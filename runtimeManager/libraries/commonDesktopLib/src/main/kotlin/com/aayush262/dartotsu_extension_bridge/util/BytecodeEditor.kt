package com.aayush262.dartotsu_extension_bridge.util

import com.aayush262.dartotsu_extension_bridge.logger.LogLevel
import com.aayush262.dartotsu_extension_bridge.logger.Logger
import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Opcodes
import org.objectweb.asm.Type
import org.objectweb.asm.tree.AbstractInsnNode
import org.objectweb.asm.tree.ClassNode
import org.objectweb.asm.tree.FieldInsnNode
import org.objectweb.asm.tree.InsnList
import org.objectweb.asm.tree.InsnNode
import org.objectweb.asm.tree.MethodInsnNode
import org.objectweb.asm.tree.MethodNode
import org.objectweb.asm.tree.TypeInsnNode
import org.objectweb.asm.tree.VarInsnNode
import org.objectweb.asm.tree.analysis.Analyzer
import org.objectweb.asm.tree.analysis.Frame
import org.objectweb.asm.tree.analysis.SourceInterpreter
import org.objectweb.asm.tree.analysis.SourceValue
import org.objectweb.asm.util.CheckClassAdapter
import java.io.PrintWriter
import java.io.StringWriter
import java.nio.file.FileSystems
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import kotlin.streams.asSequence

object BytecodeEditor {

    fun fixAndroidClasses(jarFile: Path, dexFile: Path? = null) {
        val jarLabel = jarFile.fileName?.toString() ?: jarFile.toString()
        val dexNewInstances: Map<String, List<String>> =
            dexFile?.let { DexNewInstanceOracle.load(it, jarLabel) } ?: emptyMap()

        FileSystems.newFileSystem(jarFile, null as ClassLoader?)?.use { fs ->
            val snapshot: List<Pair<Path, ByteArray>> =
                Files.walk(fs.getPath("/"))
                    .asSequence()
                    .filterNotNull()
                    .filterNot(Files::isDirectory)
                    .mapNotNull(::getClassBytes)
                    .toList()


            val binaryNameToBytes: Map<String, ByteArray> =
                snapshot.associate { (path, bytes) -> pathToBinaryName(path) to bytes }
            val loader = SnapshotClassLoader(
                binaryNameToBytes,
                Thread.currentThread().contextClassLoader ?: this::class.java.classLoader,
            )

            val classNodes = LinkedHashMap<String, ClassNode>()
            val pathByName = HashMap<String, Path>()
            val originalBytesByName = HashMap<String, ByteArray>()
            for ((path, bytes) in snapshot) {
                try {
                    val cn = ClassNode(Opcodes.ASM9)
                    ClassReader(bytes).accept(cn, ClassReader.EXPAND_FRAMES)
                    val name = cn.name
                    classNodes[name] = cn
                    pathByName[name] = path
                    originalBytesByName[name] = bytes
                } catch (e: Throwable) {
                    Logger.log(
                        "[$jarLabel] Failed to parse $path: ${e.javaClass.simpleName}: ${e.message}",
                        LogLevel.ERROR,
                    )
                }
            }



            for (cn in classNodes.values) {
                rewriteReplacedReferences(cn)
            }


            for (cn in classNodes.values) {
                fixSelfInstantiatingSingletons(cn, jarLabel)
            }


            val constructorsNeeded = LinkedHashSet<Pair<String, String>>() // (owner, desc)
            for (cn in classNodes.values) {
                repairMalformedConstructions(cn, classNodes, loader, constructorsNeeded, jarLabel, dexNewInstances)
            }
            clearErroneousAbstractFlags(classNodes, jarLabel)
            for ((owner, desc) in constructorsNeeded) {
                val target = classNodes[owner]
                if (target == null) {
                    Logger.log(
                        "[$jarLabel] Constructor needed for missing class $owner$desc, skipping",
                        LogLevel.ERROR,
                    )
                    continue
                }
                ensureConstructor(target, desc, target.superName ?: "java/lang/Object")
            }
            for ((name, cn) in classNodes) {
                val path = pathByName[name] ?: continue

                val attempt1Bytes = try {
                    val cw = ClassWriterWithLoader(ClassWriter.COMPUTE_FRAMES or ClassWriter.COMPUTE_MAXS, loader)
                    cn.accept(cw)
                    cw.toByteArray()
                } catch (e: Throwable) {
                    Logger.log(
                        "[$jarLabel] Frame computation threw for $name: ${e.javaClass.simpleName}: ${e.message}",
                        LogLevel.ERROR,
                    )
                    null
                }

                val attempt1Problems = attempt1Bytes?.let { verify(it, loader) }
                if (attempt1Bytes != null && attempt1Problems == null) {
                    write(path to attempt1Bytes)
                    continue
                }
                if (attempt1Bytes != null) {
                    Logger.log(
                        "[$jarLabel] Pattern-repaired $name still fails verification, " +
                                "falling back to frame-only recompute of the original class:\n$attempt1Problems",
                        LogLevel.ERROR,
                    )
                }

                val originalBytes = originalBytesByName[name]
                val framesOnly = originalBytes?.let { bytes ->
                    try {
                        val freshNode = ClassNode(Opcodes.ASM9)
                        ClassReader(bytes).accept(freshNode, ClassReader.EXPAND_FRAMES)
                        recomputeFramesAndVerify(freshNode, loader, jarLabel)
                    } catch (e: Throwable) {
                        Logger.log(
                            "[$jarLabel] Failed to re-parse original bytes for $name: ${e.javaClass.simpleName}: ${e.message}",
                            LogLevel.ERROR,
                        )
                        null
                    }
                }

                if (framesOnly != null) {
                    write(path to framesOnly)
                    continue
                }

                Logger.log(
                    "[$jarLabel] Frame-only recompute also failed for $name; this class likely still has an " +
                            "unresolved malformed-construction site — keeping untouched original bytes",
                    LogLevel.ERROR,
                )
            }
        } ?: Logger.log(
            "[$jarLabel] FileSystems.newFileSystem returned null — jar was NOT opened, " +
                    "nothing in this pass touched it",
            LogLevel.ERROR,
        )

        Logger.log("[$jarLabel] BytecodeEditor finished", LogLevel.INFO)
    }

    private fun pathToBinaryName(path: Path): String =
        path.toString().removePrefix("/").removeSuffix(".class").replace('/', '.')

    private class SnapshotClassLoader(
        private val classes: Map<String, ByteArray>,
        parent: ClassLoader,
    ) : ClassLoader(parent) {
        override fun findClass(name: String): Class<*> {
            val bytes = classes[name] ?: throw ClassNotFoundException(name)
            return defineClass(name, bytes, 0, bytes.size)
        }
    }

    private fun getClassBytes(path: Path): Pair<Path, ByteArray>? {
        return try {
            if (path.toString().endsWith(".class")) {
                val bytes = Files.readAllBytes(path)
                if (bytes.size < 4) return null
                val cafebabe =
                    String.format("%02X%02X%02X%02X", bytes[0], bytes[1], bytes[2], bytes[3])
                if (cafebabe.lowercase() != "cafebabe") return null
                path to bytes
            } else {
                null
            }
        } catch (e: Exception) {
            Logger.log("Error loading class from Path: $path: ${e.message}", LogLevel.ERROR)
            null
        }
    }

    private class ClassWriterWithLoader(
        flags: Int,
        private val loader: ClassLoader,
    ) : ClassWriter(flags) {
        override fun getCommonSuperClass(type1: String, type2: String): String {
            return try {
                val c1 = Class.forName(type1.replace('/', '.'), false, loader)
                val c2 = Class.forName(type2.replace('/', '.'), false, loader)
                when {
                    c1.isAssignableFrom(c2) -> type1
                    c2.isAssignableFrom(c1) -> type2
                    c1.isInterface || c2.isInterface -> "java/lang/Object"
                    else -> {
                        var x = c1
                        while (!x.isAssignableFrom(c2)) {
                            x = x.superclass
                        }
                        x.name.replace('.', '/')
                    }
                }
            } catch (_: Throwable) {
                "java/lang/Object"
            }
        }
    }

    private fun recomputeFramesAndVerify(cn: ClassNode, loader: ClassLoader, jarLabel: String): ByteArray? {
        return try {
            val cw = ClassWriterWithLoader(ClassWriter.COMPUTE_FRAMES or ClassWriter.COMPUTE_MAXS, loader)
            cn.accept(cw)
            val bytes = cw.toByteArray()
            if (verify(bytes, loader) != null) null else bytes
        } catch (e: Throwable) {
            Logger.log("[$jarLabel] Frame-only recompute failed: ${e.javaClass.simpleName}: ${e.message}", LogLevel.ERROR)
            null
        }
    }

    private fun verify(bytes: ByteArray, loader: ClassLoader): String? {
        val sw = StringWriter()
        val asmProblems = try {
            CheckClassAdapter.verify(ClassReader(bytes), loader, false, PrintWriter(sw))
            sw.toString().takeIf { it.isNotBlank() }
        } catch (e: Throwable) {
            "${e.javaClass.simpleName}: ${e.message}"
        }
        if (asmProblems != null) return asmProblems

        return try {
            val scratch = object : ClassLoader(loader) {
                fun define(b: ByteArray): Class<*> = defineClass(null, b, 0, b.size)
            }
            scratch.define(bytes)
            null
        } catch (e: VerifyError) {
            "VerifyError (real JVM verifier): ${e.message}"
        } catch (e: Throwable) {
            null
        }
    }

    private fun write(pair: Pair<Path, ByteArray>) {
        Files.write(
            pair.first,
            pair.second,
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING,
        )
    }

    private const val REPLACEMENT_PATH = "xyz/nulldev/androidcompat/replace"
    private val classesToReplace = listOf("java/text/SimpleDateFormat")

    private fun String?.replaceDirectly() =
        when (this) {
            null -> null
            in classesToReplace -> "$REPLACEMENT_PATH/$this"
            else -> this
        }

    private fun String?.replaceIndirectly(): String? {
        if (this == null) return null
        var classReference: String = this
        classesToReplace.forEach {
            classReference = classReference.replace(it, "$REPLACEMENT_PATH/$it")
        }
        return classReference
    }

    private fun rewriteReplacedReferences(cn: ClassNode) {
        for (field in cn.fields) {
            field.desc = field.desc.replaceIndirectly() ?: field.desc
        }
        for (method in cn.methods) {
            method.desc = method.desc.replaceIndirectly() ?: method.desc
            var node = method.instructions.first
            while (node != null) {
                when (node) {
                    is TypeInsnNode -> node.desc = node.desc.replaceDirectly() ?: node.desc
                    is MethodInsnNode -> {
                        node.owner = node.owner.replaceDirectly() ?: node.owner
                        node.desc = node.desc.replaceIndirectly() ?: node.desc
                    }
                    is FieldInsnNode -> node.desc = node.desc.replaceIndirectly() ?: node.desc
                    else -> {}
                }
                node = node.next
            }
        }
    }

    private fun fixSelfInstantiatingSingletons(cn: ClassNode, jarLabel: String) {
        val superName = cn.superName ?: return

        for (method in cn.methods.toList()) {
            var node = method.instructions.first
            while (node != null) {
                if (node is TypeInsnNode && node.opcode == Opcodes.NEW && node.desc == superName) {
                    val newInsn = node

                    var scan = newInsn.next
                    var invoke: MethodInsnNode? = null
                    while (scan != null) {
                        if (scan is TypeInsnNode && scan.opcode == Opcodes.NEW) break
                        if (scan is MethodInsnNode &&
                            scan.opcode == Opcodes.INVOKESPECIAL &&
                            scan.owner == superName &&
                            scan.name == "<init>"
                        ) {
                            invoke = scan
                            break
                        }
                        scan = scan.next
                    }

                    if (invoke != null) {
                        var scan2 = invoke.next
                        var store: FieldInsnNode? = null
                        while (scan2 != null) {
                            if (scan2 is TypeInsnNode && scan2.opcode == Opcodes.NEW) break
                            if (scan2 is FieldInsnNode &&
                                (scan2.opcode == Opcodes.PUTSTATIC || scan2.opcode == Opcodes.PUTFIELD) &&
                                scan2.owner == cn.name &&
                                scan2.desc == "L${cn.name};"
                            ) {
                                store = scan2
                                break
                            }
                            scan2 = scan2.next
                        }

                        if (store != null) {
                            val desc = invoke.desc
                            newInsn.desc = cn.name
                            invoke.owner = cn.name
                            ensureConstructor(cn, desc, superName)
                        }
                    }
                }
                node = node.next
            }
        }
    }

    private fun clearErroneousAbstractFlags(classNodes: Map<String, ClassNode>, jarLabel: String) {
        val instantiatedTargets = HashSet<String>()
        for (cn in classNodes.values) {
            for (method in cn.methods) {
                var node = method.instructions.first
                while (node != null) {
                    if (node is TypeInsnNode && node.opcode == Opcodes.NEW) {
                        instantiatedTargets += node.desc
                    }
                    node = node.next
                }
            }
        }
        for (target in instantiatedTargets) {
            val cn = classNodes[target] ?: continue
            val badFlags = cn.access and (Opcodes.ACC_ABSTRACT or Opcodes.ACC_INTERFACE)
            if (badFlags != 0) {
                Logger.log(
                    "[$jarLabel] Clearing erroneous abstract/interface flag on ${cn.name} " +
                            "(it is the target of a NEW elsewhere in this jar)",
                    LogLevel.INFO,
                )
                cn.access = cn.access and (Opcodes.ACC_ABSTRACT or Opcodes.ACC_INTERFACE).inv()
            }
        }
    }

    private class ProvenanceInterpreter : SourceInterpreter(Opcodes.ASM9) {
        override fun copyOperation(insn: AbstractInsnNode, value: SourceValue): SourceValue = value
    }
    private fun isConcreteInstantiable(internalName: String, loader: ClassLoader): Boolean {
        return try {
            val c = Class.forName(internalName.replace('/', '.'), false, loader)
            !c.isInterface && !java.lang.reflect.Modifier.isAbstract(c.modifiers)
        } catch (_: Throwable) {
            false
        }
    }

    private fun mostSpecificType(types: Set<String>, loader: ClassLoader): String? {
        if (types.size == 1) return types.first()
        val resolved = types.mapNotNull { t ->
            try {
                t to Class.forName(t.replace('/', '.'), false, loader)
            } catch (_: Throwable) {
                null
            }
        }
        if (resolved.size != types.size) return null
        return resolved.firstOrNull { (_, c) -> resolved.all { (_, other) -> other.isAssignableFrom(c) } }?.first
    }

   private fun isConsistentCandidate(
        candidate: String,
        requiredTypes: Set<String>,
        classNodes: Map<String, ClassNode>,
        loader: ClassLoader,
    ): Boolean {
        if (!classNodes.containsKey(candidate) || !isConcreteInstantiable(candidate, loader)) return false
        return requiredTypes.all { required ->
            try {
                val reqClass = Class.forName(required.replace('/', '.'), false, loader)
                val candClass = Class.forName(candidate.replace('/', '.'), false, loader)
                reqClass.isAssignableFrom(candClass)
            } catch (_: Throwable) {
                false
            }
        }
    }


    private fun fixDelegatingSuperCall(
        cn: ClassNode,
        method: MethodNode,
        invoke: MethodInsnNode,
        jarLabel: String,
    ) {
        if (method.name != "<init>") return
        val superName = cn.superName ?: return
        if (invoke.owner == cn.name || invoke.owner == superName) return // already legal

        val isThisCall = cn.methods.any { it.name == "<init>" && it.desc == invoke.desc && it !== method }
        val correctOwner = if (isThisCall) cn.name else superName

        invoke.owner = correctOwner
    }
    private fun resolveDexCandidate(
        requiredTypes: Set<String>,
        invokeDesc: String,
        ordinal: Int?,
        dexTypesForMethod: List<String>?,
        classNodes: Map<String, ClassNode>,
        loader: ClassLoader,
    ): String? {
        if (dexTypesForMethod == null) return null

        if (ordinal != null) {
            val positional = dexTypesForMethod.getOrNull(ordinal)
            if (positional != null && isConsistentCandidate(positional, requiredTypes, classNodes, loader)) {
                return positional
            }
        }

        val candidates = dexTypesForMethod.distinct()
            .filter { isConsistentCandidate(it, requiredTypes, classNodes, loader) }
        candidates.singleOrNull()?.let { return it }

        // Multiple sibling candidates satisfy the same weak evidence (common
        // for Filter subclasses sharing an abstract Tachiyomi base) — narrow
        // further using the actual <init> descriptor the call site uses, since
        // sibling filter subclasses rarely share a constructor shape.
        val byDesc = candidates.filter { candidateName ->
            classNodes[candidateName]?.methods?.any { it.name == "<init>" && it.desc == invokeDesc } == true
        }
        return byDesc.singleOrNull()
    }
    private fun repairMalformedConstructions(
        cn: ClassNode,
        classNodes: Map<String, ClassNode>,
        loader: ClassLoader,
        constructorsNeeded: MutableSet<Pair<String, String>>,
        jarLabel: String,
        dexNewInstances: Map<String, List<String>>,
    ) {
        for (method in cn.methods) {

            method.maxStack += method.instructions.size() + 16

            val frames: Array<Frame<SourceValue>?> = try {
                @Suppress("UNCHECKED_CAST")
                Analyzer(ProvenanceInterpreter()).analyze(cn.name, method) as Array<Frame<SourceValue>?>
            } catch (e: Throwable) {
                Logger.log(
                    "[$jarLabel] Provenance analysis failed for ${cn.name}.${method.name}${method.desc}: " +
                            "${e.javaClass.simpleName}: ${e.message}, skipping construction repair for this method",
                    LogLevel.ERROR,
                )
                continue
            }

            val insns = method.instructions
            val newOrdinal = LinkedHashMap<TypeInsnNode, Int>()
            run {
                var ordinal = 0
                for (i in 0 until insns.size()) {
                    val insn = insns.get(i)
                    if (insn is TypeInsnNode && insn.opcode == Opcodes.NEW) {
                        newOrdinal[insn] = ordinal
                        ordinal++
                    }
                }
            }

            val dexKey = "${cn.name}#${method.name}#${method.desc}"
            val dexTypesForMethod = dexNewInstances[dexKey]
            if (dexTypesForMethod != null && dexTypesForMethod.size != newOrdinal.size) {
                Logger.log(
                    "[$jarLabel] DEX oracle NEW-count mismatch for ${cn.name}.${method.name}${method.desc}: " +
                            "jar has ${newOrdinal.size}, dex has ${dexTypesForMethod.size} — positional lookups in this " +
                            "method are less trustworthy but still attempted and verified against jar-side evidence",
                    LogLevel.ERROR,
                )
            }


            val newToInit = LinkedHashMap<TypeInsnNode, MethodInsnNode>()
            for (i in 0 until insns.size()) {
                val insn = insns.get(i)
                if (insn is MethodInsnNode && insn.opcode == Opcodes.INVOKESPECIAL && insn.name == "<init>") {
                    val frame = frames.getOrNull(i)
                    if (frame == null) {
                        Logger.log(
                            "[$jarLabel] No frame at instruction $i (${cn.name}.${method.name}) for an " +
                                    "INVOKESPECIAL <init> — likely unreachable code post-analysis, skipping this call",
                            LogLevel.ERROR,
                        )
                        continue
                    }
                    val argCount = Type.getArgumentTypes(insn.desc).size
                    val receiverPos = frame.stackSize - argCount - 1
                    if (receiverPos < 0) continue
                    val producers = frame.getStack(receiverPos).insns
                    val newProducers = producers.filterIsInstance<TypeInsnNode>().filter { it.opcode == Opcodes.NEW }
                    val isInstanceMethod = (method.access and Opcodes.ACC_STATIC) == 0
                    val isThisReceiver = isInstanceMethod && frame.getStack(receiverPos) === frame.getLocal(0)
                    when {
                        newProducers.isEmpty() && isThisReceiver -> {
                            fixDelegatingSuperCall(cn, method, insn, jarLabel)
                        }
                        newProducers.isEmpty() -> {
                            // receiver is neither a NEW nor `this` (or this is a static
                            // method, where no super()/this() call is even possible) —
                            // genuinely nothing we handle here.
                        }
                        newProducers.size == producers.size -> {
                            for (producer in newProducers) {
                                newToInit[producer] = insn
                            }
                        }
                        else -> {
                            Logger.log(
                                "[$jarLabel] INVOKESPECIAL <init> receiver at ${cn.name}.${method.name}:$i has " +
                                        "mixed producers (not all NEW) — skipping pairing for this call",
                                LogLevel.ERROR,
                            )
                        }


                    }
                }
            }

            for ((newInsn, invoke) in newToInit) {
                val requiredTypes = LinkedHashSet<String>()
                requiredTypes += newInsn.desc
                requiredTypes += invoke.owner


                fun sourcedFromNew(v: SourceValue) = v.insns.contains(newInsn)

                for (i in 0 until insns.size()) {
                    val consumer = insns.get(i)
                    if (consumer === invoke) continue
                    val frame = frames.getOrNull(i) ?: continue

                    when (consumer) {
                        is InsnNode -> if (consumer.opcode == Opcodes.AASTORE && frame.stackSize >= 3) {
                            val arrayRef = frame.getStack(frame.stackSize - 3)
                            val value = frame.getStack(frame.stackSize - 1)
                            if (sourcedFromNew(value)) {
                                val arrayProducers = arrayRef.insns.filterIsInstance<TypeInsnNode>()
                                    .filter { it.opcode == Opcodes.ANEWARRAY }
                                if (arrayProducers.size == arrayRef.insns.size && arrayProducers.isNotEmpty()) {
                                    val componentTypes = arrayProducers.map { it.desc }.toSet()
                                    if (componentTypes.size == 1) requiredTypes += componentTypes.first()
                                }
                            }
                        }

                        is FieldInsnNode -> when (consumer.opcode) {
                            Opcodes.GETFIELD -> if (frame.stackSize >= 1 &&
                                sourcedFromNew(frame.getStack(frame.stackSize - 1))
                            ) {
                                requiredTypes += consumer.owner
                            }
                            Opcodes.PUTFIELD -> if (frame.stackSize >= 2) {
                                val objRef = frame.getStack(frame.stackSize - 2)
                                val value = frame.getStack(frame.stackSize - 1)
                                if (sourcedFromNew(objRef)) {
                                    requiredTypes += consumer.owner
                                } else if (sourcedFromNew(value)) {
                                    Type.getType(consumer.desc).takeIf { it.sort == Type.OBJECT }
                                        ?.internalName?.let { requiredTypes += it }
                                }
                            }
                            Opcodes.PUTSTATIC -> if (frame.stackSize >= 1 &&
                                sourcedFromNew(frame.getStack(frame.stackSize - 1))
                            ) {
                                Type.getType(consumer.desc).takeIf { it.sort == Type.OBJECT }
                                    ?.internalName?.let { requiredTypes += it }
                            }
                            else -> {}
                        }

                        is MethodInsnNode -> {
                            val argTypes = Type.getArgumentTypes(consumer.desc)
                            val isStatic = consumer.opcode == Opcodes.INVOKESTATIC
                            val totalOperands = argTypes.size + if (isStatic) 0 else 1
                            if (frame.stackSize >= totalOperands) {
                                val base = frame.stackSize - totalOperands
                                if (!isStatic && sourcedFromNew(frame.getStack(base))) {
                                    requiredTypes += consumer.owner
                                }
                                for ((argIdx, argType) in argTypes.withIndex()) {
                                    if (argType.sort != Type.OBJECT) continue
                                    val slot = base + (if (isStatic) 0 else 1) + argIdx
                                    if (sourcedFromNew(frame.getStack(slot))) {
                                        requiredTypes += argType.internalName
                                    }
                                }
                            }
                        }

                        is TypeInsnNode -> if (consumer.opcode == Opcodes.CHECKCAST &&
                            frame.stackSize >= 1 &&
                            sourcedFromNew(frame.getStack(frame.stackSize - 1))
                        ) {
                            requiredTypes += consumer.desc
                        }

                        else -> {}
                    }
                }

                val correctOwner = mostSpecificType(requiredTypes, loader)
                val ordinal = newOrdinal[newInsn]
                val dexCandidate = resolveDexCandidate(requiredTypes, invoke.desc, ordinal, dexTypesForMethod, classNodes, loader)
                when {
                    correctOwner == null && requiredTypes.size > 1 -> {
                        if (dexCandidate != null) {
                            applyConstructionFix(cn, method, newInsn, invoke, dexCandidate, constructorsNeeded, jarLabel, viaOracle = true)
                        }
                    }
                    correctOwner == null -> {}
                    !classNodes.containsKey(correctOwner) -> {

                        if (dexCandidate != null) {
                            applyConstructionFix(cn, method, newInsn, invoke, dexCandidate, constructorsNeeded, jarLabel, viaOracle = true)
                        }
                    }
                    !isConcreteInstantiable(correctOwner, loader) -> {
                        if (dexCandidate != null) {
                            applyConstructionFix(cn, method, newInsn, invoke, dexCandidate, constructorsNeeded, jarLabel, viaOracle = true)
                        }
                    }
                    else -> {
                        applyConstructionFix(cn, method, newInsn, invoke, correctOwner, constructorsNeeded, jarLabel, viaOracle = false)
                    }
                }
            }
        }
    }

    private fun applyConstructionFix(
        cn: ClassNode,
        method: MethodNode,
        newInsn: TypeInsnNode,
        invoke: MethodInsnNode,
        correctOwner: String,
        constructorsNeeded: MutableSet<Pair<String, String>>,
        jarLabel: String,
        viaOracle: Boolean,
    ) {
        val source = if (viaOracle) "DEX oracle" else "jar-side evidence"
        if (newInsn.desc != correctOwner) {
            Logger.log(
                "[$jarLabel] Repairing malformed construction in ${cn.name}.${method.name} (via $source): " +
                        "NEW ${newInsn.desc} -> NEW $correctOwner",
                LogLevel.INFO,
            )
            newInsn.desc = correctOwner
        }
        if (invoke.owner != correctOwner) {
            Logger.log(
                "[$jarLabel] Repairing malformed construction in ${cn.name}.${method.name} (via $source): " +
                        "INVOKESPECIAL ${invoke.owner}.<init> -> $correctOwner.<init>",
                LogLevel.INFO,
            )
            invoke.owner = correctOwner
        }
        constructorsNeeded += correctOwner to invoke.desc
    }

    private fun ensureConstructor(cn: ClassNode, desc: String, superName: String) {
        if (cn.methods.any { it.name == "<init>" && it.desc == desc }) return

        val ctor = MethodNode(Opcodes.ASM9, Opcodes.ACC_PUBLIC, "<init>", desc, null, null)
        val insns = InsnList()
        insns.add(VarInsnNode(Opcodes.ALOAD, 0))

        var localIndex = 1
        for (argType in Type.getArgumentTypes(desc)) {
            insns.add(VarInsnNode(argType.getOpcode(Opcodes.ILOAD), localIndex))
            localIndex += argType.size
        }
        insns.add(MethodInsnNode(Opcodes.INVOKESPECIAL, superName, "<init>", desc, false))
        insns.add(InsnNode(Opcodes.RETURN))

        ctor.instructions = insns
        ctor.maxStack = localIndex
        ctor.maxLocals = localIndex

        cn.methods.add(ctor)

    }
}
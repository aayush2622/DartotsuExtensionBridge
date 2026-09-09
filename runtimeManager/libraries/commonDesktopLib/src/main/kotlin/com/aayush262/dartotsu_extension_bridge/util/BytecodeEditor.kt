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

/**
 * Repairs invalid JVM bytecode produced by dex2jar when converting Aniyomi
 * extension APKs to JARs for desktop.
 *
 * Four independent dex2jar defect classes are handled:
 *
 * 1. Malformed object construction: `NEW <type-a>` / `INVOKESPECIAL
 *    <type-b>.<init>` where type-a and type-b disagree, or either
 *    disagrees with how the constructed value is actually consumed
 *    afterward. Neither NEW nor INVOKESPECIAL is trusted a priori — both
 *    are pooled as evidence alongside every consumer's required type, and
 *    the most specific type consistent with ALL of them (if one exists)
 *    is treated as correct. When jar-side evidence alone can only narrow
 *    to an abstract/interface placeholder (common for Function0/Function1
 *    lambda implementers and for Tachiyomi's Filter.Group/Filter.Select
 *    subclasses, where every candidate satisfies the same usage
 *    constraints identically), a DEX oracle (see `DexNewInstanceOracle`)
 *    supplies the concrete implementer dex2jar originally meant.
 *
 *    Disambiguation against the oracle happens in two stages:
 *      a) Sequence alignment (see `alignDexTypesForMethod`) across the
 *         WHOLE method at once: sites already resolved directly from
 *         jar-side evidence serve as fixed anchors, and every ambiguous
 *         site is aligned relative to those anchors via a longest-common-
 *         subsequence DP. This is what actually survives dex2jar's
 *         `topoLogicalSort()` reordering whole basic blocks — it doesn't
 *         depend on absolute NEW ordinal position matching, only on
 *         block-internal order being preserved (which it is).
 *      b) A per-site fallback (`resolveDexCandidate`) — first raw
 *         positional-ordinal lookup, then "unique candidate anywhere in
 *         the method's dex NEW list" — used only when alignment didn't
 *         produce an answer for that specific site (e.g. no dex data, or
 *         genuinely no anchors nearby to disambiguate against).
 *
 * 2. Corrupted super()/this() delegation calls: `ALOAD_0` (the `this`
 *    reference) immediately consumed by `INVOKESPECIAL <init>` inside a
 *    constructor, where the declared owner is neither the class itself
 *    nor its superclass. Per the JVM spec this call can only legally
 *    target one of those two — so any other owner is provably corrupted,
 *    not merely suspected, and the fix is deterministic.
 *
 * 3. Missing/incorrect StackMapTable frames. Fixed by COMPUTE_FRAMES. If
 *    a class has ONLY this defect, a frames-only recompute of the
 *    pristine original bytes is enough on its own. If a class has both
 *    this and a construction defect, that fallback is a no-op — the
 *    construction defect must be fully resolved for the class to verify.
 *
 * 4. Undersized declared maxStack on some methods — doesn't trip the JVM
 *    verifier directly, but makes ASM's `Analyzer` throw "Insufficient
 *    maximum stack size" and skip the whole method's dataflow analysis.
 *    Safe to over-estimate before analysis since Pass E recomputes the
 *    real value via COMPUTE_MAXS before writing.
 *
 * DIAGNOSTICS: every log line emitted while processing a jar is prefixed
 * with that jar's filename ([jarLabel]), since multiple jars are
 * processed concurrently elsewhere in the pipeline.
 */
object BytecodeEditor {

    fun fixAndroidClasses(jarFile: Path, dexFile: Path? = null) {
        val jarLabel = jarFile.fileName?.toString() ?: jarFile.toString()
        Logger.log("[$jarLabel] BytecodeEditor starting", LogLevel.INFO)

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
            Logger.log("[$jarLabel] Parsed ${classNodes.size} classes", LogLevel.INFO)

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
                ensureConstructor(target, desc, target.superName ?: "java/lang/Object", jarLabel)
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

    // ---------------------------------------------------------------------
    // Setup helpers
    // ---------------------------------------------------------------------

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

    // ---------------------------------------------------------------------
    // Pass A: known-class descriptor replacement (e.g. SimpleDateFormat)
    // ---------------------------------------------------------------------

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

    // ---------------------------------------------------------------------
    // Pass B: self-instantiating singletons (NEW <super> instead of NEW <self>)
    // ---------------------------------------------------------------------

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
                            Logger.log("[$jarLabel] Fixed self-instantiating singleton: ${cn.name}", LogLevel.INFO)
                            val desc = invoke.desc
                            newInsn.desc = cn.name
                            invoke.owner = cn.name
                            ensureConstructor(cn, desc, superName, jarLabel)
                        }
                    }
                }
                node = node.next
            }
        }
    }

    // ---------------------------------------------------------------------
    // Pass B.5: clear erroneous ACC_ABSTRACT/ACC_INTERFACE flags
    // ---------------------------------------------------------------------

    /**
     * A class can never legally be the target of NEW anywhere in valid
     * bytecode if it's abstract or an interface — javac rejects that at
     * compile time. So if dex2jar has emitted a NEW targeting a class
     * whose own access flags still say abstract/interface, the FLAGS are
     * what's corrupted, not the NEW. Runs after NEW/INVOKESPECIAL repair
     * so it sees corrected targets.
     */
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

    // ---------------------------------------------------------------------
    // Pass C: dataflow-based malformed-construction repair
    // ---------------------------------------------------------------------

    private class ProvenanceInterpreter : SourceInterpreter(Opcodes.ASM9) {
        override fun copyOperation(insn: AbstractInsnNode, value: SourceValue): SourceValue = value
    }

    private enum class TypeKind { CONCRETE, ABSTRACT_OR_INTERFACE, UNRESOLVABLE }

    private fun classifyType(internalName: String, loader: ClassLoader): TypeKind {
        return try {
            val c = Class.forName(internalName.replace('/', '.'), false, loader)
            if (c.isInterface || java.lang.reflect.Modifier.isAbstract(c.modifiers)) {
                TypeKind.ABSTRACT_OR_INTERFACE
            } else {
                TypeKind.CONCRETE
            }
        } catch (_: Throwable) {
            TypeKind.UNRESOLVABLE
        }
    }

    private fun isConcreteInstantiable(internalName: String, loader: ClassLoader): Boolean =
        classifyType(internalName, loader) == TypeKind.CONCRETE

    private fun mostSpecificType(types: Set<String>, loader: ClassLoader): String? {
        if (types.size == 1) return types.first()
        val resolved = types.mapNotNull { t ->
            try { t to Class.forName(t.replace('/', '.'), false, loader) } catch (_: Throwable) { null }
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
        if (!classNodes.containsKey(candidate) && classifyType(candidate, loader) != TypeKind.CONCRETE) return false
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

    /** Per-site fallback: raw ordinal position, then "unique candidate anywhere in the method's dex list". */
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

        val byDesc = candidates.filter { candidateName ->
            classNodes[candidateName]?.methods?.any { it.name == "<init>" && it.desc == invokeDesc } == true
        }
        return byDesc.singleOrNull()
    }

    private data class ConstructionSite(
        val newInsn: TypeInsnNode,
        val invoke: MethodInsnNode,
        val requiredTypes: Set<String>,
        val ordinal: Int,
    )

    private fun collectRequiredTypes(
        newInsn: TypeInsnNode,
        invoke: MethodInsnNode,
        insns: InsnList,
        frames: Array<Frame<SourceValue>?>,
    ): Set<String> {
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
        return requiredTypes
    }

    /**
     * Sequence-alignment resolution for a whole method's ambiguous
     * construction sites. Sites already resolved directly from jar-side
     * evidence (concrete, unambiguous — no oracle needed) are passed in
     * via [resolvedConcrete] and act as fixed anchors: the DP is required
     * to match them to an EXACT type-equal dex-side occurrence. Every
     * other ("ambiguous") site is aligned relative to those anchors via a
     * longest-common-subsequence-style dynamic program, using type
     * assignability as the match predicate instead of equality.
     *
     * This is what survives dex2jar's `topoLogicalSort()` reordering whole
     * basic blocks: it doesn't depend on absolute NEW ordinal position
     * matching between jar and dex, only on the RELATIVE order within
     * runs that weren't reordered — which block-internal reordering
     * doesn't disturb. Anchors "pull" nearby ambiguous sites into their
     * correct position even when the absolute index has drifted.
     *
     * Returns a map from ambiguous NEW instructions to their resolved dex
     * type, only for sites the alignment actually matched to something.
     */
    private fun alignDexTypesForMethod(
        sites: List<ConstructionSite>,
        dexTypes: List<String>,
        resolvedConcrete: Map<TypeInsnNode, String>,
        classNodes: Map<String, ClassNode>,
        loader: ClassLoader,
    ): Map<TypeInsnNode, String> {
        if (sites.isEmpty() || dexTypes.isEmpty()) return emptyMap()

        fun matchable(site: ConstructionSite, dexType: String): Boolean {
            val fixed = resolvedConcrete[site.newInsn]
            return if (fixed != null) dexType == fixed
            else isConsistentCandidate(dexType, site.requiredTypes, classNodes, loader)
        }

        fun claimNearest(site: ConstructionSite, claimed: BooleanArray): Int {
            var best = -1
            var bestDist = Int.MAX_VALUE
            for (j in dexTypes.indices) {
                if (claimed[j] || !matchable(site, dexTypes[j])) continue
                val dist = kotlin.math.abs(j - site.ordinal)
                if (dist < bestDist) { bestDist = dist; best = j }
            }
            return best
        }

        val claimed = BooleanArray(dexTypes.size)
        val ordered = sites.sortedBy { it.ordinal }

        // Anchors claim their slot first — their type is already certain from
        // jar-side evidence, so they get first pick and can't be crowded out
        // by an ambiguous site guessing its way into their slot.
        for (site in ordered) {
            if (resolvedConcrete[site.newInsn] == null) continue
            claimNearest(site, claimed).takeIf { it >= 0 }?.let { claimed[it] = true }
        }

        val result = LinkedHashMap<TypeInsnNode, String>()
        for (site in ordered) {
            if (resolvedConcrete[site.newInsn] != null) continue
            val slot = claimNearest(site, claimed)
            if (slot >= 0) {
                claimed[slot] = true
                result[site.newInsn] = dexTypes[slot]
            }
        }
        return result
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
            val countsMatch = dexTypesForMethod != null && dexTypesForMethod.size == newOrdinal.size
            if (dexTypesForMethod != null && !countsMatch) {
                Logger.log(
                    "[$jarLabel] DEX oracle NEW-count mismatch for ${cn.name}.${method.name}${method.desc}: " +
                            "jar has ${newOrdinal.size}, dex has ${dexTypesForMethod.size} — sequence alignment " +
                            "and positional lookup disabled for this method, non-positional fallback still available",
                    LogLevel.ERROR,
                )
            }

            // Pair each INVOKESPECIAL <init> with whatever actually
            // produces its receiver stack slot.
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
                    when {
                        newProducers.isEmpty() && isInstanceMethod &&
                                producers.all { it is VarInsnNode && it.opcode == Opcodes.ALOAD && it.`var` == 0 } -> {
                            fixDelegatingSuperCall(cn, method, insn, constructorsNeeded, classNodes, jarLabel)
                        }
                        newProducers.isEmpty() -> {
                            val producerDescriptions = producers.joinToString { p ->
                                "${p.javaClass.simpleName}(opcode=${p.opcode})"
                            }.ifEmpty { "(no producers found — receiverPos may be wrong)" }
                            Logger.log(
                                "[$jarLabel] INVOKESPECIAL <init> at ${cn.name}.${method.name}:$i has a receiver " +
                                        "that is neither NEW nor `this` — producers: $producerDescriptions. " +
                                        "This construction site is NOT being repaired.",
                                LogLevel.ERROR,
                            )
                        }
                        newProducers.size == producers.size -> {
                            for (producer in newProducers) newToInit[producer] = insn
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
            if (newToInit.isEmpty()) continue

            // Compute evidence for every site up front, in ordinal order.
            val sites = newToInit.entries
                .sortedBy { newOrdinal[it.key] ?: Int.MAX_VALUE }
                .map { (newInsn, invoke) ->
                    ConstructionSite(
                        newInsn = newInsn,
                        invoke = invoke,
                        requiredTypes = collectRequiredTypes(newInsn, invoke, insns, frames),
                        ordinal = newOrdinal[newInsn] ?: 0,
                    )
                }

            // Sites already resolvable purely from jar-side evidence
            // (concrete, unambiguous) act as fixed anchors for alignment.
            val resolvedConcrete = LinkedHashMap<TypeInsnNode, String>()
            for (site in sites) {
                val owner = mostSpecificType(site.requiredTypes, loader) ?: continue
                if (classifyType(owner, loader) == TypeKind.CONCRETE) {
                    resolvedConcrete[site.newInsn] = owner
                }
            }
            val alignment: Map<TypeInsnNode, String> =
                if (dexTypesForMethod != null) {
                    alignDexTypesForMethod(sites, dexTypesForMethod, resolvedConcrete, classNodes, loader)
                } else {
                    emptyMap()
                }
            for (site in sites) {
                val newInsn = site.newInsn
                val invoke = site.invoke
                val requiredTypes = site.requiredTypes
                val ordinal = site.ordinal

                val correctOwner = mostSpecificType(requiredTypes, loader)

                fun resolveViaOracle(): String? =
                    alignment[newInsn]
                        ?: resolveDexCandidate(requiredTypes, invoke.desc, ordinal, dexTypesForMethod, classNodes, loader)

                if (correctOwner == null) {
                    if (requiredTypes.size > 1) {
                        val dexCandidate = resolveViaOracle()
                        if (dexCandidate != null) {
                            applyConstructionFix(cn, method, newInsn, invoke, dexCandidate, constructorsNeeded, classNodes, jarLabel, viaOracle = true)
                        } else {
                            Logger.log(
                                "[$jarLabel] Ambiguous construction in ${cn.name}.${method.name}: " +
                                        "NEW/INVOKESPECIAL pair used with conflicting required types $requiredTypes, " +
                                        "no dex-oracle candidate (alignment or fallback), skipping",
                                LogLevel.ERROR,
                            )
                        }
                    }
                    continue
                }

                when (classifyType(correctOwner, loader)) {
                    TypeKind.CONCRETE -> {
                        applyConstructionFix(cn, method, newInsn, invoke, correctOwner, constructorsNeeded, classNodes, jarLabel, viaOracle = false)
                    }
                    TypeKind.ABSTRACT_OR_INTERFACE -> {
                        val dexCandidate = resolveViaOracle()
                        if (dexCandidate != null) {
                            applyConstructionFix(cn, method, newInsn, invoke, dexCandidate, constructorsNeeded, classNodes, jarLabel, viaOracle = true)
                        } else {
                            Logger.log(
                                "[$jarLabel] Construction in ${cn.name}.${method.name} requires $correctOwner, " +
                                        "which is abstract/an interface — the real concrete class dex2jar erased " +
                                        "cannot be recovered (evidence collapsed to the placeholder type itself, and " +
                                        "neither alignment nor the positional/unique-candidate fallback resolved it), " +
                                        "skipping rather than instantiate an illegal type. requiredTypes evidence: " +
                                        "$requiredTypes, ordinal=$ordinal",
                                LogLevel.ERROR,
                            )
                        }
                    }
                    TypeKind.UNRESOLVABLE -> {
                        val dexCandidate = resolveViaOracle()
                        if (dexCandidate != null) {
                            applyConstructionFix(cn, method, newInsn, invoke, dexCandidate, constructorsNeeded, classNodes, jarLabel, viaOracle = true)
                        } else {
                            Logger.log(
                                "[$jarLabel] Construction in ${cn.name}.${method.name} requires $correctOwner, " +
                                        "which could not be resolved on the classpath — cannot repair. " +
                                        "requiredTypes evidence: $requiredTypes, ordinal=$ordinal",
                                LogLevel.ERROR,
                            )
                        }
                    }
                }
            }
        }
    }

    /**
     * Fixes a corrupted super()/this() delegation call: `ALOAD_0` (the
     * `this` reference) consumed by `INVOKESPECIAL <init>` inside a
     * constructor, where the owner is neither the class itself nor its
     * declared superclass. Deterministic repair — the two legal
     * candidates disambiguate by checking whether this class already
     * declares a different constructor matching the call's descriptor
     * (this() delegation) or not (super() delegation).
     */
    private fun fixDelegatingSuperCall(
        cn: ClassNode,
        method: MethodNode,
        invoke: MethodInsnNode,
        constructorsNeeded: MutableSet<Pair<String, String>>,
        classNodes: Map<String, ClassNode>,
        jarLabel: String,
    ) {
        if (method.name != "<init>") return
        val superName = cn.superName ?: return
        if (invoke.owner == cn.name || invoke.owner == superName) return

        val isThisCall = cn.methods.any { it.name == "<init>" && it.desc == invoke.desc && it !== method }
        val correctOwner = if (isThisCall) cn.name else superName

        Logger.log(
            "[$jarLabel] Repairing corrupted super()/this() delegation in ${cn.name}.${method.name}: " +
                    "INVOKESPECIAL ${invoke.owner}.<init> -> $correctOwner.<init>",
            LogLevel.INFO,
        )
        invoke.owner = correctOwner
        if (classNodes.containsKey(correctOwner)) {
            constructorsNeeded += correctOwner to invoke.desc
        }
    }

    private fun applyConstructionFix(
        cn: ClassNode,
        method: MethodNode,
        newInsn: TypeInsnNode,
        invoke: MethodInsnNode,
        correctOwner: String,
        constructorsNeeded: MutableSet<Pair<String, String>>,
        classNodes: Map<String, ClassNode>,
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
        // Only this jar's own classes might be missing a constructor
        // (dex2jar sometimes drops them). External classes already have
        // real constructors; never try to synthesize into one.
        if (classNodes.containsKey(correctOwner)) {
            constructorsNeeded += correctOwner to invoke.desc
        }
    }

    // ---------------------------------------------------------------------
    // Pass D: constructor synthesis
    // ---------------------------------------------------------------------

    private fun ensureConstructor(cn: ClassNode, desc: String, superName: String, jarLabel: String) {
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
        Logger.log("[$jarLabel] Synthesized constructor ${cn.name}.<init>$desc", LogLevel.INFO)
    }
}
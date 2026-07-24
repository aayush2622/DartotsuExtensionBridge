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
 * Three independent dex2jar defect classes are handled:
 *
 * 1. Malformed object construction: `NEW <type-a>` / `INVOKESPECIAL
 *    <type-b>.<init>` where type-a and type-b disagree, or either
 *    disagrees with how the constructed value is actually consumed
 *    afterward (as a PUTFIELD/PUTSTATIC target, a CHECKCAST target, or a
 *    method receiver/argument). Corruption has been observed in BOTH
 *    directions — sometimes NEW is wrong and INVOKESPECIAL is correct,
 *    sometimes the reverse — so neither side is trusted a priori. Instead
 *    NEW's type, INVOKESPECIAL's owner, and every consumer's required
 *    type are all pooled as evidence, and the most specific type
 *    consistent with ALL of them (if one exists) is treated as correct;
 *    whichever side(s) disagree with it get corrected. Detecting consumer
 *    requirements needs real dataflow analysis, not linear instruction-
 *    order scanning — a value can be aliased through locals, duplicated
 *    via DUP, and consumed as either operand of a PUTFIELD — so this uses
 *    ASM's own stack-frame simulation (`Analyzer<SourceValue>`) with a
 *    provenance-preserving interpreter. Fixing this may require
 *    synthesizing a constructor in a *different* class than the one being
 *    rewritten, so the whole jar is parsed into a shared
 *    `Map<String, ClassNode>` first.
 *
 * 2. Missing/incorrect StackMapTable frames. Unrelated to (1); fixed by
 *    COMPUTE_FRAMES. If a class has ONLY this defect, a frames-only
 *    recompute of the pristine original bytes is enough on its own. If a
 *    class has BOTH defects, that fallback is a no-op — (1) must be fully
 *    resolved for the class to verify at all.
 *
 * 3. Undersized declared maxStack on some methods, which is a separate
 *    dex2jar defect from (2) — it doesn't trip the JVM verifier directly,
 *    but it DOES make ASM's own `Analyzer` (used for (1)'s dataflow) throw
 *    "Insufficient maximum stack size" and skip the whole method. Since
 *    Pass E always recomputes the real maxStack via COMPUTE_MAXS before
 *    writing, it's safe to generously over-estimate it before running the
 *    analyzer in Pass C, purely to give it room to simulate correctly.
 */
object BytecodeEditor {

    fun fixAndroidClasses(jarFile: Path) {
        FileSystems.newFileSystem(jarFile, null as ClassLoader?)?.use { fs ->
            // 1. Snapshot every class's ORIGINAL bytes into memory first.
            val snapshot: List<Pair<Path, ByteArray>> =
                Files.walk(fs.getPath("/"))
                    .asSequence()
                    .filterNotNull()
                    .filterNot(Files::isDirectory)
                    .mapNotNull(::getClassBytes)
                    .toList()

            // 2. Build a classloader backed ONLY by that in-memory snapshot.
            val binaryNameToBytes: Map<String, ByteArray> =
                snapshot.associate { (path, bytes) -> pathToBinaryName(path) to bytes }
            val loader = SnapshotClassLoader(
                binaryNameToBytes,
                Thread.currentThread().contextClassLoader ?: this::class.java.classLoader,
            )

            // 3. Parse every class into a shared ClassNode map, so a fix
            //    discovered in one class (e.g. `q`) can synthesize a
            //    constructor in a different class (e.g. `p`).
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
                        "Failed to parse $path: ${e.javaClass.simpleName}: ${e.message}",
                        LogLevel.ERROR,
                    )
                }
            }

            // 4. Pass A — descriptor/type-reference rewriting for the known
            //    always-replace classes (e.g. SimpleDateFormat -> shim).
            for (cn in classNodes.values) {
                rewriteReplacedReferences(cn)
            }

            // 5. Pass B — self-instantiating singleton fix (NEW <super>
            //    where it should be NEW <self>). Kept as a narrow, cheap
            //    first pass; Pass C's dataflow analysis would also catch
            //    this shape (a static/field store of the class's own type
            //    is just one more required-type signal), so this is
            //    intentionally redundant defense-in-depth, not load-bearing.
            for (cn in classNodes.values) {
                fixSelfInstantiatingSingletons(cn)
            }

            // 6. Pass C — dataflow-based malformed-construction repair.
            val constructorsNeeded = LinkedHashSet<Pair<String, String>>() // (owner, desc)
            for (cn in classNodes.values) {
                repairMalformedConstructions(cn, classNodes, loader, constructorsNeeded)
            }

            // 7. Pass D — synthesize any constructors passes B/C required.
            for ((owner, desc) in constructorsNeeded) {
                val target = classNodes[owner]
                if (target == null) {
                    Logger.log(
                        "Constructor needed for missing class $owner$desc, skipping",
                        LogLevel.ERROR,
                    )
                    continue
                }
                ensureConstructor(target, desc, target.superName ?: "java/lang/Object")
            }

            // 8. Pass E — recompute frames, verify, write, with layered
            //    fallback: repaired -> frames-only original -> untouched.
            for ((name, cn) in classNodes) {
                val path = pathByName[name] ?: continue

                val attempt1Bytes = try {
                    val cw = ClassWriterWithLoader(ClassWriter.COMPUTE_FRAMES or ClassWriter.COMPUTE_MAXS, loader)
                    cn.accept(cw)
                    cw.toByteArray()
                } catch (e: Throwable) {
                    Logger.log(
                        "Frame computation threw for $name: ${e.javaClass.simpleName}: ${e.message}",
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
                        "Pattern-repaired $name still fails verification, " +
                                "falling back to frame-only recompute of the original class:\n$attempt1Problems",
                        LogLevel.ERROR,
                    )
                }

                val originalBytes = originalBytesByName[name]
                val framesOnly = originalBytes?.let { bytes ->
                    try {
                        val freshNode = ClassNode(Opcodes.ASM9)
                        ClassReader(bytes).accept(freshNode, ClassReader.EXPAND_FRAMES)
                        recomputeFramesAndVerify(freshNode, loader)
                    } catch (e: Throwable) {
                        Logger.log(
                            "Failed to re-parse original bytes for $name: ${e.javaClass.simpleName}: ${e.message}",
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
                    "Frame-only recompute also failed for $name; this class likely still has an " +
                            "unresolved malformed-construction site — keeping untouched original bytes",
                    LogLevel.ERROR,
                )
            }
        }
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

    private fun recomputeFramesAndVerify(cn: ClassNode, loader: ClassLoader): ByteArray? {
        return try {
            val cw = ClassWriterWithLoader(ClassWriter.COMPUTE_FRAMES or ClassWriter.COMPUTE_MAXS, loader)
            cn.accept(cw)
            val bytes = cw.toByteArray()
            if (verify(bytes, loader) != null) null else bytes
        } catch (e: Throwable) {
            Logger.log("Frame-only recompute failed: ${e.javaClass.simpleName}: ${e.message}", LogLevel.ERROR)
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

        // ASM's checker can pass bytecode the real JVM verifier rejects
        // (seen with dex2jar tableswitch/frame edge cases). Confirm with
        // an actual defineClass so we get the JVM's own verifier.
        return try {
            val scratch = object : ClassLoader(loader) {
                fun define(b: ByteArray): Class<*> = defineClass(null, b, 0, b.size)
            }
            scratch.define(bytes)
            null
        } catch (e: VerifyError) {
            "VerifyError (real JVM verifier): ${e.message}"
        } catch (e: Throwable) {
            // LinkageError etc. from unrelated missing deps shouldn't fail
            // verification — only VerifyError is the signal we want here.
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

    private fun fixSelfInstantiatingSingletons(cn: ClassNode) {
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
                            Logger.log("Fixed self-instantiating singleton: ${cn.name}", LogLevel.INFO)
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

    // ---------------------------------------------------------------------
    // Pass C: dataflow-based malformed-construction repair
    // ---------------------------------------------------------------------

    /**
     * A SourceInterpreter that preserves value provenance through
     * ALOAD/ASTORE/DUP/SWAP instead of resetting it to "produced by this
     * instruction" (SourceInterpreter's default `copyOperation`). This is
     * what lets us trace a constructed object back to its `NEW` across
     * local-variable aliasing and stack duplication, precisely and without
     * guessing from instruction adjacency.
     */
    private class ProvenanceInterpreter : SourceInterpreter(Opcodes.ASM9) {
        override fun copyOperation(insn: AbstractInsnNode, value: SourceValue): SourceValue = value
    }

    /** A NEW target must be a concrete, instantiable class — never an interface or abstract class. */
    private fun isConcreteInstantiable(internalName: String, loader: ClassLoader): Boolean {
        return try {
            val c = Class.forName(internalName.replace('/', '.'), false, loader)
            !c.isInterface && !java.lang.reflect.Modifier.isAbstract(c.modifiers)
        } catch (_: Throwable) {
            false // unresolvable — treat as unsafe rather than guess
        }
    }

    /**
     * Returns the type in [types] that every other type in the set is a
     * supertype of (i.e. the most specific/narrowest type consistent with
     * all evidence), or null if no such type exists (genuine ambiguity, or
     * an unresolvable type — resolution can fail even for real classes if
     * a transitive dependency isn't on the snapshot classloader, which is
     * deliberately treated as "can't safely resolve" rather than guessed).
     * With a single type, that type is trivially the answer.
     */
    private fun mostSpecificType(types: Set<String>, loader: ClassLoader): String? {
        if (types.size == 1) return types.first()
        val resolved = types.mapNotNull { t ->
            try { t to Class.forName(t.replace('/', '.'), false, loader) } catch (_: Throwable) { null }
        }
        if (resolved.size != types.size) return null
        return resolved.firstOrNull { (_, c) -> resolved.all { (_, other) -> other.isAssignableFrom(c) } }?.first
    }

    private fun repairMalformedConstructions(
        cn: ClassNode,
        classNodes: Map<String, ClassNode>,
        loader: ClassLoader,
        constructorsNeeded: MutableSet<Pair<String, String>>,
    ) {
        for (method in cn.methods) {
            // See class-level doc point 3: dex2jar sometimes declares a
            // maxStack too small for the analyzer to simulate the method,
            // even though the bytecode itself is fine. Over-estimate it
            // here — Pass E recomputes the real value via COMPUTE_MAXS
            // before writing, so this has no effect on the final output,
            // it only gives the analyzer room to work.
            method.maxStack = method.maxStack + method.instructions.size() + 16

            val frames: Array<Frame<SourceValue>?> = try {
                @Suppress("UNCHECKED_CAST")
                Analyzer(ProvenanceInterpreter()).analyze(cn.name, method) as Array<Frame<SourceValue>?>
            } catch (e: Throwable) {
                Logger.log(
                    "Provenance analysis failed for ${cn.name}.${method.name}${method.desc}: " +
                            "${e.javaClass.simpleName}: ${e.message}, skipping construction repair for this method",
                    LogLevel.ERROR,
                )
                continue
            }

            val insns = method.instructions

            // Pair each NEW with its <init> by checking, at the exact
            // invoke instruction, which value actually occupies the
            // receiver stack slot — not "whichever invoke comes next".
            // This pairing is done purely by dataflow position; it does
            // NOT assume either side's declared type is correct.
            val newToInit = LinkedHashMap<TypeInsnNode, MethodInsnNode>()
            for (i in 0 until insns.size()) {
                val insn = insns.get(i)
                if (insn is MethodInsnNode && insn.opcode == Opcodes.INVOKESPECIAL && insn.name == "<init>") {
                    val frame = frames.getOrNull(i) ?: continue
                    val argCount = Type.getArgumentTypes(insn.desc).size
                    val receiverPos = frame.stackSize - argCount - 1
                    if (receiverPos < 0) continue
                    val producers = frame.getStack(receiverPos).insns
                    if (producers.size == 1) {
                        val producer = producers.iterator().next()
                        if (producer is TypeInsnNode && producer.opcode == Opcodes.NEW) {
                            newToInit[producer] = insn
                        }
                    }
                }
            }

            for ((newInsn, invoke) in newToInit) {
                // NEW's declared type and INVOKESPECIAL's owner are both
                // evidence, not assumed-correct anchors — corruption has
                // been observed in both directions (NEW wrong / invoke
                // correct, and the reverse). Whichever one disagrees with
                // the final answer gets corrected below.
                val requiredTypes = LinkedHashSet<String>()
                requiredTypes += newInsn.desc
                requiredTypes += invoke.owner

                for (i in 0 until insns.size()) {
                    val consumer = insns.get(i)
                    if (consumer === invoke) continue // the pairing init isn't independent evidence
                    val frame = frames.getOrNull(i) ?: continue

                    fun sourcedFromNew(v: SourceValue) = v.insns.size == 1 && v.insns.contains(newInsn)

                    when (consumer) {
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
                when {
                    correctOwner == null && requiredTypes.size > 1 -> {
                        Logger.log(
                            "Ambiguous construction in ${cn.name}.${method.name}: " +
                                    "NEW/INVOKESPECIAL pair used with conflicting required types $requiredTypes, skipping",
                            LogLevel.ERROR,
                        )
                    }
                    correctOwner == null -> {} // unresolvable type, nothing safe to do
                    correctOwner == newInsn.desc && correctOwner == invoke.owner -> {} // already consistent
                    !classNodes.containsKey(correctOwner) -> {
                        Logger.log(
                            "Construction in ${cn.name}.${method.name} requires $correctOwner, which isn't " +
                                    "part of this jar — cannot repair (external dependency)",
                            LogLevel.ERROR,
                        )
                    }
                    !isConcreteInstantiable(correctOwner, loader) -> {
                        Logger.log(
                            "Construction in ${cn.name}.${method.name} appears to require $correctOwner, but " +
                                    "that type is abstract/an interface — the real concrete class dex2jar erased " +
                                    "cannot be recovered from usage alone, skipping rather than instantiate an " +
                                    "illegal type",
                            LogLevel.ERROR,
                        )
                    }
                    else -> {
                        if (newInsn.desc != correctOwner) {
                            Logger.log(
                                "Repairing malformed construction in ${cn.name}.${method.name}: " +
                                        "NEW ${newInsn.desc} -> NEW $correctOwner",
                                LogLevel.INFO,
                            )
                            newInsn.desc = correctOwner
                        }
                        if (invoke.owner != correctOwner) {
                            Logger.log(
                                "Repairing malformed construction in ${cn.name}.${method.name}: " +
                                        "INVOKESPECIAL ${invoke.owner}.<init> -> $correctOwner.<init>",
                                LogLevel.INFO,
                            )
                            invoke.owner = correctOwner
                        }
                        constructorsNeeded += correctOwner to invoke.desc
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Pass D: constructor synthesis
    // ---------------------------------------------------------------------

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
        Logger.log("Synthesized constructor ${cn.name}.<init>$desc", LogLevel.INFO)
    }
}
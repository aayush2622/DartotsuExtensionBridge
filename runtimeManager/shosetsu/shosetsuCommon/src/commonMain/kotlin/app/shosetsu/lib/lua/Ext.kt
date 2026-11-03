package app.shosetsu.lib.lua

import org.luaj.vm2.LuaTable
import org.luaj.vm2.LuaValue
import org.luaj.vm2.lib.jse.CoerceJavaToLua
import org.luaj.vm2.lib.jse.CoerceLuaToJava

/*
 * shosetsu-kotlin-lib
 * 06 / 10 / 2020
 */

/** Convenient kotlin function to convert a value to a jvm value */
inline fun <reified T> coerceLuaToJava(value: LuaValue): T =
	CoerceLuaToJava.coerce(value, T::class.java) as T

/** Converts a [Map] to a [LuaTable] */
fun Map<Int, *>.toLua(): LuaTable = LuaTable().also {
	this.forEach { (i, any) -> it[i] = CoerceJavaToLua.coerce(any) }
}

/** Converts a [Map] to a [LuaTable] */
fun Array<*>.toLua(): LuaTable = LuaTable().also { table ->
	this
		.map { CoerceJavaToLua.coerce(it) }
		.forEachIndexed { i, v -> table[i] = v }
}

/** Converts [Array] of anything to [LuaTable] */
fun Array<*>.toLua(oneIndex: Boolean): LuaTable = LuaTable().also { table ->
	this
		.map { CoerceJavaToLua.coerce(it) }
		.forEachIndexed { i, v -> table[if (oneIndex) i + 1 else i] = v }
}

fun extractMetaDataSection(content: String): String {
	val line = content.lines().first().trim()
	if (!line.startsWith("--")) {
		throw IllegalArgumentException("Metadata section must be in the first line and start with --")
	}
	return line.substring(2).trimStart()
}

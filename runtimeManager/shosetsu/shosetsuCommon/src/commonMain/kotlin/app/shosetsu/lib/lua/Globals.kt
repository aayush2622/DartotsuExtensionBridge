package app.shosetsu.lib.lua

import app.shosetsu.lib.Extension
import app.shosetsu.lib.PAGE_INDEX
import app.shosetsu.lib.QUERY_INDEX
import org.luaj.vm2.*
import org.luaj.vm2.compiler.LuaC
import org.luaj.vm2.lib.*
import org.luaj.vm2.lib.jse.JseBaseLib
import org.luaj.vm2.lib.jse.JseMathLib
import org.luaj.vm2.lib.jse.JseOsLib
import org.luaj.vm2.lib.jse.LuajavaLib

// 06 / 10 / 2020

/**
 * Global values that are passed into lua with [shosetsuGlobals]
 */
val SHOSETSU_GLOBALS: Map<String, LuaValue> =
	mapOf<String, LuaValue>(
		"QUERY" to LuaValue.valueOf(QUERY_INDEX),
		"PAGE" to LuaValue.valueOf(PAGE_INDEX),
		"KEY_CHAPTER_URL" to LuaValue.valueOf(Extension.KEY_CHAPTER_URL),
		"KEY_NOVEL_URL" to LuaValue.valueOf(Extension.KEY_NOVEL_URL),
	)

fun LuaTable.frozen(name: String, allowed: Array<String>? = null): LuaTable {
	var tbl = this
	if (allowed != null) {
		val new = LuaTable()
		allowed.forEach { new[it] = tbl[it] }
		tbl = new
	}

	val mt = LuaTable()
	val new = LuaTable()
	mt["__index"] = tbl
	mt["__newindex"] =
		object : ZeroArgFunction() {
			@Throws(LuaError::class)
			override fun call(): LuaValue = throw LuaError("$name is read-only.")
		}
	new.setmetatable(mt)

	return new
}

fun Globals.freezeLib(key: String, allowed: Array<String>? = null): Unit =
	this.set(key, (this.get(key) as LuaTable).frozen(key, allowed))

fun Globals.frozen(): Globals {
	val mt = LuaTable()
	val new = Globals()
	new["_G"] = new

	// why does LuaJ have all this shit
	new.STDIN = this.STDIN
	new.STDOUT = this.STDOUT
	new.STDERR = this.STDERR
	new.finder = this.finder
	new.running = this.running
	new.baselib = this.baselib
	new.package_ = this.package_
	new.debuglib = this.debuglib
	new.loader = this.loader
	new.undumper = this.undumper
	new.compiler = this.compiler

	mt["__index"] = this
	mt["__newindex"] =
		object : ZeroArgFunction() {
			// not sure if this is the best idea,
			// but it enforces better code quality/speed and
			// it should reduce risks.
			@Throws(LuaError::class)
			override fun call(): LuaValue = throw LuaError(
				"Cannot create a global. Please use a local variable/function.",
			)
		}
	new.setmetatable(mt)
	return new
}

fun shosetsuGlobals(): Globals {
	// Creation of globals
	return Globals()
		.apply {
			load(JseBaseLib())
			load(PackageLib())
			load(Bit32Lib())
			load(TableLib())
			load(StringLib())
			load(CoroutineLib())
			load(JseMathLib())
			load(JseOsLib())
			load(LuajavaLib())

			// Install compilers.
			LoadState.install(this)
			LuaC.install(this)

			// Load shosetsu environment
			load(ShosetsuLuaLib())
			SHOSETSU_GLOBALS.forEach { (s, luaValue) -> set(s, luaValue) }

			// Freezing & Sandboxing
			freezeLib("package")
			freezeLib("bit32")
			freezeLib("table")
			freezeLib("coroutine")
			freezeLib("math")
			freezeLib(
				"os",
				arrayOf(
					"clock",
					"date",
					"difftime",
					"setlocale",
					"time",
				),
			)
		}.frozen()
}

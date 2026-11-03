package app.shosetsu.lib.lua

import app.shosetsu.lib.ILibrary
import app.shosetsu.lib.exceptions.InvalidFilterIDException
import app.shosetsu.lib.exceptions.InvalidMetaDataException
import app.shosetsu.lib.exceptions.MissingOrInvalidKeysException
import app.shosetsu.lib.json.LibraryMetaData
import java.io.File
import java.nio.file.Path
import kotlin.io.path.name
import kotlin.io.path.readText
import kotlinx.serialization.json.Json
import org.luaj.vm2.LuaError

/*
 * This file is part of shosetsu-services.
 * shosetsu-services is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * shosetsu-services is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * You should have received a copy of the GNU General Public License
 * along with shosetsu-services.  If not, see https://www.gnu.org/licenses/.
 */

class LuaLibrary
@Throws(
	MissingOrInvalidKeysException::class,
	InvalidFilterIDException::class,
	LuaError::class,
)
constructor(
	@Suppress("MemberVisibilityCanBePrivate")
	val content: String,
	debugName: String = "unknown",
) : ILibrary {
	constructor(file: File) : this(file.readText(), file.name)
	constructor(file: Path) : this(file.readText(), file.name)

	override val libMetaData: LibraryMetaData by lazy {
		try {
			Json.decodeFromString(extractMetaDataSection(content))
		} catch (e: Exception) {
			throw InvalidMetaDataException(debugName, e)
		}
	}
}

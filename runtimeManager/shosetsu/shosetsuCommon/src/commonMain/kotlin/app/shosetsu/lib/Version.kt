package app.shosetsu.lib

import kotlinx.serialization.Serializable

/**
 * Version of the kotlin-lib shosetsu is currently using
 */
val KOTLIN_LIB_VERSION = Version(1, 0, 0)

/**
 * kotlin-lib
 * 10 / 10 / 2020
 *
 * Version data class
 * @param major Incremented with major non backwards compatible changes occur
 * @param minor Incremented with feature releases that don't destroy backwards compatibility
 * @param patch Incremented with bug fixes that don't destroy backwards compatibility
 */
@Serializable(with = VersionSerializer::class)
data class Version(val major: Int, val minor: Int, val patch: Int) : Comparable<Version> {

	constructor(array: Array<Int>) : this(array[0], array[1], array[2])

	constructor(
		string: String,
	) : this(string.split(".").map { it.toInt() }.toTypedArray())

	/**
	 * Checks if this is compatible with [other]
	 */
	@Suppress("MemberVisibilityCanBePrivate")
	@Deprecated("Use isDependencySatisfied instead")
	fun isCompatible(other: Version): Boolean =
		isDependencySatisfied(requestedVersion = this, providedDependencyVersion = other)

	/**
	 * Checks if this is compatible with [KOTLIN_LIB_VERSION]
	 */
	@Deprecated("Use isDependencySatisfied instead")
	@Suppress("unused")
	fun isCompatible(): Boolean =
		isDependencySatisfied(requestedVersion = this, providedDependencyVersion = KOTLIN_LIB_VERSION)

	override fun compareTo(other: Version): Int = compareValuesBy(this, other, {
		it.major
	}, { it.minor }, { it.patch })

	override fun toString(): String = "$major.$minor.$patch"

	companion object {
		fun isDependencySatisfied(
			requestedVersion: Version,
			providedDependencyVersion: Version = KOTLIN_LIB_VERSION,
		): Boolean = requestedVersion.major == providedDependencyVersion.major &&
			requestedVersion <= providedDependencyVersion
	}
}

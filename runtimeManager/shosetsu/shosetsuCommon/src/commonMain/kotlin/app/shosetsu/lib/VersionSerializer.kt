package app.shosetsu.lib

import app.shosetsu.lib.json.J_VERSION
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind.STRING
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * [KSerializer] for [Version], to convert it from and to string
 */
internal class VersionSerializer : KSerializer<Version> {
	override fun deserialize(decoder: Decoder): Version = Version(decoder.decodeString())

	override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor(J_VERSION, STRING)

	override fun serialize(encoder: Encoder, value: Version) {
		encoder.encodeString(value.toString())
	}
}

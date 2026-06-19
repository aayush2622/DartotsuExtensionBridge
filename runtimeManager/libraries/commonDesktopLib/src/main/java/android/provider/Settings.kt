package android.provider

import android.content.ContentResolver
import java.util.UUID

object Settings {

    object Global {

        const val DEVICE_NAME = "device_name"

        @JvmStatic
        fun getString(resolver: ContentResolver?, name: String?): String? {
            return when (name) {
                DEVICE_NAME -> "Dartotsu"
                "android_id" -> UUID.randomUUID().toString()
                else -> "unknown"
            }
        }
    }
}
package kuchihige.utils

/**
 * Logs the value along with caller location, thread name, and type.
 *
 * Returns the receiver unchanged for easy chaining.
 *
 * @param m (message) prepend log message with this text
 * @param t (tag) tag to be used for log message
 */
@Suppress("UNUSED")
fun <T> T.log(m: String = "", t: String = "Kuchihige"): T {
    val stack = Throwable().stackTrace
    // stack[0] is this line, so stack[1] is the T.log(...), stack[2] is the caller
    val caller = stack.getOrNull(2)

    val location = if (caller != null) {
        "${caller.fileName}:${caller.lineNumber}"
    } else {
        "unknown location"
    }

    val method = caller?.methodName ?: "unknown"
    val thread = Thread.currentThread().name
    val type = this?.let {
        it::class.qualifiedName ?: it::class.simpleName
    } ?: "null"

    val message = """$m
        𝕧:  $this
            → $location
          𝕞:  $method
          𝕥:  $thread
          𝕋:  $type
    """.trimIndent()

    android.util.Log.d(t, message)

    return this
}

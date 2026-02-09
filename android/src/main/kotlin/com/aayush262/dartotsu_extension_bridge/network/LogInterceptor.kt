import android.util.Log
import okhttp3.Interceptor
import okhttp3.Response
import java.util.concurrent.TimeUnit

class LogInterceptor : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val startTime = System.nanoTime()

        Log.d(
            "DartotsuExtensionBridge",
            "→ ${request.method} ${request.url}"
        )

        try {
            val response = chain.proceed(request)

            val tookMs = TimeUnit.NANOSECONDS.toMillis(
                System.nanoTime() - startTime
            )

            Log.d(
                "DartotsuExtensionBridge",
                "← ${response.code} ${request.url} (${tookMs}ms)"
            )

            val server = response.header("server")?.lowercase()
            val cloudflare =
                response.code in listOf(403, 503) &&
                        server in listOf("cloudflare", "cloudflare-nginx")

            if (cloudflare) {
                Log.w("DartotsuExtensionBridge", "⚠️ Detected Cloudflare protection")
            }

            return response

        } catch (e: Exception) {
            val tookMs = TimeUnit.NANOSECONDS.toMillis(
                System.nanoTime() - startTime
            )

            Log.e(
                "DartotsuExtensionBridge",
                "× ${request.method} ${request.url} (${tookMs}ms)\n$e"
            )

            throw e
        }
    }
}

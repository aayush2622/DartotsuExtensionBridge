package com.aayush262.dartotsu_extension_bridge

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Looper
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class ExtensionSettingsActivity : AppCompatActivity() {

    companion object {
        private const val EXTRA_REQUEST = "request"
        private const val IDLE_TIMEOUT_MS = 1500L

        private val requests = ConcurrentHashMap<String, Pair<ExtensionApi, String>>()

        @Volatile
        private var current: ExtensionSettingsActivity? = null

        private var guarding = false

        fun open(context: Context, api: ExtensionApi, sourceId: String) {
            val id = UUID.randomUUID().toString()
            requests[id] = api to sourceId
            context.startActivity(
                Intent(context, ExtensionSettingsActivity::class.java)
                    .putExtra(EXTRA_REQUEST, id)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            )
        }

        private fun guardMainLooper() {
            if (guarding) return
            guarding = true
            android.os.Handler(Looper.getMainLooper()).postAtFrontOfQueue {
                while (true) {
                    try {
                        Looper.loop()
                    } catch (e: Throwable) {
                        val host = current
                        if (host == null) {
                            guarding = false
                            throw e
                        }
                        host.closeAfterCrash(e)
                    }
                }
            }
        }
    }

    private var lostFocus = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val request = intent.getStringExtra(EXTRA_REQUEST)?.let(requests::remove)
        if (savedInstanceState != null || request == null) {
            finish()
            return
        }

        current = this
        guardMainLooper()

        supportFragmentManager.registerFragmentLifecycleCallbacks(
            object : FragmentManager.FragmentLifecycleCallbacks() {
                override fun onFragmentDestroyed(fm: FragmentManager, f: Fragment) {
                    window.decorView.post { finishIfIdle() }
                }
            },
            true,
        )

        val (api, sourceId) = request
        val opened = try {
            api.openSettings(sourceId, this)
        } catch (e: Throwable) {
            closeAfterCrash(e)
            return
        }
        if (!opened) {
            finish()
            return
        }
        window.decorView.postDelayed({ if (!lostFocus) finishIfIdle() }, IDLE_TIMEOUT_MS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) lostFocus = true else if (lostFocus) finishIfIdle()
    }

    private fun finishIfIdle() {
        if (isFinishing || isDestroyed) return
        if (supportFragmentManager.fragments.any { it.isAdded }) return
        if (!hasWindowFocus()) return
        finish()
    }

    private fun closeAfterCrash(error: Throwable) {
        Logger.log("Extension settings failed: ${error.stackTraceToString()}", LogLevel.ERROR)
        Toast.makeText(applicationContext, "This extension's settings could not be opened", Toast.LENGTH_SHORT).show()
        if (!isFinishing) finish()
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }
}

package kuchihige.utils

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

val mainHandler by lazy { Handler(Looper.getMainLooper()) }

fun launchIO(block: suspend () -> Unit): Job = CoroutineScope(Dispatchers.IO).launch {
    block()
}

fun runOnMain(block: () -> Unit) {
    mainHandler.post(block)
}

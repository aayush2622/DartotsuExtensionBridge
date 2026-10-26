package com.aayush262.dartotsu_extension_bridge.common

/** A backend that loads its extensions in the background reports how many are still being prepared. */
interface ExtensionLoadStatus {
    fun pendingExtensions(): Int
}

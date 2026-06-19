package xyz.nulldev.androidcompat.io

import java.io.File

/**
 * Android file constants (Dartotsu version - no config dependency)
 */
class AndroidFiles(
    private val root: File
) {

    private fun dir(name: String): File =
        File(root, name).apply { mkdirs() }

    val dataDir: File get() = dir("data")

    val filesDir: File get() = dir("files")

    val noBackupFilesDir: File get() = dir("no-backup")

    val externalFilesDirs: List<File>
        get() = listOf(filesDir)

    val obbDirs: List<File>
        get() = listOf(dir("obb"))

    val cacheDir: File get() = dir("cache")

    val codeCacheDir: File get() = dir("code-cache")

    val externalCacheDirs: List<File>
        get() = listOf(cacheDir)

    val externalMediaDirs: List<File>
        get() = listOf(dir("media"))

    val rootDir: File get() = root.apply { mkdirs() }

    val externalStorageDir: File get() = root

    val downloadCacheDir: File get() = dir("download")

    val databasesDir: File get() = dir("databases")

    val prefsDir: File get() = dir("prefs")

    val packagesDir: File get() = dir("packages")
}
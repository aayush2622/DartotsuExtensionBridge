package eu.kanade.tachiyomi.source

interface RateLimited {
    val minimumDelayMillis: Long

    val recommendedDelayMillis: Long

    val recommendedPermits: Int
}

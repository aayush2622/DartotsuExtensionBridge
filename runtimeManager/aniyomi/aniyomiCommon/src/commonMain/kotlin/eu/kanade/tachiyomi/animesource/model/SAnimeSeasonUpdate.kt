package eu.kanade.tachiyomi.animesource.model

/**
 * Combined result of [eu.kanade.tachiyomi.animesource.AnimeSource.getAnimeSeasonUpdate].
 *
 * @since extensions-lib 17
 */
class SAnimeSeasonUpdate(val anime: SAnime, val seasons: List<SAnime>)

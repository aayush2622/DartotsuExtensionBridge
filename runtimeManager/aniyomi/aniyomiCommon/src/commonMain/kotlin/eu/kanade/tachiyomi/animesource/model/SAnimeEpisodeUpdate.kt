package eu.kanade.tachiyomi.animesource.model

/**
 * Combined result of [eu.kanade.tachiyomi.animesource.AnimeSource.getAnimeEpisodeUpdate].
 *
 * @since extensions-lib 17
 */
class SAnimeEpisodeUpdate(val anime: SAnime, val episodes: List<SEpisode>)

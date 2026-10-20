package com.maxrave.simpmusic.utils

sealed interface SharedTextContent {
    data class SongSearch(
        val query: String,
    ) : SharedTextContent

    data class Link(
        val url: String,
    ) : SharedTextContent
}

/** Converts text shared by other apps into something SimpMusic can handle. */
object SharedTextParser {
    /** Metadata from Android's MEDIA_PLAY_FROM_SEARCH, as sent by Now Playing. */
    fun parseMediaSearch(
        title: String?,
        artist: String?,
        query: String?,
    ): SharedTextContent.SongSearch? {
        val songTitle = title?.trim().orEmpty()
        val songArtist = artist?.trim().orEmpty()
        val searchQuery =
            if (songTitle.isNotEmpty()) {
                listOf(songTitle, songArtist).filter { it.isNotEmpty() }.joinToString(" ")
            } else {
                query?.trim().orEmpty()
            }
        return searchQuery.takeIf { it.isNotEmpty() }?.let(SharedTextContent::SongSearch)
    }

    private val ambientMusicSong =
        Regex(
            pattern = """^\s*[\"“„]([^\"”]+)[\"”]\s+(?:di|by)\s+(.+?)(?=\s+https?://|\r?\n|$)""",
            option = RegexOption.IGNORE_CASE,
        )
    private val webLink = Regex("""https?://\S+""", RegexOption.IGNORE_CASE)
    private val googleSearchLink = Regex("""https?://(?:www\.)?google\.com/search(?:[?#]|$)""", RegexOption.IGNORE_CASE)
    private val unquotedSong =
        Regex(
            """^\s*(.+?)\s+(?:di|by)\s+(.+?)(?=\s+https?://|\r?\n|$)""",
            RegexOption.IGNORE_CASE,
        )

    fun parse(text: String?): SharedTextContent? {
        val sharedText = text?.trim().orEmpty()
        if (sharedText.isEmpty()) return null

        ambientMusicSong.find(sharedText)?.let { match ->
            val title = match.groupValues[1].trim()
            val artist = match.groupValues[2].trim().trimEnd('.', ',', ';')
            if (title.isNotEmpty() && artist.isNotEmpty()) {
                return SharedTextContent.SongSearch("$title $artist")
            }
        }

        // Now Playing 1.3.5 shares unquoted titles followed by a Google search URL.
        // Require that URL so unrelated prose containing "di" or "by" stays untouched.
        if (googleSearchLink.containsMatchIn(sharedText)) {
            unquotedSong.find(sharedText)?.let { match ->
                return parseMediaSearch(match.groupValues[1], match.groupValues[2], null)
            }
        }

        return webLink
            .find(sharedText)
            ?.value
            ?.trimEnd('.', ',', ';', ')')
            ?.let(SharedTextContent::Link)
    }
}
package com.maxrave.simpmusic.utils

sealed interface SharedTextContent {
    data class SongSearch(val query: String) : SharedTextContent

    data class Link(val url: String) : SharedTextContent
}

/** Converts text shared by other apps into something SimpMusic can handle. */
object SharedTextParser {
    private val ambientMusicSong =
        Regex(
            pattern = """^\s*[\"“„]([^\"”]+)[\"”]\s+(?:di|by)\s+(.+?)(?=\s+https?://|\r?\n|$)""",
            option = RegexOption.IGNORE_CASE,
        )
    private val webLink = Regex("""https?://\S+""", RegexOption.IGNORE_CASE)

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

        return webLink.find(sharedText)?.value?.trimEnd('.', ',', ';', ')')?.let(SharedTextContent::Link)
    }
}

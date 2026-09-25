package com.maxrave.simpmusic.utils

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class SharedTextParserTest {
    @Test
    fun parsesAmbientMusicItalianShare() {
        val content =
            SharedTextParser.parse(
                "\"Heroes\" di David Bowie\nhttps://www.google.com/search?q=Heroes+David+Bowie",
            )

        assertEquals(SharedTextContent.SongSearch("Heroes David Bowie"), content)
    }

    @Test
    fun parsesSmartQuotesAndEnglishShare() {
        val content = SharedTextParser.parse("“Heroes” by David Bowie\nhttps://www.google.com/search?q=Heroes")

        assertEquals(SharedTextContent.SongSearch("Heroes David Bowie"), content)
    }

    @Test
    fun excludesGoogleLinkWhenShareUsesSpacesInsteadOfNewline() {
        val content =
            SharedTextParser.parse(
                "\"Heroes\" di David Bowie https://www.google.com/search?q=Heroes+David+Bowie",
            )

        assertEquals(SharedTextContent.SongSearch("Heroes David Bowie"), content)
    }

    @Test
    fun extractsYouTubeLinkFromSharedDescription() {
        val content = SharedTextParser.parse("Listen to this: https://youtu.be/dQw4w9WgXcQ")

        assertEquals(SharedTextContent.Link("https://youtu.be/dQw4w9WgXcQ"), content)
    }

    @Test
    fun ignoresPlainTextThatIsNotASongShare() {
        assertNull(SharedTextParser.parse("Some unrelated shared text"))
    }
}

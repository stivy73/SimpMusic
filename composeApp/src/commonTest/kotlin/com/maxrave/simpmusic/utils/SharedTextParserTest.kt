package com.maxrave.simpmusic.utils

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class SharedTextParserTest {
    @Test
    fun parsesActualNowPlayingUnquotedShare() {
        assertEquals(
            SharedTextContent.SongSearch("Old and Wise The Alan Parsons Project"),
            SharedTextParser.parse(
                "Old and Wise di The Alan Parsons Project\nhttps://www.google.com/search?q=Old+and+Wise+di+The+Alan+Parsons+Project",
            ),
        )
    }

    @Test
    fun parsesEnglishUnquotedShareOnOneLine() {
        assertEquals(
            SharedTextContent.SongSearch("Old and Wise The Alan Parsons Project"),
            SharedTextParser.parse("Old and Wise by The Alan Parsons Project https://www.google.com/search?q=Old+and+Wise"),
        )
    }

    @Test
    fun doesNotTreatUnquotedProseAsSongMetadata() {
        assertEquals(
            SharedTextContent.Link("https://example.com/story"),
            SharedTextParser.parse("A story by Someone\nhttps://example.com/story"),
        )
    }

    @Test
    fun parsesNowPlayingMetadataInsteadOfLocalizedQuery() {
        assertEquals(
            SharedTextContent.SongSearch("Heroes David Bowie"),
            SharedTextParser.parseMediaSearch(" Heroes ", " David Bowie ", "Play Heroes by David Bowie"),
        )
    }

    @Test
    fun fallsBackToSearchQueryWithoutTitle() {
        assertEquals(
            SharedTextContent.SongSearch("Heroes David Bowie"),
            SharedTextParser.parseMediaSearch(null, "David Bowie", " Heroes David Bowie "),
        )
    }

    @Test
    fun acceptsTitleWithoutArtist() {
        assertEquals(SharedTextContent.SongSearch("Heroes"), SharedTextParser.parseMediaSearch("Heroes", null, null))
    }

    @Test
    fun ignoresEmptySearchInsteadOfResumingPreviousSong() {
        assertNull(SharedTextParser.parseMediaSearch(" ", "David Bowie", " "))
    }

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
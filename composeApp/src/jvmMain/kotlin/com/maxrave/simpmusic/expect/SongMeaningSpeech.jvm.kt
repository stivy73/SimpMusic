package com.maxrave.simpmusic.expect

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

private class UnsupportedSongMeaningSpeechController : SongMeaningSpeechController {
    override val state: StateFlow<SongMeaningSpeechState> = MutableStateFlow(SongMeaningSpeechState.Idle)
    override val isAvailable: Boolean = false

    override fun play(text: String) = Unit

    override fun stop() = Unit

    override fun release() = Unit
}

@Composable
actual fun rememberSongMeaningSpeechController(): SongMeaningSpeechController =
    remember { UnsupportedSongMeaningSpeechController() }

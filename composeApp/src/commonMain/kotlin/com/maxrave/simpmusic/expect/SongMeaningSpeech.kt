package com.maxrave.simpmusic.expect

import androidx.compose.runtime.Composable
import kotlinx.coroutines.flow.StateFlow

enum class SongMeaningSpeechError {
    OPENAI_PROVIDER_REQUIRED,
    API_KEY_MISSING,
    GOOGLE_API_KEY_MISSING,
    LANGUAGE_UNAVAILABLE,
    SERVICE_ERROR,
}

sealed interface SongMeaningSpeechState {
    data object Idle : SongMeaningSpeechState

    data object Preparing : SongMeaningSpeechState

    data object Playing : SongMeaningSpeechState

    data class Error(
        val reason: SongMeaningSpeechError,
    ) : SongMeaningSpeechState
}

interface SongMeaningSpeechController {
    val state: StateFlow<SongMeaningSpeechState>
    val isAvailable: Boolean

    fun play(text: String)

    fun stop()

    fun release()
}

@Composable
expect fun rememberSongMeaningSpeechController(): SongMeaningSpeechController

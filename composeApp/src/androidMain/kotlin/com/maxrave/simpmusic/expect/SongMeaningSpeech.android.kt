package com.maxrave.simpmusic.expect

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.maxrave.domain.manager.DataStoreManager
import com.maxrave.domain.mediaservice.handler.MediaPlayerHandler
import com.maxrave.domain.mediaservice.handler.PlayerEvent
import com.maxrave.media3.speech.CloudSongMeaningSpeech
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import org.koin.compose.koinInject

private class AndroidSongMeaningSpeechController(
    private val context: Context,
    private val dataStoreManager: DataStoreManager,
    private val mediaPlayerHandler: MediaPlayerHandler,
) : SongMeaningSpeechController {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutableState = MutableStateFlow<SongMeaningSpeechState>(SongMeaningSpeechState.Idle)
    override val state: StateFlow<SongMeaningSpeechState> = mutableState
    override val isAvailable: Boolean = true

    private var textToSpeech: TextToSpeech? = null
    private var nativeReady = false
    private var nativeLanguageAvailable = true
    private var pendingNativeText: String? = null
    private var finalUtteranceId: String? = null
    private val openAiSpeech = CloudSongMeaningSpeech(context, scope)
    private var speechJob: Job? = null
    private var resumeMusicAfterSpeech = false

    init {
        textToSpeech =
            TextToSpeech(context) { status ->
                nativeReady = status == TextToSpeech.SUCCESS
                if (!nativeReady) {
                    if (pendingNativeText != null) {
                        pendingNativeText = null
                        mutableState.value = SongMeaningSpeechState.Error(SongMeaningSpeechError.SERVICE_ERROR)
                    }
                } else {
                    configureNativeVoice()
                    pendingNativeText?.let {
                        pendingNativeText = null
                        startNativeSpeech(it)
                    }
                }
            }
        textToSpeech?.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    mutableState.value = SongMeaningSpeechState.Playing
                }

                override fun onDone(utteranceId: String?) {
                    if (utteranceId == finalUtteranceId) finishSpeech()
                }

                @Deprecated("Deprecated in Android")
                override fun onError(utteranceId: String?) {
                    failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
                }

                override fun onError(
                    utteranceId: String?,
                    errorCode: Int,
                ) {
                    failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
                }
            },
        )
    }

    override fun play(text: String) {
        if (text.isBlank()) return
        stop(resumeMusic = false)
        mutableState.value = SongMeaningSpeechState.Preparing
        speechJob = scope.launch {
            when (dataStoreManager.songMeaningTtsProvider.first()) {
                DataStoreManager.SONG_MEANING_TTS_OPENAI -> playOpenAi(text)
                DataStoreManager.SONG_MEANING_TTS_GOOGLE -> playGoogle(text)
                else -> playNative(text)
            }
        }
    }

    override fun stop() {
        stop(resumeMusic = true)
    }

    private fun stop(resumeMusic: Boolean) {
        speechJob?.cancel()
        speechJob = null
        pendingNativeText = null
        finalUtteranceId = null
        textToSpeech?.stop()
        openAiSpeech.stop()
        mutableState.value = SongMeaningSpeechState.Idle
        if (resumeMusic) resumeMusicIfNeeded()
    }

    private fun configureNativeVoice() {
        val result = textToSpeech?.setLanguage(Locale.ITALIAN)
        nativeLanguageAvailable =
            result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED
    }

    private fun playNative(text: String) {
        if (!nativeReady) {
            pendingNativeText = text
            return
        }
        startNativeSpeech(text)
    }

    private fun startNativeSpeech(text: String) {
        if (!nativeLanguageAvailable) {
            failSpeech(SongMeaningSpeechError.LANGUAGE_UNAVAILABLE)
            return
        }
        pauseMusicIfNeeded()
        val maxLength = TextToSpeech.getMaxSpeechInputLength().coerceAtLeast(1)
        val chunks = text.chunked(maxLength)
        val utterancePrefix = "song-meaning-${System.currentTimeMillis()}"
        finalUtteranceId = "$utterancePrefix-${chunks.lastIndex}"
        chunks.forEachIndexed { index, chunk ->
            val utteranceId = "$utterancePrefix-$index"
            if (index == chunks.lastIndex) finalUtteranceId = utteranceId
            val result =
                textToSpeech?.speak(
                    chunk,
                    if (index == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,
                    Bundle(),
                    utteranceId,
                )
            if (result == TextToSpeech.ERROR) {
                failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
                return
            }
        }
    }

    private suspend fun playOpenAi(text: String) {
        if (dataStoreManager.aiProvider.first() != DataStoreManager.AI_PROVIDER_OPENAI) {
            failSpeech(SongMeaningSpeechError.OPENAI_PROVIDER_REQUIRED)
            return
        }
        val apiKey = dataStoreManager.aiApiKey.first()
        if (apiKey.isBlank()) {
            failSpeech(SongMeaningSpeechError.GOOGLE_API_KEY_MISSING)
            return
        }
        try {
            openAiSpeech.speak(
                text = text,
                apiKey = apiKey,
                beforePlayback = {
                    withContext(Dispatchers.Main.immediate) {
                        if (!resumeMusicAfterSpeech && mediaPlayerHandler.controlState.value.isPlaying) {
                            resumeMusicAfterSpeech = true
                            mediaPlayerHandler.onPlayerEvent(PlayerEvent.PlayPause)
                        }
                    }
                },
                onStage = { stage ->
                    if (stage == "first_pcm_submitted") mutableState.value = SongMeaningSpeechState.Playing
                },
            )
            finishSpeech()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (currentCoroutineContext().isActive) failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
        }
    }

    private suspend fun playGoogle(text: String) {
        val apiKey = dataStoreManager.googleTtsApiKey.first().ifBlank {
            if (dataStoreManager.aiProvider.first() == DataStoreManager.AI_PROVIDER_GEMINI) dataStoreManager.aiApiKey.first() else ""
        }
        if (apiKey.isBlank()) {
            failSpeech(SongMeaningSpeechError.API_KEY_MISSING)
            return
        }
        try {
            openAiSpeech.speakGemini(
                text = text,
                apiKey = apiKey,
                style = dataStoreManager.songMeaningVoiceStyle.first(),
                beforePlayback = {
                    withContext(Dispatchers.Main.immediate) {
                        if (!resumeMusicAfterSpeech && mediaPlayerHandler.controlState.value.isPlaying) {
                            resumeMusicAfterSpeech = true
                            mediaPlayerHandler.onPlayerEvent(PlayerEvent.PlayPause)
                        }
                    }
                },
                onStage = { stage ->
                    if (stage == "first_pcm_submitted") mutableState.value = SongMeaningSpeechState.Playing
                },
            )
            finishSpeech()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (currentCoroutineContext().isActive) failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
        }
    }

    private fun pauseMusicIfNeeded() {
        if (!resumeMusicAfterSpeech && mediaPlayerHandler.controlState.value.isPlaying) {
            resumeMusicAfterSpeech = true
            scope.launch { mediaPlayerHandler.onPlayerEvent(PlayerEvent.PlayPause) }
        }
    }

    private fun resumeMusicIfNeeded() {
        if (resumeMusicAfterSpeech) {
            resumeMusicAfterSpeech = false
            scope.launch { mediaPlayerHandler.onPlayerEvent(PlayerEvent.PlayPause) }
        }
    }

    private fun finishSpeech() {
        openAiSpeech.stop()
        mutableState.value = SongMeaningSpeechState.Idle
        resumeMusicIfNeeded()
    }

    private fun failSpeech(reason: SongMeaningSpeechError) {
        openAiSpeech.stop()
        mutableState.value = SongMeaningSpeechState.Error(reason)
        resumeMusicIfNeeded()
    }

    override fun release() {
        stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        scope.cancel()
    }

}

@Composable
actual fun rememberSongMeaningSpeechController(): SongMeaningSpeechController {
    val context = LocalContext.current.applicationContext
    val dataStoreManager = koinInject<DataStoreManager>()
    val mediaPlayerHandler = koinInject<MediaPlayerHandler>()
    val controller = remember(context, dataStoreManager, mediaPlayerHandler) {
        AndroidSongMeaningSpeechController(context, dataStoreManager, mediaPlayerHandler)
    }
    DisposableEffect(controller) {
        onDispose(controller::release)
    }
    return controller
}

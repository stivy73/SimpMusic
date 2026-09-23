package com.maxrave.simpmusic.expect

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
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
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
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
    private var speechPlayer: MediaPlayer? = null
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
        scope.launch {
            when (dataStoreManager.songMeaningTtsProvider.first()) {
                DataStoreManager.SONG_MEANING_TTS_OPENAI -> playOpenAi(text)
                else -> playNative(text)
            }
        }
    }

    override fun stop() {
        stop(resumeMusic = true)
    }

    private fun stop(resumeMusic: Boolean) {
        pendingNativeText = null
        finalUtteranceId = null
        textToSpeech?.stop()
        speechPlayer?.release()
        speechPlayer = null
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
            failSpeech(SongMeaningSpeechError.API_KEY_MISSING)
            return
        }
        val audioFile =
            runCatching { loadOpenAiSpeech(text, apiKey) }
                .getOrElse {
                    failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
                    return
                }
        playAudioFile(audioFile)
    }

    private suspend fun loadOpenAiSpeech(
        text: String,
        apiKey: String,
    ): File =
        withContext(Dispatchers.IO) {
            val cacheDirectory = File(context.cacheDir, "song_meaning_speech").apply { mkdirs() }
            val digest =
                MessageDigest
                    .getInstance("SHA-256")
                    .digest((OPENAI_VOICE + text).encodeToByteArray())
                    .joinToString("") { "%02x".format(it.toInt() and 0xff) }
            val target = File(cacheDirectory, "$digest.mp3")
            if (target.length() > 0L) return@withContext target

            val connection = (URL(OPENAI_SPEECH_URL).openConnection() as HttpURLConnection)
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = 15_000
                connection.readTimeout = 60_000
                connection.doOutput = true
                connection.setRequestProperty("Authorization", "Bearer $apiKey")
                connection.setRequestProperty("Content-Type", "application/json")
                val body =
                    buildJsonObject {
                        put("model", OPENAI_TTS_MODEL)
                        put("voice", OPENAI_VOICE)
                        put("input", text)
                        put("instructions", "Leggi in italiano con tono naturale, caldo e informativo.")
                        put("response_format", "mp3")
                    }.toString()
                connection.outputStream.use { it.write(body.encodeToByteArray()) }
                if (connection.responseCode !in 200..299) {
                    throw IllegalStateException("OpenAI speech request failed (${connection.responseCode})")
                }
                val partial = File(cacheDirectory, "$digest.tmp")
                connection.inputStream.use { input -> partial.outputStream().use(input::copyTo) }
                check(partial.renameTo(target)) { "Unable to cache generated speech" }
                target
            } finally {
                connection.disconnect()
            }
        }

    private fun playAudioFile(file: File) {
        val player =
            MediaPlayer()
                .apply {
                    setAudioAttributes(
                        AudioAttributes
                            .Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    setDataSource(context, Uri.fromFile(file))
                    setOnPreparedListener { preparedPlayer ->
                        pauseMusicIfNeeded()
                        preparedPlayer.start()
                        mutableState.value = SongMeaningSpeechState.Playing
                    }
                    setOnCompletionListener { finishSpeech() }
                    setOnErrorListener { _, _, _ ->
                        failSpeech(SongMeaningSpeechError.SERVICE_ERROR)
                        true
                    }
                    prepareAsync()
                }
        speechPlayer = player
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
        speechPlayer?.release()
        speechPlayer = null
        mutableState.value = SongMeaningSpeechState.Idle
        resumeMusicIfNeeded()
    }

    private fun failSpeech(reason: SongMeaningSpeechError) {
        speechPlayer?.release()
        speechPlayer = null
        mutableState.value = SongMeaningSpeechState.Error(reason)
        resumeMusicIfNeeded()
    }

    override fun release() {
        stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        scope.cancel()
    }

    private companion object {
        private const val OPENAI_SPEECH_URL = "https://api.openai.com/v1/audio/speech"
        private const val OPENAI_TTS_MODEL = "gpt-4o-mini-tts"
        private const val OPENAI_VOICE = "marin"
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

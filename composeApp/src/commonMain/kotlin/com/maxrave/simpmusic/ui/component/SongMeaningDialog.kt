package com.maxrave.simpmusic.ui.component

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.maxrave.domain.utils.LocalResource
import com.maxrave.simpmusic.expect.copyToClipboard
import com.maxrave.simpmusic.expect.rememberSongMeaningSpeechController
import com.maxrave.simpmusic.expect.shareUrl
import com.maxrave.simpmusic.expect.SongMeaningSpeechError
import com.maxrave.simpmusic.expect.SongMeaningSpeechState
import com.maxrave.simpmusic.ui.icon.Pause
import com.maxrave.simpmusic.ui.icon.PlayArrow
import com.maxrave.simpmusic.ui.icon.Share
import com.maxrave.simpmusic.ui.icon.SimpIcons
import com.maxrave.simpmusic.ui.theme.typo
import org.jetbrains.compose.resources.stringResource
import simpmusic.composeapp.generated.resources.Res
import simpmusic.composeapp.generated.resources.cancel
import simpmusic.composeapp.generated.resources.copy
import simpmusic.composeapp.generated.resources.retry
import simpmusic.composeapp.generated.resources.read_aloud
import simpmusic.composeapp.generated.resources.share
import simpmusic.composeapp.generated.resources.song_meaning
import simpmusic.composeapp.generated.resources.song_meaning_loading
import simpmusic.composeapp.generated.resources.song_meaning_no_lyrics
import simpmusic.composeapp.generated.resources.song_meaning_speech_error
import simpmusic.composeapp.generated.resources.song_meaning_speech_key_missing
import simpmusic.composeapp.generated.resources.song_meaning_speech_language_unavailable
import simpmusic.composeapp.generated.resources.song_meaning_speech_openai_required
import simpmusic.composeapp.generated.resources.stop_reading

@Composable
fun SongMeaningDialog(
    title: String,
    artist: String,
    hasLyrics: Boolean,
    state: LocalResource<String>,
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    val songMeaningLabel = stringResource(Res.string.song_meaning)
    val shareLabel = stringResource(Res.string.share)
    val speechController = rememberSongMeaningSpeechController()
    val speechState by speechController.state.collectAsState()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Column {
                Text(songMeaningLabel, style = typo().titleMedium)
                Text("$title • $artist", style = typo().bodySmall)
            }
        },
        text = {
            when (state) {
                is LocalResource.Loading -> CircularProgressIndicator(modifier = Modifier.padding(16.dp))
                is LocalResource.Error -> Text(state.message.orEmpty(), style = typo().bodyMedium)
                is LocalResource.Success ->
                    Column {
                        if (!hasLyrics) {
                            Text(
                                stringResource(Res.string.song_meaning_no_lyrics),
                                style = typo().bodySmall,
                                modifier = Modifier.padding(bottom = 12.dp),
                            )
                        }
                        if (state.data.isNullOrBlank()) {
                            Text(stringResource(Res.string.song_meaning_loading), style = typo().bodyMedium)
                        } else {
                            SelectionContainer {
                                Text(
                                    state.data.orEmpty(),
                                    style = typo().bodyMedium,
                                    modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp).verticalScroll(rememberScrollState()),
                                )
                            }
                            (speechState as? SongMeaningSpeechState.Error)?.let { error ->
                                Text(
                                    text =
                                        stringResource(
                                            when (error.reason) {
                                                SongMeaningSpeechError.OPENAI_PROVIDER_REQUIRED ->
                                                    Res.string.song_meaning_speech_openai_required
                                                SongMeaningSpeechError.API_KEY_MISSING ->
                                                    Res.string.song_meaning_speech_key_missing
                                                SongMeaningSpeechError.LANGUAGE_UNAVAILABLE ->
                                                    Res.string.song_meaning_speech_language_unavailable
                                                SongMeaningSpeechError.SERVICE_ERROR ->
                                                    Res.string.song_meaning_speech_error
                                            },
                                        ),
                                    style = typo().bodySmall,
                                    modifier = Modifier.padding(top = 12.dp),
                                )
                            }
                        }
                    }
            }
        },
        confirmButton = {
            when (state) {
                is LocalResource.Success ->
                    if (!state.data.isNullOrBlank()) {
                        Row {
                            if (speechController.isAvailable) {
                                val speechActive =
                                    speechState is SongMeaningSpeechState.Preparing ||
                                        speechState is SongMeaningSpeechState.Playing
                                IconButton(
                                    onClick = {
                                        if (speechActive) {
                                            speechController.stop()
                                        } else {
                                            speechController.play(state.data.orEmpty())
                                        }
                                    },
                                ) {
                                    if (speechState is SongMeaningSpeechState.Preparing) {
                                        CircularProgressIndicator(modifier = Modifier.padding(12.dp))
                                    } else {
                                        Icon(
                                            imageVector =
                                                if (speechState is SongMeaningSpeechState.Playing) {
                                                    SimpIcons.Pause
                                                } else {
                                                    SimpIcons.PlayArrow
                                                },
                                            contentDescription =
                                                stringResource(
                                                    if (speechActive) Res.string.stop_reading else Res.string.read_aloud,
                                                ),
                                        )
                                    }
                                }
                            }
                            IconButton(
                                onClick = {
                                    shareUrl(
                                        title = songMeaningLabel,
                                        url = "$title — $artist\n\n${state.data.orEmpty()}",
                                    )
                                },
                            ) {
                                Icon(
                                    imageVector = SimpIcons.Share,
                                    contentDescription = shareLabel,
                                )
                            }
                            TextButton(onClick = { copyToClipboard("Song meaning", state.data.orEmpty()) }) {
                                Text(stringResource(Res.string.copy))
                            }
                        }
                    }

                is LocalResource.Error -> {
                    TextButton(onClick = onRetry) { Text(stringResource(Res.string.retry)) }
                }

                is LocalResource.Loading -> Unit
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(Res.string.cancel)) }
        },
    )
}

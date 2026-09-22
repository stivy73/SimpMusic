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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.maxrave.domain.utils.LocalResource
import com.maxrave.simpmusic.expect.copyToClipboard
import com.maxrave.simpmusic.expect.shareUrl
import com.maxrave.simpmusic.ui.icon.Share
import com.maxrave.simpmusic.ui.icon.SimpIcons
import com.maxrave.simpmusic.ui.theme.typo
import org.jetbrains.compose.resources.stringResource
import simpmusic.composeapp.generated.resources.Res
import simpmusic.composeapp.generated.resources.cancel
import simpmusic.composeapp.generated.resources.copy
import simpmusic.composeapp.generated.resources.retry
import simpmusic.composeapp.generated.resources.share
import simpmusic.composeapp.generated.resources.song_meaning
import simpmusic.composeapp.generated.resources.song_meaning_loading
import simpmusic.composeapp.generated.resources.song_meaning_no_lyrics

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
                        }
                    }
            }
        },
        confirmButton = {
            when (state) {
                is LocalResource.Success ->
                    if (!state.data.isNullOrBlank()) {
                        Row {
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

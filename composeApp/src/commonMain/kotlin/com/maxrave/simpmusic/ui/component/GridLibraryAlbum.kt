package com.maxrave.simpmusic.ui.component

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.maxrave.domain.data.model.searchResult.albums.AlbumsResult
import com.maxrave.domain.utils.LocalResource
import com.maxrave.simpmusic.extension.isScrollingUp
import com.maxrave.simpmusic.ui.navigation.destination.list.AlbumDestination
import org.jetbrains.compose.resources.stringResource
import simpmusic.composeapp.generated.resources.Res
import simpmusic.composeapp.generated.resources.no_youtube_music_albums
import simpmusic.composeapp.generated.resources.retry_youtube_music_albums
import simpmusic.composeapp.generated.resources.unable_to_load_youtube_music_albums

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun GridLibraryAlbum(
    navController: NavController,
    contentPadding: PaddingValues,
    data: LocalResource<List<AlbumsResult>>,
    onScrolling: (Boolean) -> Unit,
    onReload: () -> Unit,
) {
    val state = rememberLazyGridState()
    val isScrollingUp by state.isScrollingUp()
    LaunchedEffect(state) {
        snapshotFlow { state.firstVisibleItemIndex }.collect {
            onScrolling(it <= 1 || isScrollingUp)
        }
    }
    val refreshState = rememberPullToRefreshState()
    PullToRefreshBox(
        modifier = Modifier.fillMaxSize(),
        state = refreshState,
        isRefreshing = data is LocalResource.Loading,
        onRefresh = onReload,
        indicator = {
            PullToRefreshDefaults.Indicator(
                state = refreshState,
                isRefreshing = data is LocalResource.Loading,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = contentPadding.calculateTopPadding()),
            )
        },
    ) {
        // Keep a scrollable surface even when empty or failed, so pull-to-refresh still works.
        LazyVerticalGrid(
            modifier = Modifier.fillMaxSize(),
            columns = LibraryGridCells,
            contentPadding = contentPadding,
            state = state,
        ) {
            when (data) {
                is LocalResource.Success -> {
                    val albums = data.data.orEmpty()
                    if (albums.isEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Text(stringResource(Res.string.no_youtube_music_albums), modifier = Modifier.padding(20.dp))
                        }
                    }
                    items(albums, key = { it.browseId }) { album ->
                        HomeItemContentPlaylist(
                            data = album,
                            fillMaxWidth = true,
                            onClick = { navController.navigate(AlbumDestination(browseId = album.browseId)) },
                        )
                    }
                }
                is LocalResource.Error -> {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Text(stringResource(Res.string.unable_to_load_youtube_music_albums), modifier = Modifier.padding(20.dp))
                    }
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        TextButton(onClick = onReload) { Text(stringResource(Res.string.retry_youtube_music_albums)) }
                    }
                }
                is LocalResource.Loading -> {
                    Unit
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) { EndOfPage() }
        }
    }
}
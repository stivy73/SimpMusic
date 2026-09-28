package com.maxrave.simpmusic.ui.component

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.toRoute
import com.maxrave.simpmusic.ui.icon.Album
import com.maxrave.simpmusic.ui.icon.DownloadForOffline
import com.maxrave.simpmusic.ui.icon.Favorite
import com.maxrave.simpmusic.ui.icon.Home
import com.maxrave.simpmusic.ui.icon.SimpIcons
import com.maxrave.simpmusic.ui.navigation.destination.home.HomeDestination
import com.maxrave.simpmusic.ui.navigation.destination.library.LibraryDestination
import com.maxrave.simpmusic.ui.navigation.destination.library.LibraryDynamicPlaylistDestination
import com.maxrave.simpmusic.ui.screen.library.LibraryDynamicPlaylistType
import com.maxrave.simpmusic.ui.theme.typo
import org.jetbrains.compose.resources.StringResource
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.stringResource
import simpmusic.composeapp.generated.resources.Res
import simpmusic.composeapp.generated.resources.albums
import simpmusic.composeapp.generated.resources.car_downloads
import simpmusic.composeapp.generated.resources.favorite
import simpmusic.composeapp.generated.resources.home
import simpmusic.composeapp.generated.resources.mono

private data class CarNavigationItem(
    val id: String,
    val title: StringResource,
    val icon: ImageVector,
    val destination: Any,
)

@Composable
fun CarNavigationRail(navController: NavController) {
    val currentEntry = navController.currentBackStackEntryAsState().value
    val favoriteType = LibraryDynamicPlaylistType.Favorite.toStringParams()
    val downloadedType = LibraryDynamicPlaylistType.Downloaded.toStringParams()
    val currentDynamicType =
        if (currentEntry?.destination?.hasRoute(LibraryDynamicPlaylistDestination::class) == true) {
            runCatching { currentEntry.toRoute<LibraryDynamicPlaylistDestination>().type }.getOrNull()
        } else {
            null
        }
    val selectedId =
        when {
            currentEntry?.destination?.hasRoute(HomeDestination::class) == true -> "home"
            currentEntry?.destination?.hasRoute(LibraryDestination::class) == true -> "albums"
            currentDynamicType == favoriteType -> "favorites"
            currentDynamicType == downloadedType -> "downloads"
            else -> null
        }
    val items =
        listOf(
            CarNavigationItem("home", Res.string.home, SimpIcons.Home, HomeDestination),
            CarNavigationItem("albums", Res.string.albums, SimpIcons.Album, LibraryDestination),
            CarNavigationItem(
                "favorites",
                Res.string.favorite,
                SimpIcons.Favorite,
                LibraryDynamicPlaylistDestination(favoriteType),
            ),
            CarNavigationItem(
                "downloads",
                Res.string.car_downloads,
                SimpIcons.DownloadForOffline,
                LibraryDynamicPlaylistDestination(downloadedType),
            ),
        )

    Column(
        modifier =
            Modifier
                .width(112.dp)
                .fillMaxHeight()
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 8.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painter = painterResource(Res.drawable.mono),
                contentDescription = null,
                modifier = Modifier.size(34.dp).clip(CircleShape),
            )
        }
        Spacer(Modifier.weight(1f))
        items.forEach { item ->
            val selected = selectedId == item.id
            Column(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .height(76.dp)
                        .clip(RoundedCornerShape(18.dp))
                        .background(
                            if (selected) {
                                MaterialTheme.colorScheme.secondaryContainer
                            } else {
                                MaterialTheme.colorScheme.surface
                            },
                        ).clickable {
                            navController.navigate(item.destination) {
                                popUpTo(navController.graph.startDestinationId) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }.padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    item.icon,
                    contentDescription = stringResource(item.title),
                    modifier = Modifier.size(30.dp),
                    tint =
                        if (selected) {
                            MaterialTheme.colorScheme.onSecondaryContainer
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                )
                Text(
                    text = stringResource(item.title),
                    style = typo().bodyMedium,
                    color =
                        if (selected) {
                            MaterialTheme.colorScheme.onSecondaryContainer
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    maxLines = 1,
                )
            }
            Spacer(Modifier.height(4.dp))
        }
        Spacer(Modifier.weight(1f))
    }
}

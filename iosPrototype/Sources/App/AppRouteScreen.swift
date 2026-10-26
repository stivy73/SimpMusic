import SwiftUI

struct AppRouteScreen: View {
  let route: AppRoute
  @EnvironmentObject private var library: LibraryModel
  @EnvironmentObject private var music: MusicModel
  @ViewBuilder var body: some View {
    switch route {
    case .statistics: ListeningScreen()
    case .received: SharedMusicInboxScreen()
    case .library, .player: LibraryView(library: library)
    case .playlist(let id):
      if library.session == nil {
        LibraryView(library: library)
      } else {
        let item =
          library.state(.playlists).items.first { $0.mediaId == id }
          ?? DiscoveryItem(
            kind: .playlist, mediaId: id, title: "Playlist", subtitle: "YouTube Music", artwork: nil
          )
        RemotePlaylistView(playlist: item)
      }
    case .album(let id):
      let release = music.releases.state.notices.first { $0.release.mediaId == id }
      AlbumView(
        album: LibraryAlbum(
          id: id, title: release?.release.title ?? "Album", artist: release?.artist.title ?? "",
          artwork: release?.release.artwork),
        identity: library.session?.identity)
    }
  }
}

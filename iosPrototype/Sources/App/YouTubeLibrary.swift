import Foundation

/// Remote saved albums stay distinct from favorites and discovery recommendations.
struct YouTubeLibrary: Sendable {
  let session: YouTubeSession

  func albums() async throws -> [LibraryAlbum] {
    let browse = YouTubeBrowse(session: session)
    return try await LibraryAlbumsPage.completed { token in
      try LibraryAlbumsPage.parse(
        await browse.request(browseId: "FEmusic_liked_albums", token: token))
    }
  }
}

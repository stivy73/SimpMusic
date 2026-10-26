import Foundation
import YouTubeSDK

/// Album data uses the confirmed account and only the album's own track shelves.
/// Recommendation carousels must never become part of Play or Download album.
public struct AlbumDetail: Sendable {
  public let album: LibraryAlbum
  public let year: String?
  public let description: String
  public let songs: [PlaybackTrack]
  public var durationSeconds: Double? {
    guard !songs.isEmpty, songs.allSatisfy({ ($0.durationSeconds ?? 0) > 0 }) else { return nil }
    return songs.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
  }

  public init(
    album: LibraryAlbum, year: String? = nil, description: String = "", songs: [PlaybackTrack],
    artists: [TrackArtist] = []
  ) {
    self.album = album
    self.year = year
    self.description = description
    self.songs = songs.map { song in
      var track = song.withAlbumArtwork(album.artwork, artist: album.artist, albumID: album.id)
      track.albumTitle = album.title
      if track.artistReferences?.isEmpty != false { track.artistReferences = artists }
      if track.artistBrowseID == nil { track.artistBrowseID = artists.first?.id }
      return track
    }
  }

  public static func load(album: LibraryAlbum, session: YouTubeSession?) async throws -> Self {
    let browse = YouTubeBrowse(session: session)
    return try await completed(album: album) { token in
      try await browse.request(browseId: album.id, token: token)
    }
  }

  public static func completed(
    album: LibraryAlbum, fetch: @Sendable (String?) async throws -> Data
  ) async throws -> Self {
    var metadata = AlbumMetadata(fallback: album)
    var tracks: [PlaybackTrack] = []
    var tokens = Set<String>()
    var token: String?
    repeat {
      try Task.checkCancellation()
      let data = try await fetch(token)
      try Task.checkCancellation()
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        root["error"] == nil
      else { throw LibraryError.malformed }
      if token == nil { metadata = AlbumMetadata(root: root, fallback: album) }
      let isolated = try trackPage(root)
      let page = try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: isolated))
      tracks += page.shelves.flatMap(\.items).filter { $0.kind == .song }.map(PlaybackTrack.init)
      token = page.continuation
      if let token, !tokens.insert(token).inserted { throw LibraryError.repeatedContinuation }
    } while token != nil
    try Task.checkCancellation()
    return Self(
      album: metadata.album, year: metadata.year, description: metadata.description, songs: tracks,
      artists: metadata.artists)
  }

  private static func trackPage(_ root: [String: Any]) throws -> Data {
    var rows: [[String: Any]] = []
    var continuation: [String: Any]?
    func visit(_ value: Any) {
      if let list = value as? [Any] {
        list.forEach(visit)
        return
      }
      guard let object = value as? [String: Any] else { return }
      // Deliberately skip carousels, headers, menus, suggestions and related albums.
      for key in ["musicShelfRenderer", "musicPlaylistShelfRenderer"] {
        if let shelf = object[key] as? [String: Any] {
          rows.append([key: shelf])
          return
        }
      }
      for key in [
        "musicShelfContinuation", "musicPlaylistShelfContinuation",
        "appendContinuationItemsAction", "reloadContinuationItemsCommand",
      ] {
        if let content = object[key] as? [String: Any] {
          continuation = [key: content]
          return
        }
      }
      for key in [
        "contents", "content", "tabs", "tabRenderer", "secondaryContents",
        "singleColumnBrowseResultsRenderer", "twoColumnBrowseResultsRenderer",
        "sectionListRenderer",
        "continuationContents", "onResponseReceivedActions", "onResponseReceivedEndpoints",
      ] {
        if let child = object[key] { visit(child) }
      }
    }
    visit(root)
    let result: [String: Any]
    if let continuation {
      result = ["continuationContents": continuation]
    } else {
      guard !rows.isEmpty else { throw LibraryError.malformed }
      result = ["contents": ["sectionListRenderer": ["contents": rows]]]
    }
    return try JSONSerialization.data(withJSONObject: result)
  }
}

private struct AlbumMetadata {
  let album: LibraryAlbum
  var year: String?
  var description = ""
  var artists: [TrackArtist] = []
  init(fallback: LibraryAlbum) { album = fallback }
  init(root: [String: Any], fallback: LibraryAlbum) {
    func find(_ keys: Set<String>, in value: Any) -> [String: Any]? {
      if let list = value as? [Any] {
        return list.lazy.compactMap { find(keys, in: $0) }.first
      }
      guard let object = value as? [String: Any] else { return nil }
      for key in keys.sorted() {
        if let found = object[key] as? [String: Any] { return found }
      }
      for key in object.keys.sorted() where !key.contains("Carousel") {
        if let found = find(keys, in: object[key]!) { return found }
      }
      return nil
    }
    func text(_ value: Any?) -> String {
      guard let object = value as? [String: Any] else { return "" }
      return (object["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        ?? object["simpleText"] as? String ?? ""
    }
    let header =
      find(["musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer"], in: root) ?? [:]
    let title = text(header["title"])
    let subtitle = text(header["subtitle"])
    let runs =
      ((header["straplineTextOne"] as? [String: Any])?["runs"] as? [[String: Any]] ?? [])
      + ((header["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]] ?? [])
    let artist = runs.filter {
      let nav = $0["navigationEndpoint"] as? [String: Any]
      let browse = nav?["browseEndpoint"] as? [String: Any]
      return (browse?["browseId"] as? String)?.hasPrefix("UC") == true
    }.compactMap { $0["text"] as? String }.joined(separator: ", ")
    for run in runs {
      let endpoint = run["navigationEndpoint"] as? [String: Any]
      let browse = endpoint?["browseEndpoint"] as? [String: Any]
      if let id = browse?["browseId"] as? String, id.hasPrefix("UC"),
        let name = run["text"] as? String, !artists.contains(where: { $0.id == id })
      {
        artists.append(.init(id: id, name: name))
      }
    }
    let fallbackArtist = AlbumTrackMetadata.artist(from: fallback.artist) ?? ""
    let thumbnails = find(
      ["musicThumbnailRenderer", "croppedSquareThumbnailRenderer"],
      in: header["thumbnail"] ?? header["thumbnailRenderer"] ?? [:])
    let image = (thumbnails?["thumbnail"] as? [String: Any] ?? thumbnails ?? [:])
    let artwork = (image["thumbnails"] as? [[String: Any]])?.last.flatMap {
      ($0["url"] as? String).flatMap(URL.init(string:))
    }
    album = LibraryAlbum(
      id: fallback.id, title: title.isEmpty ? fallback.title : title,
      artist: artist.isEmpty ? fallbackArtist : artist,
      artwork: artwork?.scheme == "https" ? artwork : fallback.artwork)
    if let range = subtitle.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) {
      year = String(subtitle[range])
    }
    let descriptionRenderer =
      find(["musicDescriptionShelfRenderer"], in: header)
      ?? find(["musicDescriptionShelfRenderer"], in: root)
    description = text(descriptionRenderer?["description"] ?? header["description"])
  }
}

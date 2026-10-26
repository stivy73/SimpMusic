import Foundation
import YouTubeSDK

public typealias TrackArtist = YouTubeMusicArtistReference

public struct PlaybackTrack: Identifiable, Codable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let artist: String
  public let artwork: URL?
  public let durationSeconds: Double?
  public var albumBrowseID: String? = nil
  public var albumTitle: String? = nil
  public var artistBrowseID: String? = nil
  public var artistReferences: [TrackArtist]? = nil
  public init(
    id: String, title: String, artist: String, artwork: URL?, durationSeconds: Double? = nil,
    albumBrowseID: String? = nil, albumTitle: String? = nil, artistBrowseID: String? = nil,
    artistReferences: [TrackArtist]? = nil
  ) {
    self.id = id
    self.title = title
    self.artist = artist
    self.artwork = artwork
    self.durationSeconds = durationSeconds
    self.albumBrowseID = albumBrowseID
    self.albumTitle = albumTitle
    self.artistBrowseID = artistBrowseID
    self.artistReferences = artistReferences
  }
  public init(_ item: DiscoveryItem) {
    albumBrowseID = item.albumBrowseID
    artistBrowseID = item.artistBrowseID
    albumTitle = item.albumTitle
    artistReferences = item.artistReferences
    id = item.mediaId
    title = item.title
    artist = item.subtitle
    artwork = item.artwork
    durationSeconds = item.durationSeconds
  }
  public var discoveryItem: DiscoveryItem {
    DiscoveryItem(
      kind: .song, mediaId: id, title: title, subtitle: artist, artwork: artwork,
      durationSeconds: durationSeconds, albumBrowseID: albumBrowseID,
      artistBrowseID: artistBrowseID, albumTitle: albumTitle, artistReferences: artistReferences)
  }
  public func withAlbumArtwork(
    _ albumArtwork: URL?, artist albumArtist: String? = nil, albumID: String? = nil
  ) -> PlaybackTrack {
    var result = PlaybackTrack(
      id: id, title: title,
      artist: artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? albumArtist ?? artist : artist,
      artwork: albumArtwork ?? artwork,
      durationSeconds: durationSeconds)
    result.artistBrowseID = artistBrowseID
    result.artistReferences = artistReferences
    result.albumTitle = albumTitle
    result.albumBrowseID = albumID ?? albumBrowseID
    return result
  }
  public init(_ song: YouTubeMusicSong, albumArtwork: URL? = nil) {
    id = song.videoId
    title = song.title
    artist = song.artistsDisplay
    artwork = albumArtwork ?? song.thumbnailURL
    durationSeconds = song.duration
    albumTitle = song.album
    albumBrowseID = song.albumBrowseID
    artistBrowseID = song.artistBrowseID
    artistReferences = song.artistReferences
  }
}

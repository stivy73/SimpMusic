import Foundation
import YouTubeSDK

public typealias BrowseTarget = YouTubeMusicBrowseEndpoint

public struct HomeFilter: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let params: String?
  public static let all = HomeFilter(id: "all", title: "Tutto", params: nil)
  // Exact HomeViewModel.HOME_PARAMS_* values from SimpMusic; see Scripts/CheckHomeFilters.py.
  public static let values: [HomeFilter] = [
    all,
    HomeFilter(
      id: "relax", title: "Relax",
      params: "ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "sleep", title: "Riposo",
      params: "ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "energize", title: "Energetico",
      params: "ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "sad", title: "Triste",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "romance", title: "Romantico",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "feel_good", title: "Buonumore",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBADSgQIBBABSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "workout", title: "Allenamento",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBADSgQIDhABSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "party", title: "Festa",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhADSgQIAxABSgQIBhAB"
    ),
    HomeFilter(
      id: "commute", title: "In viaggio",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxADSgQIBhAB"
    ),
    HomeFilter(
      id: "focus", title: "Concentrazione",
      params: "ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAD"
    ),
  ]
}

public struct DiscoveryItem: Identifiable, Codable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable { case song, album, playlist, artist }
  public let kind: Kind
  public let mediaId: String
  public let title: String
  public let subtitle: String
  public let artwork: URL?
  public let durationSeconds: Double?
  public var id: String { kind.rawValue + ":" + mediaId }
  public var albumBrowseID: String? = nil
  public var artistBrowseID: String? = nil
  public var albumTitle: String? = nil
  public var artistReferences: [TrackArtist]? = nil
  public var target: BrowseTarget? { kind == .song ? nil : BrowseTarget(browseId: mediaId) }

  public init(
    kind: Kind, mediaId: String, title: String, subtitle: String, artwork: URL?,
    durationSeconds: Double? = nil, albumBrowseID: String? = nil,
    artistBrowseID: String? = nil, albumTitle: String? = nil,
    artistReferences: [TrackArtist]? = nil
  ) {
    self.kind = kind
    self.mediaId = mediaId
    self.title = title
    self.subtitle = subtitle
    self.artwork = artwork
    self.durationSeconds = durationSeconds
    self.albumBrowseID = albumBrowseID
    self.artistBrowseID = artistBrowseID
    self.albumTitle = albumTitle
    self.artistReferences = artistReferences
  }

  init(_ item: YouTubeMusicItem) {
    switch item {
    case .song(let value):
      albumBrowseID = value.albumBrowseID
      artistBrowseID = value.artistBrowseID
      albumTitle = value.album
      artistReferences = value.artistReferences
      kind = .song
      mediaId = value.videoId
      title = value.title
      subtitle = value.artistsDisplay
      artwork = value.thumbnailURL
      durationSeconds = value.duration
    case .album(let value):
      kind = .album
      mediaId = value.id
      title = value.title
      subtitle = value.artist ?? "Album"
      artwork = value.thumbnailURL
      durationSeconds = nil
    case .playlist(let value):
      kind = .playlist
      mediaId = value.id
      title = value.title
      subtitle = value.author ?? "Playlist"
      artwork = value.thumbnailURL
      durationSeconds = nil
    case .artist(let value):
      kind = .artist
      mediaId = value.id
      title = value.name
      subtitle = "Artista"
      artwork = value.thumbnailURL
      durationSeconds = nil
    }
  }
}

public struct HomeShelf: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let avatar: URL?
  public let more: BrowseTarget?
  public var items: [DiscoveryItem]

  public init(id: String, title: String, items: [DiscoveryItem], more: BrowseTarget? = nil) {
    self.id = id
    self.title = title
    self.items = items
    self.more = more
    subtitle = ""
    avatar = nil
  }

  init(_ section: YouTubeMusicSection) {
    title = section.title
    subtitle = section.subtitle
    avatar = section.thumbnailURL
    more = section.moreEndpoint
    id = [
      title, subtitle, more?.browseId ?? "", more?.params ?? "",
      title.isEmpty ? "tracks" : "",
    ].joined(separator: "|")
    var seen = Set<String>()
    items = section.items.map(DiscoveryItem.init).filter { seen.insert($0.id).inserted }
  }
}

public struct HomeCategory: Identifiable, Hashable, Sendable {
  public let title: String
  public let stripeColor: UInt32
  public let target: BrowseTarget
  public var id: String { target.browseId + ":" + (target.params ?? "") }
}

public struct HomeCategorySection: Identifiable, Sendable {
  public let title: String
  public let items: [HomeCategory]
  public var id: String { title }
}

public struct HomePage: Sendable {
  public var shelves: [HomeShelf]
  public var categories: [HomeCategorySection]
  public let continuation: String?
  public init(shelves: [HomeShelf], continuation: String? = nil) {
    self.shelves = shelves
    self.categories = []
    self.continuation = continuation
  }
  public init(_ page: YouTubeMusicHomePage) {
    shelves = page.sections.map(HomeShelf.init)
    categories = page.categories.map { section in
      var seen = Set<String>()
      let items = section.items.map {
        HomeCategory(title: $0.title, stripeColor: $0.stripeColor, target: $0.endpoint)
      }.filter { seen.insert($0.id).inserted }
      return HomeCategorySection(title: section.title, items: items)
    }
    continuation = page.continuationToken
  }
}

public struct HomeDiscovery: Sendable {
  private let browse: YouTubeBrowse
  private let parser = YouTubeMusicClient()
  public init(session: YouTubeSession?) { browse = YouTubeBrowse(session: session) }
  public func page(target: BrowseTarget, continuation: String? = nil) async throws -> HomePage {
    let data = try await browse.request(
      browseId: target.browseId, params: target.params, token: continuation)
    return try await HomePage(parser.decodeDiscoveryPage(from: data))
  }
  public func libraryPage(kind: RemoteLibraryKind, continuation: String? = nil) async throws
    -> HomePage
  {
    let data = try await browse.request(browseId: kind.browseID, token: continuation)
    return try await HomePage(parser.decodeDiscoveryPage(from: data, strictItems: true))
  }
}

/// Same typed search filters used by the Android fork; don't filter a songs-only response.
public enum MusicSearchFilter: String, CaseIterable, Sendable {
  case songs = "Canzoni"
  case artists = "Artisti"
  case albums = "Album"
  case playlists = "Playlist di YouTube Music"
  case communityPlaylists = "Playlist della community"
  case videos = "Video"
  case podcasts = "Podcast"
  // Keep the existing vehicle search focused on its three supported media types.
  public static let carPlay: [Self] = [.songs, .artists, .albums]
  public var params: String {
    switch self {
    case .songs: "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
    case .artists: "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
    case .albums: "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
    case .playlists: "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"
    case .communityPlaylists: "EgeKAQQoAEABagoQAxAEEAoQCRAF"
    case .videos: "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
    case .podcasts: "EgWKAQJQAWoIEBAQERADEBU%3D"
    }
  }
  public var kind: DiscoveryItem.Kind {
    switch self {
    case .songs, .videos: .song
    case .artists: .artist
    case .albums: .album
    case .playlists, .communityPlaylists, .podcasts: .playlist
    }
  }
  public var symbol: String {
    switch self {
    case .songs: "music.note"
    case .artists: "person.fill"
    case .albums: "square.stack.fill"
    case .playlists, .communityPlaylists: "music.note.list"
    case .videos: "play.rectangle"
    case .podcasts: "mic.fill"
    }
  }
  public var identifier: String {
    switch self {
    case .songs: "songs"
    case .artists: "artists"
    case .albums: "albums"
    case .playlists: "playlists"
    case .communityPlaylists: "community"
    case .videos: "videos"
    case .podcasts: "podcasts"
    }
  }
}

extension HomeDiscovery {
  public func search(query: String, filter: MusicSearchFilter) async throws -> [DiscoveryItem] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }
    return try await searchPage(query: query, filter: filter).items
  }

  public func searchPage(query: String, filter: MusicSearchFilter, continuation: String? = nil)
    async throws -> MusicSearchPage
  {
    let data = try await browse.search(query: query, filter: filter, continuation: continuation)
    return try await MusicSearchPage.decode(data, filter: filter)
  }
}

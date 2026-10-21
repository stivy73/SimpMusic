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

public struct DiscoveryItem: Identifiable, Hashable, Sendable {
  public enum Kind: String, Sendable { case song, album, playlist, artist }
  public let kind: Kind
  public let mediaId: String
  public let title: String
  public let subtitle: String
  public let artwork: URL?
  public let durationSeconds: Double?
  public var id: String { kind.rawValue + ":" + mediaId }
  public var target: BrowseTarget? { kind == .song ? nil : BrowseTarget(browseId: mediaId) }

  init(_ item: YouTubeMusicItem) {
    switch item {
    case .song(let value):
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
}

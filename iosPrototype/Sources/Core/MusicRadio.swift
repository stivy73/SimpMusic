import Foundation

/// WEB_REMIX watch endpoint, shared by song radio, artist radio and automix continuation.
public struct RadioEndpoint: Hashable, Sendable {
  public let videoID: String?
  public let playlistID: String?
  public let params: String?
  public let index: Int?
  public let playlistSetVideoID: String?

  public init(
    videoID: String? = nil, playlistID: String? = nil, params: String? = nil,
    index: Int? = nil, playlistSetVideoID: String? = nil
  ) {
    self.videoID = videoID
    self.playlistID = playlistID
    self.params = params
    self.index = index
    self.playlistSetVideoID = playlistSetVideoID
  }
  public static func song(_ id: String) -> Self {
    Self(videoID: id, playlistID: "RDAMVM" + id)
  }
  var fields: [String: Any] {
    var result: [String: Any] = [:]
    if let videoID { result["videoId"] = videoID }
    if let playlistID { result["playlistId"] = playlistID }
    if let params { result["params"] = params }
    if let index { result["index"] = index }
    if let playlistSetVideoID { result["playlistSetVideoId"] = playlistSetVideoID }
    return result
  }
  static func decode(_ value: [String: Any]) -> Self? {
    let endpoint = Self(
      videoID: value["videoId"] as? String,
      playlistID: value["playlistId"] as? String, params: value["params"] as? String,
      index: value["index"] as? Int, playlistSetVideoID: value["playlistSetVideoId"] as? String)
    return endpoint.videoID?.isEmpty == false || endpoint.playlistID?.isEmpty == false
      ? endpoint : nil
  }

  /// Use the actual artist's radio button; never substitute a title search or a fabricated playlist.
  public static func artist(in data: Data) throws -> Self {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let header = root["header"] as? [String: Any] ?? [:]
    for name in [
      "musicImmersiveHeaderRenderer", "musicVisualHeaderRenderer", "musicHeaderRenderer",
    ] {
      let renderer = header[name] as? [String: Any] ?? [:]
      let radio = renderer["startRadioButton"] as? [String: Any] ?? [:]
      let button = radio["buttonRenderer"] as? [String: Any] ?? [:]
      let navigation = button["navigationEndpoint"] as? [String: Any] ?? [:]
      if let watch = navigation["watchEndpoint"] as? [String: Any], let result = decode(watch) {
        return result
      }
    }
    throw RadioError.unavailable
  }
}

public enum RadioError: LocalizedError {
  case unavailable, repeatedPage
  public var errorDescription: String? {
    switch self {
    case .unavailable: "YouTube Music non ha restituito suggerimenti riproducibili. Riprova."
    case .repeatedPage: "YouTube Music ha ripetuto la coda radio. Riprova."
    }
  }
}

public struct RadioPage: Sendable {
  public var items: [DiscoveryItem]
  public let endpoint: RadioEndpoint
  public let continuation: String?
  public let automix: RadioEndpoint?

  public static func decode(_ data: Data, endpoint: RadioEndpoint) throws -> Self {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    func path(_ root: [String: Any], _ keys: [String]) -> [String: Any]? {
      var result = root
      for key in keys {
        guard let next = result[key] as? [String: Any] else { return nil }
        result = next
      }
      return result
    }
    let tabs =
      path(
        root,
        [
          "contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer",
          "watchNextTabbedResultsRenderer",
        ])?["tabs"] as? [[String: Any]] ?? []
    let panel =
      path(root, ["continuationContents", "playlistPanelContinuation"])
      ?? tabs.compactMap {
        path(
          $0, ["tabRenderer", "content", "musicQueueRenderer", "content", "playlistPanelRenderer"])
      }.first
    guard let panel, let contents = panel["contents"] as? [[String: Any]] else {
      throw RadioError.unavailable
    }
    func text(_ object: [String: Any]?) -> String {
      if let simple = object?["simpleText"] as? String { return simple }
      return (object?["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        .joined()
    }
    var items: [DiscoveryItem] = []
    var automix: RadioEndpoint?
    for entry in contents {
      if let watch = path(
        entry,
        [
          "automixPreviewVideoRenderer", "content", "automixPlaylistVideoRenderer",
          "navigationEndpoint", "watchPlaylistEndpoint",
        ])
      {
        automix = RadioEndpoint.decode(watch)
      }
      guard let video = entry["playlistPanelVideoRenderer"] as? [String: Any],
        video["unplayableText"] == nil, video["isPlayable"] as? Bool != false,
        let id = video["videoId"] as? String, !id.isEmpty
      else { continue }
      let title = text(video["title"] as? [String: Any])
      guard !title.isEmpty else { continue }
      let runs = (video["longBylineText"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
      let linked = runs.compactMap { run -> (String, String)? in
        guard
          let target = path(run, ["navigationEndpoint", "browseEndpoint"])?["browseId"] as? String
        else { return nil }
        return (target, run["text"] as? String ?? "")
      }
      let artist = linked.first { $0.0.hasPrefix("UC") }
      let album = linked.first { $0.0.hasPrefix("MPRE") }
      let thumbnail =
        (video["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
      let artwork = thumbnail.compactMap { $0["url"] as? String }.last.flatMap(URL.init(string:))
      let length = text(video["lengthText"] as? [String: Any]).split(separator: ":").compactMap {
        Double($0)
      }
      let duration = length.isEmpty ? nil : length.reduce(0) { $0 * 60 + $1 }
      items.append(
        DiscoveryItem(
          kind: .song, mediaId: id, title: title,
          subtitle: artist?.1 ?? text(video["longBylineText"] as? [String: Any]).components(
            separatedBy: " • "
          ).first ?? "",
          artwork: artwork, durationSeconds: duration,
          albumBrowseID: album?.0, artistBrowseID: artist?.0, albumTitle: album?.1))
    }
    let continuations = panel["continuations"] as? [[String: Any]] ?? []
    let token = continuations.compactMap {
      path($0, ["nextContinuationData"])?["continuation"] as? String
        ?? path($0, ["nextRadioContinuationData"])?["continuation"] as? String
    }.first
    return Self(
      items: items, endpoint: endpoint, continuation: token?.isEmpty == false ? token : nil,
      automix: automix)
  }
}

/// Follows Android's automix pointer, preserving its watch endpoint for subsequent pages.
public struct MusicRadio: Sendable {
  public typealias Loader = @Sendable (RadioEndpoint, String?) async throws -> Data
  private let load: Loader
  private let browse: YouTubeBrowse?
  public init(session: YouTubeSession?) {
    let browse = YouTubeBrowse(session: session)
    self.browse = browse
    load = { try await browse.next(endpoint: $0, continuation: $1) }
  }
  public init(load: @escaping Loader) {
    self.load = load
    browse = nil
  }
  public func artistEndpoint(id: String) async throws -> RadioEndpoint {
    guard let browse else { throw RadioError.unavailable }
    return try RadioEndpoint.artist(in: await browse.request(browseId: id))
  }
  public func page(endpoint: RadioEndpoint, continuation: String? = nil) async throws -> RadioPage {
    var page = try RadioPage.decode(await load(endpoint, continuation), endpoint: endpoint)
    var visited: Set<RadioEndpoint> = [endpoint]
    var items = page.items
    while let next = page.automix {
      guard visited.insert(next).inserted, visited.count <= 4 else { throw RadioError.repeatedPage }
      try Task.checkCancellation()
      page = try RadioPage.decode(await load(next, nil), endpoint: next)
      items += page.items
    }
    return RadioPage(
      items: items, endpoint: page.endpoint, continuation: page.continuation, automix: nil)
  }
}

/// Request cursor rejects repeated continuations and suggestions already present in the user's queue.
public struct RadioCursor: Sendable {
  public private(set) var endpoint: RadioEndpoint
  public private(set) var continuation: String?
  public private(set) var exhausted = false
  private var requested = Set<String>()
  public init(endpoint: RadioEndpoint) { self.endpoint = endpoint }
  public mutating func accept(_ page: RadioPage, excluding ids: Set<String>) throws
    -> [DiscoveryItem]
  {
    if let token = page.continuation, !requested.insert(token).inserted {
      throw RadioError.repeatedPage
    }
    endpoint = page.endpoint
    continuation = page.continuation
    exhausted = continuation == nil
    var seen = ids
    return page.items.filter { $0.kind == .song && seen.insert($0.mediaId).inserted }
  }
}

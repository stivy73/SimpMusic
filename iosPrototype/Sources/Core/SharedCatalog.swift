import Combine
import Foundation

public enum SharedCatalogError: LocalizedError {
  case unavailable, malformed, tooLarge
  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "Contenuto non accessibile dal link pubblico. Per una playlist privata, rendila condivisibile nell’app di origine e condividila nuovamente."
    case .malformed:
      "Non riesco a leggere le informazioni del contenuto condiviso. Riprova oppure cerca titolo e artista."
    case .tooLarge:
      "Questo contenuto supera il limite di importazione. Condividi una raccolta più piccola."
    }
  }
}

public struct SharedCatalogTrack: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let artists: [String]
  public let artwork: URL?
  public let duration: Double?
  public var artist: String { artists.joined(separator: ", ") }
  public var query: String { title + " " + artist }
  public init(
    id: String, title: String, artists: [String], artwork: URL? = nil, duration: Double? = nil
  ) {
    self.id = id
    self.title = title
    self.artists = artists
    self.artwork = artwork
    self.duration = duration
  }

  /// Do not silently substitute a cover, live performance, remix or a substantially different edit.
  public func match(_ items: [DiscoveryItem]) -> DiscoveryItem? {
    func titleKey(_ value: String) -> String {
      MusicSuggestion.normalize(
        value.replacingOccurrences(
          of:
            #"\s*[\(\[][^)\]]*\bremaster(?:ed)?\b[^)\]]*[\)\]]|\s*[-–]\s*(?:[12][0-9]{3}\s+)?remaster(?:ed)?(?:\s+[12][0-9]{3})?$|\s*[\(\[]official (?:audio|video)[\)\]]"#,
          with: "", options: [.regularExpression, .caseInsensitive]))
    }
    let expected = Set(artists.map(MusicSuggestion.normalize).filter { !$0.isEmpty })
    guard !expected.isEmpty else { return nil }
    let verified = items.filter { item in
      guard item.kind == .song, !item.mediaId.isEmpty, titleKey(item.title) == titleKey(title)
      else { return false }
      let credits =
        (item.artistReferences ?? []).map(\.name)
        + item.subtitle.components(separatedBy: ", ") + [item.subtitle]
      let actual = Set(credits.map(MusicSuggestion.normalize))
      guard expected.isSubset(of: actual) else { return false }
      if let duration, let found = item.durationSeconds,
        abs(duration - found) > max(8, duration * 0.05)
      {
        return false
      }
      return true
    }
    return verified.min {
      abs(($0.durationSeconds ?? duration ?? 0) - (duration ?? 0))
        < abs(($1.durationSeconds ?? duration ?? 0) - (duration ?? 0))
    }
  }
}

public struct SharedCatalogCollection: Sendable {
  public let link: SharedCatalogLink
  public let title: String
  public let subtitle: String
  public let artwork: URL?
  public let tracks: [SharedCatalogTrack]
  public let total: Int?
  public let warning: String?
  public init(
    link: SharedCatalogLink, title: String, subtitle: String, artwork: URL?,
    tracks: [SharedCatalogTrack], total: Int?, warning: String? = nil
  ) {
    self.link = link
    self.title = title
    self.subtitle = subtitle
    self.artwork = artwork
    self.tracks = tracks
    self.total = total
    self.warning = warning
  }
}

/// Public metadata only. No provider cookies, bearer tokens, preview audio or API keys are used.
public struct SharedCatalogResolver: Sendable {
  public struct Response: Sendable {
    public let data: Data
    public let url: URL
    public init(data: Data, url: URL) {
      self.data = data
      self.url = url
    }
  }
  public typealias Fetch = @Sendable (URL, SharedCatalogLink.Provider) async throws -> Response
  private let fetch: Fetch
  public init(fetch: Fetch? = nil) {
    self.fetch = fetch ?? { try await SharedCatalogHTTP.fetch($0, provider: $1) }
  }
  public func resolve(_ input: SharedCatalogLink) async throws -> SharedCatalogCollection {
    guard input.valid else { throw SharedCatalogError.malformed }
    var link = input
    if link.kind == .shortLink {
      let expanded = try await fetch(link.url, link.provider)
      guard let canonical = SharedCatalogLink.parse(expanded.url), canonical.kind != .shortLink,
        canonical.provider == link.provider
      else { throw SharedCatalogError.unavailable }
      link = canonical
    }
    try Task.checkCancellation()
    if link.provider == .spotify {
      let url = URL(string: "https://open.spotify.com/embed/\(link.kind.rawValue)/\(link.id)")!
      return try Self.spotify(try await fetch(url, .spotify).data, link: link)
    }
    if link.kind != .playlist {
      var url = URLComponents(string: "https://itunes.apple.com/lookup")!
      url.queryItems = [
        URLQueryItem(name: "id", value: link.id),
        URLQueryItem(name: "country", value: link.country),
        URLQueryItem(name: "entity", value: "song"),
        URLQueryItem(name: "limit", value: "200"),
      ]
      do {
        return try Self.appleLookup(try await fetch(url.url!, .appleMusic).data, link: link)
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
      }
    }
    return try Self.applePage(try await fetch(link.url, .appleMusic).data, link: link)
  }

  public static func appleLookup(_ data: Data, link: SharedCatalogLink) throws
    -> SharedCatalogCollection
  {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let rows = root?["results"] as? [[String: Any]] ?? []
    let collection = rows.first {
      number($0["collectionId"]) == link.id && $0["wrapperType"] as? String == "collection"
    }
    let songs = rows.filter {
      $0["kind"] as? String == "song"
        && (link.kind == .track
          ? number($0["trackId"]) == link.id : number($0["collectionId"]) == link.id)
    }
    guard let first = songs.first, songs.count <= 500,
      link.kind == .track || collection != nil
    else { throw SharedCatalogError.unavailable }
    let tracks = try songs.map { row in
      try track(
        id: number(row["trackId"]), title: row["trackName"],
        artists: [row["artistName"] as? String ?? ""], artwork: artwork(row["artworkUrl100"]),
        milliseconds: row["trackTimeMillis"])
    }
    let header = link.kind == .track ? first : collection!
    let total = link.kind == .track ? 1 : (header["trackCount"] as? Int)
    return SharedCatalogCollection(
      link: link,
      title: try text(header[link.kind == .track ? "trackName" : "collectionName"]),
      subtitle: header["artistName"] as? String ?? "", artwork: artwork(header["artworkUrl100"]),
      tracks: tracks, total: total, warning: coverage(tracks.count, total: total))
  }

  public static func spotify(_ data: Data, link: SharedCatalogLink) throws
    -> SharedCatalogCollection
  {
    let html = String(decoding: data, as: UTF8.self)
    guard let json = script(html, id: "__NEXT_DATA__") as? [String: Any],
      let props = json["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
      let state = page["state"] as? [String: Any], let payload = state["data"] as? [String: Any],
      let entity = payload["entity"] as? [String: Any], entity["id"] as? String == link.id,
      entity["type"] as? String == link.kind.rawValue
    else { throw SharedCatalogError.unavailable }
    let image = spotifyArtwork(entity)
    let title = try text(entity["name"] ?? entity["title"])
    let tracks: [SharedCatalogTrack]
    if link.kind == .track {
      let artists = (entity["artists"] as? [[String: Any]] ?? []).compactMap {
        $0["name"] as? String
      }
      tracks = [
        try track(
          id: link.id, title: title, artists: artists, artwork: image,
          milliseconds: entity["duration"])
      ]
    } else {
      guard let rows = entity["trackList"] as? [[String: Any]], !rows.isEmpty else {
        throw SharedCatalogError.unavailable
      }
      guard rows.count <= 500 else { throw SharedCatalogError.tooLarge }
      tracks = try rows.enumerated().map { index, row in
        guard row["entityType"] as? String == "track",
          let uri = row["uri"] as? String, uri.hasPrefix("spotify:track:"),
          uri.dropFirst(14).range(of: "^[A-Za-z0-9]{22}$", options: .regularExpression) != nil
        else { throw SharedCatalogError.malformed }
        let artists = (row["subtitle"] as? String ?? "").replacingOccurrences(
          of: "\u{00a0}", with: " "
        )
        .components(separatedBy: ", ")
        return try track(
          id: "\(index):\(uri.dropFirst(14))", title: row["title"], artists: artists,
          artwork: image, milliseconds: row["duration"])
      }
    }
    let total = link.kind == .track ? 1 : entity["totalTracks"] as? Int
    let warning = coverage(tracks.count, total: total)
    return SharedCatalogCollection(
      link: link, title: title,
      subtitle: entity["subtitle"] as? String ?? tracks.first?.artist ?? "", artwork: image,
      tracks: tracks, total: total, warning: warning)
  }

  public static func applePage(_ data: Data, link: SharedCatalogLink) throws
    -> SharedCatalogCollection
  {
    let html = String(decoding: data, as: UTF8.self)
    guard let json = script(html, id: "serialized-server-data") as? [String: Any],
      let pages = json["data"] as? [[String: Any]],
      let page = pages.first?["data"] as? [String: Any],
      let sections = page["sections"] as? [[String: Any]],
      let header = sections.first(where: {
        $0["itemKind"] as? String == "containerDetailHeaderLockup"
      }),
      let info = (header["items"] as? [[String: Any]])?.first
    else { throw SharedCatalogError.unavailable }
    // A song permalink can redirect to its album page. Select only that exact song ID.
    let lists = sections.filter { section in
      guard section["itemKind"] as? String == "trackLockup" else { return false }
      if link.kind == .track { return true }
      let descriptor = section["containerContentDescriptor"] as? [String: Any]
      let ids = descriptor?["identifiers"] as? [String: Any]
      return ids?["storeAdamID"] as? String == link.id
    }
    let rows = lists.flatMap { $0["items"] as? [[String: Any]] ?? [] }.filter { row in
      guard link.kind == .track else { return true }
      let descriptor = row["contentDescriptor"] as? [String: Any]
      let ids = descriptor?["identifiers"] as? [String: Any]
      return ids?["storeAdamID"] as? String == link.id
    }
    guard !rows.isEmpty, link.kind != .track || rows.count == 1 else {
      throw SharedCatalogError.unavailable
    }
    guard rows.count <= 500 else { throw SharedCatalogError.tooLarge }
    let image = appleArtwork(info["artwork"])
    let artist = linksText(info["subtitleLinks"])
    let tracks = try rows.enumerated().map { index, row in
      let descriptor = row["contentDescriptor"] as? [String: Any]
      let ids = descriptor?["identifiers"] as? [String: Any]
      guard descriptor?["kind"] as? String == "song", let id = ids?["storeAdamID"] as? String else {
        throw SharedCatalogError.malformed
      }
      let artists = row["artistName"] as? String ?? linksText(row["subtitleLinks"])
      return try track(
        id: "\(index):\(id)", title: row["title"],
        artists: (artists.isEmpty ? artist : artists).components(separatedBy: ", "),
        artwork: appleArtwork(row["artwork"]) ?? image, milliseconds: row["duration"])
    }
    let schema =
      script(html, id: link.kind == .playlist ? "schema:music-playlist" : "schema:music-album")
      as? [String: Any]
    let total = link.kind == .track ? 1 : schema?["numTracks"] as? Int
    return SharedCatalogCollection(
      link: link, title: link.kind == .track ? tracks[0].title : try text(info["title"]),
      subtitle: link.kind == .track ? tracks[0].artist : artist,
      artwork: link.kind == .track ? tracks[0].artwork : image,
      tracks: tracks, total: total, warning: coverage(tracks.count, total: total))
  }

  private static func coverage(_ count: Int, total: Int?) -> String? {
    if let total, count == total { return nil }
    if let total {
      return "Il servizio espone \(count) tracce su \(total). Puoi importare solo quelle visibili."
    }
    return
      "Sono visibili \(count) tracce dal link pubblico. Il servizio potrebbe non esporre l’intera raccolta."
  }
  private static func track(
    id: String?, title: Any?, artists: [String], artwork: URL?, milliseconds: Any?
  ) throws -> SharedCatalogTrack {
    guard let id, !id.isEmpty, id.count <= 160, !artists.isEmpty else {
      throw SharedCatalogError.malformed
    }
    let validArtists = try artists.map { try text($0) }
    let ms = (milliseconds as? NSNumber)?.doubleValue
    let duration = ms.flatMap { $0.isFinite && $0 > 0 && $0 <= 86_400_000 ? $0 / 1000 : nil }
    return SharedCatalogTrack(
      id: id, title: try text(title), artists: validArtists, artwork: artwork, duration: duration)
  }
  private static func text(_ raw: Any?) throws -> String {
    guard let value = raw as? String, let clean = SharedMusicTarget.queryText(value),
      clean.count <= 250
    else { throw SharedCatalogError.malformed }
    return clean
  }
  private static func number(_ raw: Any?) -> String? {
    (raw as? NSNumber)?.stringValue ?? raw as? String
  }
  private static func linksText(_ raw: Any?) -> String {
    (raw as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }.joined(separator: ", ")
  }
  private static func appleArtwork(_ raw: Any?) -> URL? {
    let box = raw as? [String: Any]
    let values = box?["dictionary"] as? [String: Any]
    return artwork(values?["url"])
  }
  private static func spotifyArtwork(_ entity: [String: Any]) -> URL? {
    let visual = entity["visualIdentity"] as? [String: Any]
    let images = visual?["image"] as? [[String: Any]]
    let cover = entity["coverArt"] as? [String: Any]
    return artwork(images?.last?["url"] ?? (cover?["sources"] as? [[String: Any]])?.first?["url"])
  }
  private static func artwork(_ raw: Any?) -> URL? {
    guard let value = raw as? String else { return nil }
    let address = value.replacingOccurrences(of: "{w}", with: "600")
      .replacingOccurrences(of: "{h}", with: "600").replacingOccurrences(of: "{f}", with: "jpg")
      .replacingOccurrences(of: "100x100bb", with: "600x600bb")
    guard let url = URL(string: address), SharedCatalogLink.safe(url), let host = url.host,
      host.hasSuffix(".mzstatic.com") || host.hasSuffix(".scdn.co")
        || host.hasSuffix(".spotifycdn.com")
    else { return nil }
    return url
  }
  private static func script(_ html: String, id: String) -> Any? {
    let escaped = NSRegularExpression.escapedPattern(for: id)
    guard
      let re = try? NSRegularExpression(
        pattern: "<script\\b[^>]*\\bid=[\"']?" + escaped
          + "[\"']?(?=[\\s>])[^>]*>([\\s\\S]*?)</script>", options: .caseInsensitive),
      let match = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
      let range = Range(match.range(at: 1), in: html)
    else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(html[range].utf8))
  }
}

final class SharedCatalogRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  let provider: SharedCatalogLink.Provider
  init(_ provider: SharedCatalogLink.Provider) { self.provider = provider }
  static func allowed(_ url: URL, provider: SharedCatalogLink.Provider) -> Bool {
    guard SharedCatalogLink.safe(url), let host = url.host else { return false }
    let hosts: Set<String> =
      provider == .spotify
      ? ["open.spotify.com", "spotify.link", "spotify.app.link"]
      : ["music.apple.com", "geo.music.apple.com", "itunes.apple.com", "apple.co", "www.apple.co"]
    return hosts.contains(host)
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(
      request.url.map { Self.allowed($0, provider: provider) } == true ? request : nil)
  }
}

enum SharedCatalogHTTP {
  static func fetch(_ url: URL, provider: SharedCatalogLink.Provider) async throws
    -> SharedCatalogResolver.Response
  {
    guard SharedCatalogRedirects.allowed(url, provider: provider) else {
      throw SharedCatalogError.malformed
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForResource = 30
    let session = URLSession(
      configuration: configuration, delegate: SharedCatalogRedirects(provider), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Mozilla/5.0 NoteNarrate/1.0", forHTTPHeaderField: "User-Agent")
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      let final = response.url, SharedCatalogRedirects.allowed(final, provider: provider)
    else { throw SharedCatalogError.unavailable }
    guard response.expectedContentLength <= 8 * 1024 * 1024 else {
      throw SharedCatalogError.tooLarge
    }
    var data = Data()
    for try await byte in bytes {
      if data.count >= 8 * 1024 * 1024 { throw SharedCatalogError.tooLarge }
      data.append(byte)
    }
    try Task.checkCancellation()
    return .init(data: data, url: final)
  }
}

@MainActor public final class SharedCatalogImport: ObservableObject {
  public typealias Search = @Sendable (YouTubeSession?, String) async throws -> [DiscoveryItem]
  @Published public private(set) var collection: SharedCatalogCollection?
  @Published public private(set) var matches: [Int: DiscoveryItem] = [:]
  @Published public private(set) var candidates: [Int: [DiscoveryItem]] = [:]
  @Published public private(set) var failures: [Int: String] = [:]
  @Published public private(set) var busy = false
  @Published public private(set) var completed = 0
  @Published public private(set) var error: String?
  private let resolver: SharedCatalogResolver
  private let search: Search
  public init(
    resolver: SharedCatalogResolver = .init(),
    search: @escaping Search = {
      try await HomeDiscovery(session: $0).search(query: $1, filter: .songs)
    }
  ) {
    self.resolver = resolver
    self.search = search
  }
  public var orderedMatches: [DiscoveryItem] {
    guard let collection else { return [] }
    return collection.tracks.indices.compactMap { matches[$0] }
  }
  public func load(_ link: SharedCatalogLink) async {
    guard !busy else { return }
    busy = true
    error = nil
    collection = nil
    matches = [:]
    candidates = [:]
    failures = [:]
    completed = 0
    defer { busy = false }
    do { collection = try await resolver.resolve(link) } catch is CancellationError {} catch {
      self.error = error.localizedDescription
    }
  }
  public func resolve(session: YouTubeSession?) async {
    guard let collection, !busy else { return }
    busy = true
    error = nil
    completed = matches.count
    defer { busy = false }
    let pending = collection.tracks.indices.filter { matches[$0] == nil }
    let search = self.search
    // Three concurrent searches; source positions remain stable even when responses finish out of order.
    await withTaskGroup(of: (Int, [DiscoveryItem]?, String?).self) { group in
      var next = 0
      func schedule(_ index: Int) {
        let track = collection.tracks[index]
        group.addTask {
          do {
            try Task.checkCancellation()
            return (index, try await search(session, track.query), nil)
          } catch {
            return (index, nil, error is CancellationError ? nil : "Ricerca non riuscita. Riprova.")
          }
        }
      }
      while next < min(3, pending.count) {
        schedule(pending[next])
        next += 1
      }
      for await (index, items, failure) in group {
        guard !Task.isCancelled else {
          group.cancelAll()
          break
        }
        completed += 1
        if let items {
          candidates[index] = items.filter { $0.kind == .song }
          if let match = collection.tracks[index].match(items) {
            matches[index] = match
            failures[index] = nil
          } else {
            failures[index] = "Scegli la versione su YouTube Music"
          }
        } else {
          failures[index] = failure
        }
        if next < pending.count {
          schedule(pending[next])
          next += 1
        }
      }
    }
  }
  public func choose(_ item: DiscoveryItem, at index: Int) {
    guard !busy, collection?.tracks.indices.contains(index) == true,
      candidates[index]?.contains(item) == true, item.kind == .song
    else { return }
    matches[index] = item
    failures[index] = nil
  }
  public func searchCandidates(at index: Int, query: String, session: YouTubeSession?) async {
    guard !busy, collection?.tracks.indices.contains(index) == true,
      let query = SharedMusicTarget.queryText(query)
    else { return }
    busy = true
    defer { busy = false }
    do {
      let items = try await search(session, query)
      try Task.checkCancellation()
      candidates[index] = items.filter { $0.kind == .song }
      failures[index] =
        candidates[index]?.isEmpty == true ? "Nessun risultato. Modifica la ricerca." : nil
    } catch {
      if !Task.isCancelled { failures[index] = "Ricerca non riuscita. Riprova." }
    }
  }
  public func clearMatches() {
    guard !busy else { return }
    matches = [:]
    candidates = [:]
    failures = [:]
    completed = 0
  }
}

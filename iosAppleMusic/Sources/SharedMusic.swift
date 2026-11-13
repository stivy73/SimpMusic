// Adapted from iosPrototype/Sources/Core/SharedMusic.swift at 5a277798. SHA256 829b877ebfb6452d048e389717fd44998d33b13b1c7fa37633493761449fc3f9
// Reproduce with Scripts/import_youtube_collections.py.
import Foundation

/// Only a validated catalogue identifier or an explicit search query crosses the app boundary.
/// Never stores raw source URLs (which may contain tokens), cookies, keys or arbitrary attachments.
public enum SharedMusicTarget: Codable, Equatable, Sendable {
  case search(String)
  case video(String)
  case playlist(String)
  case catalog(SharedCatalogLink)
  public var label: String {
    switch self {
    case .search(let value): value
    case .video: "Brano YouTube condiviso"
    case .playlist: "Playlist YouTube condivisa"
    case .catalog(let link): "\(link.kind.title) · \(link.provider.title)"
    }
  }
  public var valid: Bool {
    switch self {
    case .search(let query): !query.isEmpty && query.count <= 300 && !query.contains("\n")
    case .video(let id): Self.matches(id, #"^[A-Za-z0-9_-]{11}$"#)
    case .playlist(let id): Self.matches(id, #"^[A-Za-z0-9_-]{10,180}$"#)
    case .catalog(let link): link.valid
    }
  }
  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }
  public static func parse(_ values: [String]) -> Self? {
    var seen = Set<String>()
    let text = values.prefix(8).map {
      String($0.prefix(4096)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    .filter { seen.insert($0).inserted }.joined(separator: "\n")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 16384 else { return nil }
    let detector = try? NSRegularExpression(
      pattern: #"https?://[^\s<>]+"#, options: .caseInsensitive)
    let range = NSRange(text.startIndex..., in: text)
    let urls =
      detector?.matches(in: text, range: range).compactMap { match -> URL? in
        guard let r = Range(match.range, in: text) else { return nil }
        return URL(
          string: String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)\"”")))
      } ?? []
    for url in urls {
      guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
        c.user == nil, c.password == nil, c.port == nil, let host = c.host?.lowercased()
      else { continue }
      if let link = SharedCatalogLink.parse(url) { return .catalog(link) }
      let yt = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be"]
      guard yt.contains(host) else { continue }
      let parts = c.path.split(separator: "/").map(String.init)
      let query = c.queryItems ?? []
      let videoID =
        host == "youtu.be" && parts.count == 1
        ? parts[0]
        : c.path == "/watch"
          ? query.first(where: { $0.name == "v" })?.value
          : parts.count == 2 && ["shorts", "live", "embed"].contains(parts[0]) ? parts[1] : nil
      if let videoID, Self.video(videoID).valid { return .video(videoID) }
      if c.path == "/playlist", let id = query.first(where: { $0.name == "list" })?.value,
        Self.playlist(id).valid
      {
        return .playlist(id)
      }
    }
    // Android's Now Playing/Ambient Music format: quoted title, or unquoted plus Google search URL.
    let google = urls.contains { url in
      ["google.com", "www.google.com"].contains(url.host?.lowercased() ?? "")
        && url.path == "/search"
    }
    let patterns =
      [#"^\s*["“„]([^"”]+)["”]\s+(?:di|by)\s+([^\n]+?)(?=\s+https?://|$|\n)"#]
      + (google ? [#"^\s*(.+?)\s+(?:di|by)\s+([^\n]+?)(?=\s+https?://|$|\n)"#] : [])
    for pattern in patterns {
      if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
        let match = re.firstMatch(in: text, range: range),
        let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text)
      {
        let candidate = queryText(String(text[a]) + " " + text[b])
        if let candidate { return .search(candidate) }
      }
    }
    let withoutLinks =
      detector?.stringByReplacingMatches(in: text, range: range, withTemplate: "") ?? text
    if let query = queryText(withoutLinks) { return .search(query) }
    return nil
  }
  public static func queryText(_ text: String) -> String? {
    let clean = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
      .joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,;\"“”"))
    guard !clean.isEmpty, clean.count <= 300,
      clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    return clean
  }
}

/// Persist only catalogue IDs and storefront, never tracking parameters or authentication data.
/// Short links retain only an allowlisted host and opaque path until the main app expands them.
public struct SharedCatalogLink: Codable, Hashable, Sendable {
  public enum Provider: String, Codable, Sendable {
    case appleMusic, spotify
    public var title: String { self == .appleMusic ? "Apple Music" : "Spotify" }
  }
  public enum Kind: String, Codable, Sendable {
    case track, album, playlist, shortLink
    public var title: String {
      switch self {
      case .track: "Brano"
      case .album: "Album"
      case .playlist: "Playlist"
      case .shortLink: "Link condiviso"
      }
    }
  }
  public let provider: Provider
  public let kind: Kind
  public let id: String
  public let country: String
  public init(provider: Provider, kind: Kind, id: String, country: String = "it") {
    self.provider = provider
    self.kind = kind
    self.id = id
    self.country = country
  }
  public var valid: Bool {
    func matches(_ value: String, _ pattern: String) -> Bool {
      value.range(of: pattern, options: .regularExpression) != nil
    }
    guard matches(country, "^[a-z]{2}$") else { return false }
    if kind == .shortLink {
      guard let url = URL(string: "https://" + id), Self.safe(url),
        Self.shortHosts(provider).contains(url.host ?? ""),
        matches(url.path, "^/[A-Za-z0-9_/-]{1,200}$"),
        !url.path.contains("//"), !url.path.contains(".."), url.query == nil, url.fragment == nil
      else { return false }
      return true
    }
    if provider == .spotify { return matches(id, "^[A-Za-z0-9]{22}$") }
    return matches(id, kind == .playlist ? "^pl\\.[A-Za-z0-9-]{10,100}$" : "^[0-9]{5,20}$")
  }
  public var url: URL {
    if kind == .shortLink { return URL(string: "https://" + id)! }
    if provider == .spotify {
      return URL(string: "https://open.spotify.com/\(kind.rawValue)/\(id)")!
    }
    let path = kind == .track ? "song" : kind.rawValue
    return URL(string: "https://music.apple.com/\(country)/\(path)/\(id)")!
  }
  public static func safe(_ url: URL) -> Bool {
    guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
    return c.scheme == "https" && c.user == nil && c.password == nil && c.port == nil
  }
  public static func shortHosts(_ provider: Provider) -> Set<String> {
    provider == .spotify ? ["spotify.link", "spotify.app.link"] : ["apple.co", "www.apple.co"]
  }
  public static func parse(_ url: URL) -> Self? {
    guard safe(url), let host = url.host?.lowercased(),
      let c = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    var parts = c.path.split(separator: "/").map(String.init)
    for provider in [Provider.appleMusic, .spotify] where shortHosts(provider).contains(host) {
      let link = Self(provider: provider, kind: .shortLink, id: host + c.path)
      return link.valid ? link : nil
    }
    if host == "open.spotify.com" {
      if parts.first?.range(of: "^intl-[a-z]{2}$", options: .regularExpression) != nil {
        parts.removeFirst()
      }
      if parts.first == "embed" { parts.removeFirst() }
      guard parts.count == 2, let kind = Kind(rawValue: parts[0]), kind != .shortLink else {
        return nil
      }
      let link = Self(provider: .spotify, kind: kind, id: parts[1])
      return link.valid ? link : nil
    }
    guard ["music.apple.com", "geo.music.apple.com", "itunes.apple.com"].contains(host),
      (3...4).contains(parts.count), let country = parts.first?.lowercased(),
      ["song", "album", "playlist"].contains(parts[1])
    else { return nil }
    var kind: Kind = parts[1] == "song" ? .track : parts[1] == "album" ? .album : .playlist
    var id = parts.last!.replacingOccurrences(of: "^id", with: "", options: .regularExpression)
    let song = (c.queryItems ?? []).filter { $0.name == "i" }
    if kind == .album, !song.isEmpty {
      guard song.count == 1, let value = song[0].value else { return nil }
      kind = .track
      id = value
    }
    let link = Self(provider: .appleMusic, kind: kind, id: id, country: country)
    return link.valid ? link : nil
  }
}

public struct SharedMusicRequest: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let date: Date
  public let target: SharedMusicTarget
  public init(target: SharedMusicTarget, date: Date = Date()) {
    self.id = UUID()
    self.date = date
    self.target = target
  }
}
public struct SharedMusicInbox: Sendable {
  public static let group = "group.com.stivy.notenarrate.applemusic"
  public let directory: URL
  public init(directory: URL) {
    self.directory = directory.appendingPathComponent("MusicShares", isDirectory: true)
  }
  public static func shared() -> Self? {
    #if os(iOS)
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group).map(Self.init)
    #else
      nil
    #endif
  }
  public func save(_ request: SharedMusicRequest) throws {
    guard request.target.valid else { throw CocoaError(.fileWriteInvalidFileName) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(request).write(to: file(request.id), options: .atomic)
    // Each request is a separate atomic file: app and extension cannot overwrite one another's queue.
    let entries = pending()
    for old in entries.dropLast(20) { try? remove(old.id) }
  }
  public func pending() -> [SharedMusicRequest] {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) ?? []
    return files.compactMap { url in
      guard url.pathExtension == "json",
        let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
        let attributes = try? url.resourceValues(forKeys: [
          .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ]),
        attributes.isRegularFile == true, attributes.isSymbolicLink != true,
        (attributes.fileSize ?? 8193) <= 8192,
        let data = try? Data(contentsOf: url), data.count <= 8192,
        let request = try? JSONDecoder().decode(SharedMusicRequest.self, from: data),
        request.id == id, request.target.valid
      else { return nil as SharedMusicRequest? }
      return request
    }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
  }
  public func remove(_ id: UUID) throws {
    let url = file(id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
  private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
}

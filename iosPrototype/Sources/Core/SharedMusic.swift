import Foundation

/// Only a validated catalogue identifier or an explicit search query crosses the app boundary.
/// Never stores the source URL (which may contain tokens), cookies, keys or arbitrary attachments.
public enum SharedMusicTarget: Codable, Equatable, Sendable {
  case search(String)
  case video(String)
  case playlist(String)
  public var label: String {
    switch self {
    case .search(let value): value
    case .video: "Brano YouTube condiviso"
    case .playlist: "Playlist YouTube condivisa"
    }
  }
  public var valid: Bool {
    switch self {
    case .search(let query): !query.isEmpty && query.count <= 300 && !query.contains("\n")
    case .video(let id): Self.matches(id, #"^[A-Za-z0-9_-]{11}$"#)
    case .playlist(let id): Self.matches(id, #"^[A-Za-z0-9_-]{10,180}$"#)
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
  public static let group = "group.com.stivy.simpmusic.prototype"
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

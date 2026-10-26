import Foundation

/// Public display data only. Cookies, API keys and signed media URLs never enter the widget container.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public static let group = "group.com.stivy.simpmusic.prototype"
  public struct Track: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var artworkFile: String?
    public var duration: Double
    public var elapsed: Double
    public var playing: Bool
    public init(
      id: String, title: String, artist: String, duration: Double, elapsed: Double, playing: Bool,
      artworkFile: String? = nil
    ) {
      self.id = id
      self.title = title
      self.artist = artist
      self.duration = duration.isFinite ? max(0, duration) : 0
      self.elapsed = elapsed.isFinite ? max(0, min(elapsed, self.duration)) : 0
      self.playing = playing
      self.artworkFile = artworkFile
    }
  }
  public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var artworkFile: String?
    public init(id: String, title: String, subtitle: String, artworkFile: String? = nil) {
      self.id = id
      self.title = title
      self.subtitle = subtitle
      self.artworkFile = artworkFile
    }
  }
  public var date: Date
  public var track: Track?
  public var playlists: [Playlist]
  public var todaySeconds: Double
  public var weekSeconds: Double
  public var weekPlays: Int
  public var topArtist: String?
  public init(
    date: Date = Date(), track: Track? = nil, playlists: [Playlist] = [], todaySeconds: Double = 0,
    weekSeconds: Double = 0, weekPlays: Int = 0, topArtist: String? = nil
  ) {
    self.date = date
    self.track = track
    self.playlists = Array(playlists.prefix(24))
    self.todaySeconds = todaySeconds
    self.weekSeconds = weekSeconds
    self.weekPlays = weekPlays
    self.topArtist = topArtist
  }
  public static func directory() -> URL? {
    #if os(iOS)
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    #else
      nil
    #endif
  }
  public static func read(at directory: URL? = directory()) -> Self {
    guard let directory,
      let data = try? Data(contentsOf: directory.appendingPathComponent("widgets.json")),
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return Self() }
    return value
  }
  public func write(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(
      to: directory.appendingPathComponent("widgets.json"), options: .atomic)
  }
  public static func artworkURL(_ name: String?, directory: URL? = directory()) -> URL? {
    guard let name, name == URL(fileURLWithPath: name).lastPathComponent,
      name.hasPrefix("art-"), name.hasSuffix(".jpg")
    else { return nil }
    return directory?.appendingPathComponent(name)
  }
}

public enum AppRoute: Equatable, Identifiable, Sendable {
  case player, statistics, library, received
  case playlist(String)
  case album(String)
  public var id: String { url.absoluteString }
  public var url: URL {
    var value = URLComponents()
    value.scheme = "notenarrate"
    switch self {
    case .player: value.host = "player"
    case .statistics: value.host = "statistics"
    case .library: value.host = "library"
    case .received: value.host = "received"
    case .playlist(let id):
      value.host = "playlist"
      value.queryItems = [URLQueryItem(name: "id", value: id)]
    case .album(let id):
      value.host = "album"
      value.queryItems = [URLQueryItem(name: "id", value: id)]
    }
    return value.url!
  }
  public init?(url: URL) {
    guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false),
      value.scheme == "notenarrate", value.user == nil, value.password == nil,
      value.port == nil, value.path.isEmpty, value.fragment == nil
    else { return nil }
    let ids = (value.queryItems ?? []).filter { $0.name == "id" }
    switch value.host {
    case "player" where value.queryItems == nil: self = .player
    case "statistics" where value.queryItems == nil: self = .statistics
    case "library" where value.queryItems == nil: self = .library
    case "received" where value.queryItems == nil: self = .received
    case "playlist", "album":
      guard ids.count == 1, value.queryItems?.count == 1, let id = ids.first?.value,
        id.range(of: #"^[A-Za-z0-9_-]{2,180}$"#, options: .regularExpression) != nil
      else { return nil }
      self = value.host == "playlist" ? .playlist(id) : .album(id)
    default: return nil
    }
  }
}

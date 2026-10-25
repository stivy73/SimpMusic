import Foundation

/// Window over the complete library. Navigation buttons do not consume album slots.
public struct CarPlayPage: Equatable, Sendable {
  public let range: Range<Int>
  public let previous: Int?
  public let next: Int?
  public init(count: Int, offset: Int, capacity: Int) {
    let count = max(0, count)
    let size = max(1, capacity)
    let last = count == 0 ? 0 : ((count - 1) / size) * size
    let start = min(last, max(0, offset) / size * size)
    let end = min(count, start + size)
    range = start..<end
    previous = start > 0 ? max(0, start - size) : nil
    next = end < count ? end : nil
  }
}

public enum ArtworkSource {
  public static func candidates(primary: URL?, videoID: String? = nil) -> [URL] {
    var urls: [URL] = []
    if let primary, primary.scheme == "https", primary.host != nil { urls.append(primary) }
    if let id = videoID, id.count == 11,
      id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
      let url = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"), !urls.contains(url)
    {
      urls.append(url)
    }
    return urls
  }
}

/// Album rows omit per-track artists; retain the selected album's real metadata.
public enum AlbumTrackMetadata {
  public static func artist(from subtitle: String?) -> String? {
    guard let subtitle else { return nil }
    let parts = subtitle.components(separatedBy: CharacterSet(charactersIn: "•·"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { value in
        guard !value.isEmpty, !["album", "single", "ep"].contains(value.lowercased()) else {
          return false
        }
        return !(value.count == 4 && Int(value).map { (1800...2200).contains($0) } == true)
      }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

/// Voice queries are separate from phone searches and survive a CarPlay scene reconnect.
public struct CarPlayVoiceQuery: Equatable, Sendable {
  public let id = UUID()
  public let query: String
  public let filter: MusicSearchFilter
  public init(query: String, filter: MusicSearchFilter) {
    self.query = query
    self.filter = filter
  }
}

public struct VoiceMediaIdentifier: Equatable, Sendable {
  public let kind: DiscoveryItem.Kind
  public let mediaID: String
  public init(kind: DiscoveryItem.Kind, mediaID: String) {
    self.kind = kind
    self.mediaID = mediaID
  }
  public init?(encoded: String) {
    let parts = encoded.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let kind = DiscoveryItem.Kind(rawValue: String(parts[0])) else {
      return nil
    }
    self.kind = kind
    mediaID = String(parts[1])
  }
  public var encoded: String { kind.rawValue + ":" + mediaID }
}

public enum PlaybackRepeatMode: String, CaseIterable, Sendable {
  case off, all, one
  public var title: String {
    switch self {
    case .off: "Ripetizione disattivata"
    case .all: "Ripeti coda"
    case .one: "Ripeti brano"
    }
  }
  public var next: Self {
    switch self {
    case .off: .all
    case .all: .one
    case .one: .off
    }
  }
}

/// Indices preserve duplicate playlist occurrences; shuffle never drops or repeats an index.
public struct PlaybackSequence: Equatable, Sendable {
  public private(set) var order: [Int] = []
  public private(set) var current: Int?
  public private(set) var shuffled = false
  public init() {}
  public mutating func reset(count: Int, selected: Int, shuffle: Bool) {
    order = Array(0..<max(0, count))
    current = order.contains(selected) ? selected : nil
    shuffled = false
    if shuffle { setShuffled(true) }
  }
  public mutating func select(_ index: Int) { if order.contains(index) { current = index } }
  public mutating func setShuffled(_ value: Bool) {
    guard value != shuffled else { return }
    shuffled = value
    if value, let current {
      order = [current] + order.filter { $0 != current }.shuffled()
    } else {
      order.sort()
    }
  }
  public func next(repeatMode: PlaybackRepeatMode, automatic: Bool = false) -> Int? {
    guard let current, let offset = order.firstIndex(of: current) else { return nil }
    if automatic && repeatMode == .one { return current }
    if offset + 1 < order.count { return order[offset + 1] }
    return repeatMode == .all ? order.first : nil
  }
  public func previous(repeatMode: PlaybackRepeatMode) -> Int? {
    guard let current, let offset = order.firstIndex(of: current) else { return nil }
    if offset > 0 { return order[offset - 1] }
    return repeatMode == .all ? order.last : nil
  }
}

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

public enum PlaybackRepeatMode: String, CaseIterable, Sendable, Codable {
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
public struct PlaybackSequence: Equatable, Sendable, Codable {
  public private(set) var order: [Int] = []
  private var naturalOrder: [Int] = []
  public private(set) var current: Int?
  public private(set) var shuffled = false
  public init() {}
  public mutating func reset(count: Int, selected: Int, shuffle: Bool) {
    order = Array(0..<max(0, count))
    naturalOrder = order
    current = order.contains(selected) ? selected : nil
    shuffled = false
    if shuffle { setShuffled(true) }
  }
  public func isValid(count: Int) -> Bool {
    let expected = Set(0..<max(0, count))
    return count >= 0 && order.count == count && naturalOrder.count == count
      && Set(order) == expected && Set(naturalOrder) == expected
      && (count == 0 ? current == nil : current.map { expected.contains($0) } == true)
  }

  public mutating func select(_ index: Int) { if order.contains(index) { current = index } }
  public mutating func setShuffled(_ value: Bool) {
    guard value != shuffled else { return }
    shuffled = value
    if value, let current {
      order = [current] + order.filter { $0 != current }.shuffled()
    } else {
      order = naturalOrder
    }
  }

  /// New occurrences are appended to storage, without reshuffling existing playback history.
  @discardableResult
  public mutating func append(playNext: Bool = false) -> Int {
    let index = naturalOrder.count
    Self.insert(index, into: &naturalOrder, after: playNext ? current : nil)
    Self.insert(index, into: &order, after: playNext ? current : nil)
    if current == nil { current = index }
    return index
  }

  /// A manual drag establishes the new canonical order, including while shuffle is enabled.
  @discardableResult
  public mutating func move(from offsets: IndexSet, to destination: Int) -> Bool {
    guard !offsets.isEmpty, offsets.allSatisfy({ order.indices.contains($0) }),
      (0...order.count).contains(destination)
    else { return false }
    let selected = offsets.map { order[$0] }
    var result = order.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    let adjusted = destination - offsets.filter { $0 < destination }.count
    result.insert(contentsOf: selected, at: adjusted)
    order = result
    naturalOrder = result
    return true
  }

  public mutating func playNext(_ index: Int) {
    guard order.contains(index), index != current else { return }
    naturalOrder.removeAll { $0 == index }
    order.removeAll { $0 == index }
    Self.insert(index, into: &naturalOrder, after: current)
    Self.insert(index, into: &order, after: current)
  }

  /// Returns removed storage indices. Survivors are remapped to the compacted song array.
  @discardableResult
  public mutating func remove(_ indices: Set<Int>) -> Set<Int> {
    let removed = indices.intersection(order)
    guard !removed.isEmpty else { return [] }
    let survivors = (0..<naturalOrder.count).filter { !removed.contains($0) }
    let mapping = Dictionary(
      uniqueKeysWithValues: survivors.enumerated().map { ($0.element, $0.offset) })
    var selected = current
    if let current, removed.contains(current), let offset = order.firstIndex(of: current) {
      selected =
        order.dropFirst(offset + 1).first { !removed.contains($0) }
        ?? order.prefix(offset).last { !removed.contains($0) }
    }
    order = order.compactMap { mapping[$0] }
    naturalOrder = naturalOrder.compactMap { mapping[$0] }
    current = selected.flatMap { mapping[$0] }
    return removed
  }

  private static func insert(_ value: Int, into values: inout [Int], after index: Int?) {
    if let index, let offset = values.firstIndex(of: index) {
      values.insert(value, at: offset + 1)
    } else {
      values.append(value)
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

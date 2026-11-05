import Foundation

/// Bounded companion messages. No account cookies, API keys or signed media URLs.
public struct WatchSnapshot: Codable, Sendable, Equatable {
  public struct Track: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public init(id: String, title: String, artist: String) {
      self.id = id
      self.title = String(title.prefix(180))
      self.artist = String(artist.prefix(180))
    }
  }
  public var version = 1
  public var date = Date()
  public var track: Track?
  public var playing = false
  public var loading = false
  public var narrating = false
  public var preparingMeaning = false
  public var elapsed = 0.0
  public var duration = 0.0
  public var meaning = ""
  public var progress = ""
  public var artwork: Data?
  public var queue: [Track] = []
  public var queueTotal = 0
  public init() {}
  public static func queueRange(count: Int, currentOffset: Int) -> Range<Int> {
    let count = max(0, count)
    let offset = min(max(0, currentOffset), max(0, count - 1))
    let start = max(0, min(offset - 5, count - 40))
    return start..<min(count, start + 40)
  }
  public func encoded() throws -> Data {
    var safe = self
    safe.queueTotal = max(queueTotal, queue.count)
    safe.queue = Array(queue.prefix(40))
    safe.meaning = String(meaning.prefix(6000))
    safe.progress = String(progress.prefix(200))
    if let artwork, artwork.count > 16_000 { safe.artwork = nil }
    safe.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
    safe.duration = duration.isFinite ? max(0, duration) : 0
    var data = try JSONEncoder().encode(safe)
    if data.count > 60_000 {
      safe.artwork = nil
      data = try JSONEncoder().encode(safe)
    }
    while data.count > 60_000, !safe.queue.isEmpty {
      safe.queue.removeLast()
      data = try JSONEncoder().encode(safe)
    }
    guard data.count <= 60_000 else { throw WatchCommandError.malformed }
    return data
  }
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 60_000 else { throw WatchCommandError.malformed }
    let result = try JSONDecoder().decode(Self.self, from: data)
    guard result.version == 1, result.queue.count <= 40,
      result.elapsed.isFinite, result.duration.isFinite,
      result.elapsed >= 0, result.duration >= 0
    else { throw WatchCommandError.malformed }
    return result
  }
}

public enum WatchCommandError: Error, LocalizedError {
  case malformed, stale, noTrack
  public var errorDescription: String? {
    switch self {
    case .malformed: "Aggiorna NoteNarrate su entrambi i dispositivi."
    case .stale: "Il brano è cambiato. Aggiorna il player e riprova."
    case .noTrack: "Seleziona prima un brano su iPhone."
    }
  }
}
public struct WatchCommand: Codable, Sendable {
  public enum Action: String, Codable, Sendable {
    case refresh, play, pause, previous, next, explain, stopExplanation, radio, playOccurrence
  }
  public var version = 1
  public var id = UUID()
  public var date = Date()
  public let action: Action
  public let expectedTrackID: String?
  public let occurrenceID: String?
  public init(action: Action, expectedTrackID: String?, occurrenceID: String? = nil) {
    self.action = action
    self.expectedTrackID = expectedTrackID
    self.occurrenceID = occurrenceID
  }
  public func validate(against snapshot: WatchSnapshot, now: Date = Date()) throws {
    guard version == 1, abs(date.timeIntervalSince(now)) <= 120 else {
      throw WatchCommandError.stale
    }
    if action == .refresh { return }
    guard snapshot.track != nil else { throw WatchCommandError.noTrack }
    guard expectedTrackID == snapshot.track?.id else { throw WatchCommandError.stale }
    if action == .playOccurrence {
      guard let occurrenceID, UUID(uuidString: occurrenceID) != nil,
        snapshot.queue.contains(where: { $0.id == occurrenceID })
      else { throw WatchCommandError.stale }
    }
  }
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 2048 else { throw WatchCommandError.malformed }
    return try JSONDecoder().decode(Self.self, from: data)
  }
}

import Foundation

public enum SleepTimer: Codable, Equatable, Sendable {
  case deadline(Date)
  case endOfTrack
  public static func minutes(_ count: Int, now: Date = Date()) -> Self {
    .deadline(now.addingTimeInterval(Double(max(1, min(count, 720))) * 60))
  }
  public func expired(now: Date = Date(), trackEnded: Bool = false) -> Bool {
    switch self {
    case .deadline(let end): now >= end
    case .endOfTrack: trackEnded
    }
  }
  public var title: String {
    switch self {
    case .endOfTrack: return "Alla fine del brano"
    case .deadline(let end):
      let seconds = max(0, Int(end.timeIntervalSinceNow))
      return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
  }
}

public struct PlaybackSnapshot: Codable, Sendable {
  public var version = 1
  public let tracks: [PlaybackTrack]
  public let occurrenceIDs: [UUID]
  public let sequence: PlaybackSequence
  public let repeatMode: PlaybackRepeatMode
  public let position: Double
  public let duration: Double
  public let timer: SleepTimer?
  public let saved: Date
  public init(
    tracks: [PlaybackTrack], occurrenceIDs: [UUID], sequence: PlaybackSequence,
    repeatMode: PlaybackRepeatMode, position: Double, duration: Double,
    timer: SleepTimer? = nil, saved: Date = Date()
  ) {
    self.tracks = tracks
    self.occurrenceIDs = occurrenceIDs
    self.sequence = sequence
    self.repeatMode = repeatMode
    self.position = position
    self.duration = duration
    self.timer = timer
    self.saved = saved
  }
  public var valid: Bool {
    version == 1 && tracks.count <= 5000 && tracks.count == occurrenceIDs.count
      && Set(occurrenceIDs).count == tracks.count && sequence.isValid(count: tracks.count)
      && position.isFinite && position >= 0 && duration.isFinite && duration >= 0
      && (duration == 0 || position <= duration + 1)
      && tracks.allSatisfy {
        !$0.id.isEmpty && $0.id.count <= 256
          && ($0.durationSeconds.map { $0.isFinite && $0 >= 0 } ?? true)
      }
  }
}

public struct PlaybackSessionStore: Sendable {
  public let url: URL
  public init(url: URL = LocalFiles.directory("Playback").appendingPathComponent("session.json")) {
    self.url = url
  }
  public func load() -> PlaybackSnapshot? {
    guard let snapshot = LocalFiles.read(PlaybackSnapshot.self, from: url), snapshot.valid else {
      return nil
    }
    return snapshot
  }
  public func save(_ snapshot: PlaybackSnapshot) throws {
    guard snapshot.valid else { throw OfflineError.incomplete }
    try LocalFiles.write(snapshot, to: url)
  }
}

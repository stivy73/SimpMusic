import Foundation
import AVFoundation

/// Music ends with its audio timeline, not a padded container or a stale video duration.
public struct AudioPlaybackTiming: Equatable, Sendable {
  public let source: Double
  public let container: Double
  public let audioEnd: Double
  public let duration: Double
  public init(source: Double, container: Double, audioEnd: Double) {
    self.source = Self.valid(source) ?? 0
    self.container = Self.valid(container) ?? 0
    self.audioEnd = Self.valid(audioEnd) ?? 0
    var end = Self.valid(audioEnd) ?? Self.valid(container) ?? Self.valid(source) ?? 0
    // Player metadata refers to this exact video ID. Allow frame/second rounding,
    // but do not play minutes beyond its declared length when a container is padded.
    if self.source > 0, end > self.source + max(2, self.source * 0.01) {
      end = self.source + 0.25
    }
    duration = end
  }
  private static func valid(_ value: Double) -> Double? {
    value.isFinite && value > 0 ? value : nil
  }
  public static func resolve(_ asset: AVAsset, source: Double = 0) async throws -> Self {
    let container = try await asset.load(.duration).seconds
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw AudioPlaybackError.unavailable
    }
    let range = try await track.load(.timeRange)
    let segments = try? await track.load(.segments)
    let ends = (segments ?? []).filter { !$0.isEmpty }
      .map { $0.timeMapping.target.end.seconds }.filter { $0.isFinite && $0 > 0 }
    return Self(source: source, container: container, audioEnd: ends.max() ?? range.end.seconds)
  }
  public var diagnostic: String {
    "sorgente \(Int(source)) s, contenitore \(Int(container)) s, audio \(Int(audioEnd)) s, fine \(Int(duration)) s"
  }
}

/// Now Playing extrapolates linear progress itself. Publish only discontinuities
/// or metadata changes, instead of restarting CarPlay's clock every half second.
public struct NowPlayingPublication: Sendable {
  private var key: String?
  private var duration = 0.0
  private var position = 0.0
  private var rate = 0.0
  private var at = 0.0
  public init() {}
  public mutating func reset() { key = nil }
  public mutating func shouldPublish(
    key: String, duration: Double, position: Double, rate: Double, live: Bool, now: Double
  ) -> Bool {
    let position = position.isFinite ? max(0, position) : 0
    let duration = duration.isFinite ? max(0, duration) : 0
    let predicted = self.position + max(0, now - at) * self.rate
    guard self.key != key || self.duration != duration || self.rate != rate
      || (!live && abs(predicted - position) > 1) || now < at else { return false }
    self.key = key
    self.duration = duration
    self.position = position
    self.rate = rate
    self.at = now
    return true
  }
}

/// A retry budget belongs to a queue occurrence, not to an AVPlayerItem. Replacing
/// the item must not reset it or an unavailable CDN can cause an endless loop.
public struct AudioRecovery: Sendable {
  public private(set) var attempts = 0
  private var lastPosition: Double?
  private var progressAt: TimeInterval?
  public init() {}

  public mutating func begin() -> Bool {
    guard attempts < 2 else { return false }
    attempts += 1
    resetStall()
    return true
  }

  public mutating func resetStall() {
    lastPosition = nil
    progressAt = nil
  }

  /// Uses an independent monotonic clock: AVPlayer time callbacks can stop when
  /// the download stalls. Pause, narration and preparation never count as stalls.
  public mutating func observe(
    position: Double, now: TimeInterval, shouldPlay: Bool, ready: Bool, duration: Double
  ) -> Bool {
    guard shouldPlay, ready, position.isFinite, position >= 0, now.isFinite,
      !(duration.isFinite && duration > 0 && position >= duration - 0.5)
    else {
      resetStall()
      return false
    }
    guard let previous = lastPosition, let progressAt else {
      lastPosition = position
      self.progressAt = now
      return false
    }
    if position < previous || position - previous >= 0.2 || now < progressAt {
      lastPosition = position
      self.progressAt = now
      return false
    }
    return now - progressAt >= 8
  }
}

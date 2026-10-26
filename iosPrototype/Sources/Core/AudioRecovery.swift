import Foundation

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

import Foundation

/// Relative phone-volume changes must not jump to the phone's absolute level.
/// Keep the latest requested receiver level while its asynchronous reply arrives.
public struct CastVolumeControl: Sendable {
  public private(set) var receiverVolume = 0.0
  public private(set) var phoneVolume: Double?
  private var pendingUntil: TimeInterval?

  public init() {}

  public var phoneAtLimit: Bool {
    guard let phoneVolume else { return false }
    return phoneVolume <= 0 || phoneVolume >= 1
  }

  public mutating func begin(phone: Double, receiver: Double) {
    end()
    guard phone.isFinite, receiver.isFinite else { return }
    phoneVolume = Self.bounded(phone)
    receiverVolume = Self.bounded(receiver)
  }

  public mutating func end() {
    phoneVolume = nil
    pendingUntil = nil
  }

  public mutating func phoneChanged(to value: Double, now: TimeInterval) -> Double? {
    guard value.isFinite, let previous = phoneVolume else { return nil }
    let value = Self.bounded(value)
    phoneVolume = value
    let delta = value - previous
    guard abs(delta) > 0.0001 else { return nil }
    // A route change/coalesced notification must not cause a large volume jump.
    let next = Self.bounded(receiverVolume + min(0.0625, max(-0.0625, delta)))
    guard abs(next - receiverVolume) > 0.0001 else { return nil }
    return request(next, now: now)
  }

  @discardableResult
  public mutating func request(_ value: Double, now: TimeInterval) -> Double? {
    guard value.isFinite, phoneVolume != nil else { return nil }
    receiverVolume = Self.bounded(value)
    pendingUntil = now + 2
    return receiverVolume
  }

  public mutating func receive(_ value: Double, now: TimeInterval) {
    guard value.isFinite, phoneVolume != nil else { return }
    let value = Self.bounded(value)
    if let pendingUntil, now < pendingUntil, abs(value - receiverVolume) > 0.001 { return }
    receiverVolume = value
    pendingUntil = nil
  }

  private static func bounded(_ value: Double) -> Double { min(1, max(0, value)) }
}

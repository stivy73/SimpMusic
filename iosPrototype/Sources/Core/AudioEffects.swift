import Foundation

public struct AudioEffects: Codable, Equatable, Sendable {
  public static let frequencies = (0..<10).map { 31.25 * pow(2, Double($0)) }
  public var enabled = false
  public var gains = [Double](repeating: 0, count: 10)
  public var preamp = 0.0
  public var delay = 0.0
  public var reverb = 0.0
  public var delaySeconds = 0.22
  public var profile = "Personalizzato"
  public init() {}
  public var valid: Bool {
    gains.count == 10 && gains.allSatisfy { $0.isFinite && (-12...12).contains($0) }
      && preamp.isFinite && (-30...0).contains(preamp)
      && delay.isFinite && (0...0.6).contains(delay)
      && reverb.isFinite && (0...0.6).contains(reverb)
      && delaySeconds.isFinite && (0.05...0.8).contains(delaySeconds)
  }
  public static let presets: [(String, [Double])] = [
    ("Piatto", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), ("Bassi", [5, 4, 3, 1, 0, 0, 0, 0, 0, 0]),
    ("Voce", [-3, -2, -1, 0, 2, 3, 4, 2, 0, -1]), ("Rock", [4, 3, 1, -1, -2, 0, 2, 3, 4, 3]),
    ("Jazz", [3, 2, 0, 1, -1, -1, 0, 2, 3, 4]),
  ]
  /// AutoEq ten-band FixedBandEQ format, identical centres/Q used by the Android fork.
  /// Reject partial or parametric/shelf profiles instead of silently applying a different curve.
  public static func autoEq(_ text: String) throws -> Self {
    let regex = try NSRegularExpression(
      pattern:
        #"(?im)^Filter\s+\d+:\s*ON\s+PK\s+Fc\s+([0-9.]+)\s+Hz\s+Gain\s+(-?[0-9.]+)\s+dB\s+Q\s+([0-9.]+)\s*$"#
    )
    let source = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
    guard matches.count == 10 else { throw OfflineError.incomplete }
    var result = Self()
    result.enabled = true
    for (index, centre) in frequencies.enumerated() {
      let candidates = matches.filter { match in
        guard let hz = Double(source.substring(with: match.range(at: 1))),
          let q = Double(source.substring(with: match.range(at: 3)))
        else { return false }
        return abs(hz - centre) <= centre * 0.05 && abs(q - sqrt(2)) < 0.02
      }
      guard candidates.count == 1,
        let gain = Double(source.substring(with: candidates[0].range(at: 2)))
      else { throw OfflineError.incomplete }
      result.gains[index] = gain
    }
    let preamp = try NSRegularExpression(pattern: #"(?im)^Preamp:\s*(-?[0-9.]+)\s*dB\s*$"#)
    if let match = preamp.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
      let value = Double(source.substring(with: match.range(at: 1)))
    {
      result.preamp = value
    }
    result.profile = "AutoEq importato"
    guard result.valid else { throw OfflineError.incomplete }
    return result
  }
}

/// Stateful PCM processing: RBJ peaking biquads, feedback delay and four parallel comb reverbs.
/// Allocated outside render callbacks; one instance per audio stream, no shared channel history.
public final class EffectsDSP {
  private struct Biquad {
    let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var z1 = 0.0, z2 = 0.0
    init(hz: Double, gain: Double, rate: Double) {
      let w = 2 * Double.pi * min(hz, rate * 0.45) / rate
      let alpha = sin(w) / (2 * sqrt(2.0))
      let a = pow(10, gain / 40)
      let norm = 1 + alpha / a
      b0 = (1 + alpha * a) / norm
      b1 = -2 * cos(w) / norm
      b2 = (1 - alpha * a) / norm
      a1 = -2 * cos(w) / norm
      a2 = (1 - alpha / a) / norm
    }
    mutating func sample(_ x: Double) -> Double {
      let y = b0 * x + z1
      z1 = b1 * x - a1 * y + z2
      z2 = b2 * x - a2 * y
      return y
    }
  }
  private let settings: AudioEffects
  private let channels: Int
  private let gain: Double
  private var filters: [[Biquad]]
  private var delays: [[Double]]
  private var reverbs: [[[Double]]]
  private var cursor = [Int]()
  private var reverbCursor = [[Int]]()
  public init(settings: AudioEffects, rate: Double, channels: Int) {
    let rate = rate.isFinite && (8000...192000).contains(rate) ? rate : 44100
    let configuration = settings.valid ? settings : AudioEffects()
    self.settings = configuration
    self.channels = max(1, min(channels, 8))
    gain = pow(10, min(configuration.preamp, -(configuration.gains.max() ?? 0)) / 20)
    filters = (0..<self.channels).map { _ in
      zip(AudioEffects.frequencies, configuration.gains).map {
        Biquad(hz: $0.0, gain: $0.1, rate: rate)
      }
    }
    delays = (0..<self.channels).map { _ in
      [Double](repeating: 0, count: max(1, Int(rate * configuration.delaySeconds)))
    }
    reverbs = (0..<self.channels).map { channel in
      [0.0297, 0.0371, 0.0411, 0.0437].map {
        [Double](repeating: 0, count: max(1, Int(rate * ($0 + Double(channel) * 0.001))))
      }
    }
    cursor = [Int](repeating: 0, count: self.channels)
    reverbCursor = (0..<self.channels).map { _ in [Int](repeating: 0, count: 4) }
  }
  public func process(_ sample: Float, channel: Int) -> Float {
    guard settings.enabled, channel < channels, channel >= 0 else {
      return sample.isFinite ? sample : 0
    }
    var value = Double(sample.isFinite ? sample : 0) * gain
    for i in filters[channel].indices { value = filters[channel][i].sample(value) }
    if settings.delay > 0 {
      let old = delays[channel][cursor[channel]]
      delays[channel][cursor[channel]] = value + old * 0.35
      cursor[channel] = (cursor[channel] + 1) % delays[channel].count
      value += old * settings.delay
    }
    if settings.reverb > 0 {
      var wet = 0.0
      for i in 0..<4 {
        let index = reverbCursor[channel][i]
        let old = reverbs[channel][i][index]
        reverbs[channel][i][index] = value + old * 0.68
        reverbCursor[channel][i] = (index + 1) % reverbs[channel][i].count
        wet += old * 0.25
      }
      value += wet * settings.reverb
    }
    return Float(value.isFinite ? max(-1, min(1, value)) : 0)
  }
}

public enum CrossfadeCurve {
  public static func gains(progress: Double, dj: Bool) -> (outgoing: Double, incoming: Double) {
    let x = max(0, min(1, progress.isFinite ? progress : 0))
    // DJ mode steepens the centre of the equal-power fade, without claiming beat matching.
    let t = dj ? x * x * (3 - 2 * x) : x
    return (cos(t * .pi / 2), sin(t * .pi / 2))
  }
}

/// One-pole DJ sweep, separate histories per channel; coefficient changes preserve continuity.
public final class DJSweep {
  private var low = [Double](repeating: 0, count: 8)
  private var alpha = 1.0
  private var highPass = false
  private var active = false
  public init() {}
  public func configure(progress: Double?, incoming: Bool, rate: Double) {
    guard let progress else {
      active = false
      low = [Double](repeating: 0, count: 8)
      return
    }
    active = true
    highPass = incoming
    let t = min(1, max(0, progress))
    let frequency = incoming ? 8000 * pow(20 / 8000, t) : 18000 * pow(200 / 18000, t)
    alpha = 1 - exp(-2 * .pi * min(frequency, rate * 0.45) / rate)
  }
  public func process(_ sample: Float, channel: Int) -> Float {
    guard active, (0..<8).contains(channel) else { return sample }
    low[channel] += alpha * (Double(sample) - low[channel])
    return Float(highPass ? Double(sample) - low[channel] : low[channel])
  }
}

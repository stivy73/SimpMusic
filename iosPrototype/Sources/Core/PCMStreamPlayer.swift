import AVFoundation
import Foundation

/// Kept alive by MusicModel, independent of sheet lifetime or device rotation.
@MainActor
public final class PCMStreamPlayer {
  private let engine = AVAudioEngine()
  private let node = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
  private var pendingFrames = 0
  private var cancelled = false
  private var started = false
  private var playbackFailure: Error?
  private var lastPlaybackProgress = ContinuousClock.now
  private var observer: AudioConfigurationObservation?
  private let gain: Float

  public init(gain: Float = 1) {
    self.gain = gain.isFinite ? min(2, max(0, gain)) : 1
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    observer = AudioConfigurationObservation(
      NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          // Initial route negotiation can notify while the new engine is still being prepared.
          // A notification alone is not a failure if audio is actually running.
          if let self, self.started, !self.engine.isRunning {
            self.playbackFailure = SpeechStreamError.playbackStopped
          }
        }
      })
  }

  private func check() throws {
    try Task.checkCancellation()
    if cancelled { throw CancellationError() }
    if let playbackFailure { throw playbackFailure }
    if pendingFrames > 0 && lastPlaybackProgress.duration(to: .now) > .seconds(15) {
      throw SpeechStreamError.playbackStopped
    }
  }

  /// Queue at most six seconds. Split large network chunks into half-second buffers.
  public func enqueue(_ pcm: Data, onStart: @MainActor () -> Void) async throws {
    guard !pcm.isEmpty, pcm.count.isMultiple(of: 2) else { throw PrototypeError.invalidResponse }
    let bytes = [UInt8](pcm)
    var offset = 0
    while offset < bytes.count {
      try check()
      while pendingFrames >= 144_000 {
        try await Task.sleep(for: .milliseconds(20))
        try check()
        guard engine.isRunning else { throw PrototypeError.invalidResponse }
      }
      let count = min(24_000, bytes.count - offset)
      let frames = count / 2
      guard
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
        let samples = buffer.floatChannelData?[0]
      else { throw PrototypeError.invalidResponse }
      buffer.frameLength = AVAudioFrameCount(frames)
      for index in 0..<frames {
        let low = UInt16(bytes[offset + index * 2])
        let high = UInt16(bytes[offset + index * 2 + 1]) << 8
        samples[index] = NarrationLevel.sample(Float(Int16(bitPattern: low | high)) / 32768,
          gain: gain)
      }
      if !started {
        try engine.start()
      }
      if pendingFrames == 0 { lastPlaybackProgress = .now }
      pendingFrames += frames
      // dataConsumed fires too early: only dataPlayedBack proves the tail was heard.
      node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, !self.cancelled else { return }
          self.pendingFrames -= frames
          self.lastPlaybackProgress = .now
        }
      }
      if !started {
        // Route activation is asynchronous, especially on wireless CarPlay.
        // Don't invoke the legacy throwing Objective-C path before hardware renders.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while engine.outputNode.lastRenderTime?.isHostTimeValid != true {
          try check()
          guard ContinuousClock.now < deadline, engine.isRunning else {
            throw SpeechStreamError.playbackStopped
          }
          try await Task.sleep(for: .milliseconds(20))
        }
        if #available(iOS 27.0, macOS 27.0, *) {
          try node.playAudio()
        } else {
          node.play()
        }
        started = true
        onStart()
      }
      offset += count
    }
  }

  public func finish() async throws {
    try check()
    guard started else { throw PrototypeError.invalidResponse }
    while pendingFrames > 0 {
      try await Task.sleep(for: .milliseconds(20))
      try check()
      guard engine.isRunning else { throw PrototypeError.invalidResponse }
    }
    stop()
  }

  public func stop() {
    cancelled = true
    node.stop()
    engine.stop()
    pendingFrames = 0
    observer = nil
  }
}

/// Gain applies at playback, so old cached PCM receives the same narration level.
public enum NarrationLevel {
  public static let gain: Float = 1.3
  public static func sample(_ value: Float, gain: Float = gain) -> Float {
    max(-1, min(1, value * gain))
  }
}

/// Synthesizes native speech into the same amplified PCM output as Gemini.
@MainActor public final class SystemSpeechStream {
  private let synthesizer = AVSpeechSynthesizer()
  private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
  private var timeout: Task<Void, Never>?
  public init() {}
  public func audio(_ text: String) -> AsyncThrowingStream<Data, Error> {
    let converter = SpeechPCMConverter()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    return AsyncThrowingStream { continuation in
      self.continuation = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor [weak self] in self?.stop() }
      }
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(8)) } catch { return }
        self?.continuation?.finish(throwing: SpeechStreamError.playbackStopped)
      }
      synthesizer.write(utterance) { [weak self] buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else {
          continuation.finish(throwing: PrototypeError.invalidResponse)
          return
        }
        Task { @MainActor [weak self] in self?.timeout?.cancel() }
        do {
          if pcm.frameLength == 0 {
            let tail = try converter.finish()
            if !tail.isEmpty { continuation.yield(tail) }
            continuation.finish()
          } else {
            let data = try converter.convert(pcm)
            if !data.isEmpty { continuation.yield(data) }
          }
        } catch { continuation.finish(throwing: error) }
      }
    }
  }
  public func stop() {
    timeout?.cancel()
    timeout = nil
    synthesizer.stopSpeaking(at: .immediate)
    continuation?.finish(throwing: CancellationError())
    continuation = nil
  }
}

/// AVSpeech callbacks may arrive off the main actor. Only the converter is shared,
/// serialized by this lock; mutable AVAudioBuffers never cross to an actor.
public final class SpeechPCMConverter: @unchecked Sendable {
  private let lock = NSLock()
  private let target = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
  private var converter: AVAudioConverter?
  public init() {}
  public func convert(_ input: AVAudioPCMBuffer) throws -> Data {
    lock.lock(); defer { lock.unlock() }
    if converter?.inputFormat != input.format {
      converter = AVAudioConverter(from: input.format, to: target)
    }
    guard let converter else { throw PrototypeError.invalidResponse }
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 24_000 / input.format.sampleRate)) + 256
    return try render(converter, capacity: capacity, input: input)
  }
  public func finish() throws -> Data {
    lock.lock(); defer { lock.unlock() }
    guard let converter else { return Data() }
    return try render(converter, capacity: 1024, input: nil)
  }
  private func render(_ converter: AVAudioConverter, capacity: AVAudioFrameCount,
    input: AVAudioPCMBuffer?) throws -> Data {
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
      throw PrototypeError.invalidResponse
    }
    var sent = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, flag in
      if let input, !sent { sent = true; flag.pointee = .haveData; return input }
      flag.pointee = input == nil ? .endOfStream : .noDataNow
      return nil
    }
    if status == .error { throw error ?? PrototypeError.invalidResponse as NSError }
    guard let samples = output.floatChannelData?[0] else { throw PrototypeError.invalidResponse }
    var result = Data(capacity: Int(output.frameLength) * 2)
    for index in 0..<Int(output.frameLength) {
      let value = Int16(max(-32768, min(32767, samples[index] * 32768)))
      let bits = UInt16(bitPattern: value)
      result.append(UInt8(truncatingIfNeeded: bits))
      result.append(UInt8(truncatingIfNeeded: bits >> 8))
    }
    return result
  }
}

private final class AudioConfigurationObservation: @unchecked Sendable {
  let token: NSObjectProtocol
  init(_ token: NSObjectProtocol) { self.token = token }
  deinit { NotificationCenter.default.removeObserver(token) }
}

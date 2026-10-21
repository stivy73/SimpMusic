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

  public init() {
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
        samples[index] = Float(Int16(bitPattern: low | high)) / 32768
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
        node.play()
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

private final class AudioConfigurationObservation: @unchecked Sendable {
  let token: NSObjectProtocol
  init(_ token: NSObjectProtocol) { self.token = token }
  deinit { NotificationCenter.default.removeObserver(token) }
}

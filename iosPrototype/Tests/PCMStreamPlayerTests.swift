import AVFoundation
import Foundation
import XCTest

@testable import PrototypeCore

final class PCMStreamPlayerTests: XCTestCase {
  func testNarrationGainIsThirtyPercentAndBoundedAtPlayback() {
    XCTAssertEqual(NarrationLevel.sample(0.5), 0.65, accuracy: 0.0001)
    XCTAssertEqual(NarrationLevel.sample(-0.5), -0.65, accuracy: 0.0001)
    XCTAssertEqual(NarrationLevel.sample(0.99), 1)
    XCTAssertEqual(NarrationLevel.sample(-0.99), -1)
    XCTAssertEqual(NarrationLevel.sample(0), 0)
    XCTAssertEqual(NarrationLevel.sample(0.5, gain: 1), 0.5)
  }

  func testNativeSpeechConvertsFloatBuffersToSamePCMFormatAsCloudAndCache() throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
    buffer.frameLength = 480
    for n in 0..<480 { buffer.floatChannelData![0][n] = 0.25 }
    let converter = SpeechPCMConverter()
    let data = try converter.convert(buffer) + converter.finish()
    XCTAssertEqual(data.count, 960)
    XCTAssertEqual(Array(data.prefix(4)), [0, 32, 0, 32])
  }

  @MainActor
  func testFinishWaitsForLastSample() async throws {
    let player = PCMStreamPlayer()
    defer { player.stop() }
    let start = Date()
    var starts = 0
    try await player.enqueue(Data(repeating: 0, count: 48_000)) { starts += 1 }
    try await player.finish()
    XCTAssertEqual(starts, 1)
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.95)
    XCTAssertLessThan(Date().timeIntervalSince(start), 5)
  }

  @MainActor
  func testStopAndCancellationDoNotWaitForQueuedAudio() async throws {
    let player = PCMStreamPlayer()
    try await player.enqueue(Data(repeating: 0, count: 96_000)) {}
    let task = Task { try await player.finish() }
    task.cancel()
    do {
      try await task.value
      XCTFail()
    } catch is CancellationError {}
    player.stop()
    do {
      try await player.enqueue(Data([0, 0])) {}
      XCTFail()
    } catch is CancellationError {}
  }
}

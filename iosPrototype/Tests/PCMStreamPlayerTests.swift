import Foundation
import XCTest

@testable import PrototypeCore

final class PCMStreamPlayerTests: XCTestCase {
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

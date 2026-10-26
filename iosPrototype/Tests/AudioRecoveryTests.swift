import XCTest

@testable import PrototypeCore

final class AudioRecoveryTests: XCTestCase {
  func testStalledClockTriggersOnlyAfterEightSecondsWithoutProgress() {
    var recovery = AudioRecovery()
    XCTAssertFalse(
      recovery.observe(position: 59, now: 100, shouldPlay: true, ready: true, duration: 200))
    XCTAssertFalse(
      recovery.observe(position: 59, now: 107, shouldPlay: true, ready: true, duration: 200))
    XCTAssertTrue(
      recovery.observe(position: 59, now: 108, shouldPlay: true, ready: true, duration: 200))
  }

  func testPauseNarrationPreparationAndEndNeverTriggerRecovery() {
    for (playing, ready, position) in [
      (false, true, 59.0), (true, false, 59.0), (true, true, 199.8),
    ] {
      var recovery = AudioRecovery()
      XCTAssertFalse(
        recovery.observe(
          position: position, now: 0, shouldPlay: playing, ready: ready, duration: 200))
      XCTAssertFalse(
        recovery.observe(
          position: position, now: 90, shouldPlay: playing, ready: ready, duration: 200))
    }
  }

  func testProgressAndSeekRestartTheStallClock() {
    var recovery = AudioRecovery()
    XCTAssertFalse(
      recovery.observe(position: 59, now: 0, shouldPlay: true, ready: true, duration: 200))
    XCTAssertFalse(
      recovery.observe(position: 60, now: 7, shouldPlay: true, ready: true, duration: 200))
    XCTAssertFalse(
      recovery.observe(position: 60, now: 14, shouldPlay: true, ready: true, duration: 200))
    recovery.resetStall()
    XCTAssertFalse(
      recovery.observe(position: 120, now: 15, shouldPlay: true, ready: true, duration: 200))
    XCTAssertFalse(
      recovery.observe(position: 120, now: 22, shouldPlay: true, ready: true, duration: 200))
    XCTAssertTrue(
      recovery.observe(position: 120, now: 23, shouldPlay: true, ready: true, duration: 200))
  }

  func testRecoveryBudgetDoesNotResetWhenPlaybackMakesProgress() {
    var recovery = AudioRecovery()
    XCTAssertTrue(recovery.begin())
    _ = recovery.observe(position: 60, now: 0, shouldPlay: true, ready: true, duration: 200)
    _ = recovery.observe(position: 80, now: 20, shouldPlay: true, ready: true, duration: 200)
    XCTAssertTrue(recovery.begin())
    XCTAssertFalse(recovery.begin())
    XCTAssertEqual(recovery.attempts, 2)
    recovery = AudioRecovery()
    XCTAssertTrue(recovery.begin(), "A new queue occurrence gets a fresh budget")
  }
}

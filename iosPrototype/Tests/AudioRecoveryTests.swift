import XCTest

@testable import PrototypeCore

final class AudioRecoveryTests: XCTestCase {
  func testDoubledContainerUsesLengthOfTheSameYouTubeSource() {
    let timing = AudioPlaybackTiming(source: 258, container: 515.58839, audioEnd: 515.58839)
    XCTAssertEqual(timing.duration, 258.25)
    XCTAssertEqual(AudioPlaybackTiming(source: 258, container: 258.4, audioEnd: 258.4).duration, 258.4)
    XCTAssertEqual(AudioPlaybackTiming(source: 3840, container: 3840, audioEnd: 3840).duration, 3840)
  }

  func testEmptyTailAndUnknownDurationsDoNotBecomePlayableSilence() {
    XCTAssertEqual(AudioPlaybackTiming(source: 0, container: 126, audioEnd: 6).duration, 6)
    XCTAssertEqual(AudioPlaybackTiming(source: .nan, container: .infinity, audioEnd: 6).duration, 6)
    XCTAssertEqual(AudioPlaybackTiming(source: 258, container: .nan, audioEnd: .nan).duration, 258)
    XCTAssertEqual(AudioPlaybackTiming(source: 0, container: 0, audioEnd: .nan).duration, 0)
  }

  func testNowPlayingPublishesDiscontinuitiesRatherThanEveryProgressTick() {
    var publication = NowPlayingPublication()
    XCTAssertTrue(publication.shouldPublish(key: "song", duration: 258, position: 10, rate: 1, live: false, now: 100))
    for tick in 1...20 {
      let delta = Double(tick) / 2
      XCTAssertFalse(publication.shouldPublish(key: "song", duration: 258, position: 10 + delta, rate: 1, live: false, now: 100 + delta))
    }
    XCTAssertTrue(publication.shouldPublish(key: "song", duration: 258, position: 80, rate: 1, live: false, now: 111))
    XCTAssertTrue(publication.shouldPublish(key: "song", duration: 258, position: 80, rate: 0, live: false, now: 112))
    XCTAssertFalse(publication.shouldPublish(key: "song", duration: 258, position: 80, rate: 0, live: false, now: 120))
    XCTAssertTrue(publication.shouldPublish(key: "song-artwork", duration: 258, position: 80, rate: 0, live: false, now: 120))
  }

  func testNarrationHasItsOwnNonSeekableClockAndMusicRestoresItsPosition() {
    var publication = NowPlayingPublication()
    XCTAssertTrue(publication.shouldPublish(key: "song", duration: 258, position: 80, rate: 1, live: false, now: 100))
    XCTAssertTrue(publication.shouldPublish(key: "narration", duration: 0, position: 80, rate: 1, live: true, now: 101))
    XCTAssertFalse(publication.shouldPublish(key: "narration", duration: 0, position: 80, rate: 1, live: true, now: 160))
    XCTAssertTrue(publication.shouldPublish(key: "song", duration: 258, position: 80, rate: 1, live: false, now: 161))
    XCTAssertFalse(publication.shouldPublish(key: "song", duration: 258, position: 81, rate: 1, live: false, now: 162))
  }

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

import XCTest

@testable import PrototypeCore

final class SiriPlaybackActionTests: XCTestCase {
  func testEveryCommandRequiresASelectedSong() {
    for action in [SiriPlaybackAction.resume, .pause, .next, .explain, .radio] {
      XCTAssertThrowsError(try action.validate(hasSong: false, hasGeminiKey: true)) {
        XCTAssertEqual($0 as? SiriPlaybackError, .noSong)
      }
    }
  }
  func testCloudCommandsRequireConfigurationBeforeChangingPlayback() {
    for action in [SiriPlaybackAction.explain, .radio] {
      XCTAssertThrowsError(try action.validate(hasSong: true)) {
        XCTAssertEqual($0 as? SiriPlaybackError, .missingGeminiKey)
      }
    }
  }
  func testLocalPlaybackCommandsNeedNoCloudKeyAndCanInterruptNarration() {
    for action in [SiriPlaybackAction.resume, .pause, .next] {
      XCTAssertNoThrow(try action.validate(hasSong: true, loading: true, narrating: true))
    }
  }
  func testRepeatedExplainCannotRestartAnActiveNarration() {
    XCTAssertThrowsError(
      try SiriPlaybackAction.explain.validate(
        hasSong: true, narrating: true, hasGeminiKey: true)
    ) {
      XCTAssertEqual($0 as? SiriPlaybackError, .narrationInProgress)
    }
  }
  func testExplainWaitsForLoadingButRadioCanPrepareDuringBuffering() {
    XCTAssertThrowsError(
      try SiriPlaybackAction.explain.validate(
        hasSong: true, loading: true, hasGeminiKey: true)
    ) {
      XCTAssertEqual($0 as? SiriPlaybackError, .loading)
    }
    XCTAssertNoThrow(
      try SiriPlaybackAction.radio.validate(
        hasSong: true, loading: true, hasGeminiKey: true))
  }
  func testConfiguredCommandsCanStart() {
    XCTAssertNoThrow(try SiriPlaybackAction.explain.validate(hasSong: true, hasGeminiKey: true))
    XCTAssertNoThrow(try SiriPlaybackAction.radio.validate(hasSong: true, hasGeminiKey: true))
  }
}

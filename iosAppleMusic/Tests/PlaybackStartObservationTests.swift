import XCTest
@testable import LyricsContract
final class PlaybackStartObservationTests:XCTestCase {
  @MainActor func testPlayReturningWhilePausedIsNotSuccess() async throws {
    let result=try await PlaybackStartObservation.wait(attempts:3,current:{true},playing:{false},tick:{})
    XCTAssertEqual(result,.unconfirmed)
  }
  @MainActor func testDelayedNativeStartIsObserved() async throws {
    var ticks=0
    let result=try await PlaybackStartObservation.wait(attempts:5,current:{true},playing:{ticks==2},tick:{ticks+=1})
    XCTAssertEqual(result,.playing);XCTAssertEqual(ticks,2)
  }
  @MainActor func testUserPauseCancelsIntentWithoutFailureOrRetry() async throws {
    var current=true
    let result=try await PlaybackStartObservation.wait(attempts:5,current:{current},playing:{false},tick:{current=false})
    XCTAssertEqual(result,.cancelled)
  }
}

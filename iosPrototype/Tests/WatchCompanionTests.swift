import XCTest

@testable import PrototypeCore

final class WatchCompanionTests: XCTestCase {
  func testLongQueueKeepsCurrentOccurrenceVisibleInBoundedWindow() {
    XCTAssertEqual(WatchSnapshot.queueRange(count: 0, currentOffset: 0), 0..<0)
    XCTAssertEqual(WatchSnapshot.queueRange(count: 50, currentOffset: 0), 0..<40)
    let tail = WatchSnapshot.queueRange(count: 50, currentOffset: 48)
    XCTAssertTrue(tail.contains(48))
    XCTAssertEqual(tail.upperBound, 50)
    XCTAssertEqual(tail.count, 40)
  }
  private func snapshot() -> WatchSnapshot {
    var value = WatchSnapshot()
    value.track = .init(id: UUID().uuidString, title: "Brano", artist: "Artista")
    value.queue = [value.track!]
    return value
  }
  func testSnapshotRoundTripBoundsTextQueueAndInvalidTimes() throws {
    var value = snapshot()
    value.elapsed = .nan
    value.duration = .infinity
    value.meaning = String(repeating: "a", count: 10_000)
    value.queue = (0..<80).map { .init(id: String($0), title: "Titolo", artist: "Artista") }
    let data = try value.encoded()
    let result = try WatchSnapshot.decode(data)
    XCTAssertEqual(result.queue.count, 40)
    XCTAssertEqual(result.queueTotal, 80)
    XCTAssertEqual(result.meaning.count, 6000)
    XCTAssertEqual(result.elapsed, 0)
    XCTAssertEqual(result.duration, 0)
    XCTAssertLessThanOrEqual(data.count, 60_000)
  }
  func testStaleCommandNeverActsOnNewQueueOccurrenceOfSameSong() throws {
    let before = snapshot()
    let command = WatchCommand(action: .next, expectedTrackID: before.track?.id)
    XCTAssertNoThrow(try command.validate(against: before))
    var after = before
    after.track?.id = UUID().uuidString
    XCTAssertThrowsError(try command.validate(against: after))
  }
  func testUnicodeQueueAndArtworkStayWithinConnectivityBudget() throws {
    var value = snapshot()
    value.meaning = String(repeating: "語", count: 6000)
    value.artwork = Data(repeating: 1, count: 16_000)
    value.queue = (0..<40).map {
      .init(
        id: String($0), title: String(repeating: "語", count: 180),
        artist: String(repeating: "語", count: 180))
    }
    let data = try value.encoded()
    XCTAssertLessThanOrEqual(data.count, 60_000)
    let result = try WatchSnapshot.decode(data)
    XCTAssertEqual(result.queueTotal, 40)
    XCTAssertLessThan(result.queue.count, result.queueTotal)
    XCTAssertEqual(result.meaning.count, 6000)
  }
  func testExpiredAndFutureCommandsAreRejected() throws {
    let state = snapshot()
    for seconds in [-121.0, 121.0] {
      var command = WatchCommand(action: .play, expectedTrackID: state.track?.id)
      command.date = Date().addingTimeInterval(seconds)
      XCTAssertThrowsError(try command.validate(against: state))
    }
  }
  func testQueueSelectionRequiresExistingOccurrence() throws {
    let state = snapshot()
    let good = WatchCommand(
      action: .playOccurrence, expectedTrackID: state.track?.id, occurrenceID: state.track?.id)
    XCTAssertNoThrow(try good.validate(against: state))
    let bad = WatchCommand(
      action: .playOccurrence, expectedTrackID: state.track?.id, occurrenceID: UUID().uuidString)
    XCTAssertThrowsError(try bad.validate(against: state))
  }
  func testEmptyStateAllowsRefreshButNeverAudioCommands() throws {
    let state = WatchSnapshot()
    XCTAssertNoThrow(
      try WatchCommand(action: .refresh, expectedTrackID: nil).validate(against: state))
    for action in [
      WatchCommand.Action.play, .pause, .next, .previous, .explain, .radio, .stopExplanation,
    ] {
      XCTAssertThrowsError(
        try WatchCommand(action: action, expectedTrackID: nil).validate(against: state))
    }
  }
  func testUnknownSchemaAndOversizedPayloadsAreRejected() throws {
    var state = snapshot()
    state.version = 999
    XCTAssertThrowsError(try WatchSnapshot.decode(state.encoded()))
    XCTAssertThrowsError(try WatchCommand.decode(Data(repeating: 1, count: 2049)))
    XCTAssertThrowsError(try WatchSnapshot.decode(Data(repeating: 1, count: 60_001)))
  }
}

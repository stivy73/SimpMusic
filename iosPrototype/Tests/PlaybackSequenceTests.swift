import XCTest

@testable import PrototypeCore

final class PlaybackSequenceTests: XCTestCase {
  func testNaturalEndStopsWithoutRepeatAndWrapsAll() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 3, selected: 2, shuffle: false)
    XCTAssertNil(sequence.next(repeatMode: .off, automatic: true))
    XCTAssertEqual(sequence.next(repeatMode: .all, automatic: true), 0)
    XCTAssertEqual(sequence.previous(repeatMode: .off), 1)
  }
  func testRepeatOneOnlyRepeatsOnNaturalEndNotNextButton() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 3, selected: 1, shuffle: false)
    XCTAssertEqual(sequence.next(repeatMode: .one, automatic: true), 1)
    XCTAssertEqual(sequence.next(repeatMode: .one), 2)
  }
  func testShufflePreservesCurrentAndEveryOccurrence() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 20, selected: 8, shuffle: true)
    XCTAssertEqual(sequence.current, 8)
    XCTAssertEqual(sequence.order.first, 8)
    XCTAssertEqual(Set(sequence.order), Set(0..<20))
    XCTAssertEqual(sequence.order.count, 20)
    let next = sequence.next(repeatMode: .off)!
    sequence.select(next)
    XCTAssertEqual(sequence.previous(repeatMode: .off), 8)
    sequence.setShuffled(false)
    XCTAssertEqual(sequence.current, next)
    XCTAssertEqual(sequence.order, Array(0..<20))
  }
  func testEmptyAndSingleItemQueues() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 0, selected: 0, shuffle: true)
    XCTAssertNil(sequence.current)
    XCTAssertNil(sequence.next(repeatMode: .all))
    sequence.reset(count: 1, selected: 0, shuffle: true)
    XCTAssertNil(sequence.next(repeatMode: .off))
    XCTAssertEqual(sequence.next(repeatMode: .all), 0)
    XCTAssertEqual(sequence.previous(repeatMode: .all), 0)
  }
  func testVoiceIdentifiersRoundTripAndRejectMissingIDs() {
    for kind in [DiscoveryItem.Kind.song, .album, .artist] {
      let id = VoiceMediaIdentifier(kind: kind, mediaID: "media-123")
      XCTAssertEqual(VoiceMediaIdentifier(encoded: id.encoded), id)
    }
    XCTAssertNil(VoiceMediaIdentifier(encoded: "song:"))
    XCTAssertNil(VoiceMediaIdentifier(encoded: "invalid:123"))
  }
}

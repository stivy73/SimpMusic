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
  func testPlayNextInsertsWithoutRestartingOrReshufflingCurrentOrder() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 4, selected: 1, shuffle: true)
    let previousOrder = sequence.order
    XCTAssertEqual(sequence.append(playNext: true), 4)
    XCTAssertEqual(sequence.current, 1)
    XCTAssertEqual(sequence.order, [1, 4] + previousOrder.dropFirst())
    XCTAssertEqual(sequence.next(repeatMode: .one), 4)
    sequence.setShuffled(false)
    XCTAssertEqual(sequence.order, [0, 1, 4, 2, 3])
  }

  func testAppendAtEndKeepsEveryExistingOccurrenceAndCurrentSelection() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 3, selected: 1, shuffle: true)
    let order = sequence.order
    sequence.append()
    XCTAssertEqual(sequence.order, order + [3])
    XCTAssertEqual(sequence.current, 1)
    sequence.setShuffled(false)
    XCTAssertEqual(sequence.order, [0, 1, 2, 3])
  }

  func testManualMovePreservesCurrentAndBecomesCanonicalOrder() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 4, selected: 1, shuffle: false)
    XCTAssertTrue(sequence.move(from: IndexSet(integer: 3), to: 1))
    XCTAssertEqual(sequence.order, [0, 3, 1, 2])
    XCTAssertEqual(sequence.current, 1)
    XCTAssertEqual(sequence.next(repeatMode: .off), 2)
    sequence.setShuffled(true)
    sequence.setShuffled(false)
    XCTAssertEqual(sequence.order, [0, 3, 1, 2])
  }

  func testRemovingEarlierOccurrenceRemapsCurrentWithoutSelectingAnotherSong() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 5, selected: 3, shuffle: false)
    XCTAssertEqual(sequence.remove([0, 2]), [0, 2])
    XCTAssertEqual(sequence.order, [0, 1, 2])
    XCTAssertEqual(sequence.current, 1)  // original occurrence 3
    XCTAssertEqual(sequence.next(repeatMode: .off), 2)  // original occurrence 4
  }

  func testRemovingCurrentSelectsFollowingOccurrenceAndLastFallsBackToPrevious() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 4, selected: 1, shuffle: false)
    sequence.remove([1])
    XCTAssertEqual(sequence.current, 1)  // original occurrence 2
    sequence.select(2)
    sequence.remove([2])
    XCTAssertEqual(sequence.current, 1)
    sequence.remove([0, 1])
    XCTAssertTrue(sequence.order.isEmpty)
    XCTAssertNil(sequence.current)
    XCTAssertNil(sequence.next(repeatMode: .all))
  }

  func testMoveExistingOccurrenceNextDoesNotDuplicateItEvenWithShuffle() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 6, selected: 2, shuffle: true)
    sequence.playNext(5)
    XCTAssertEqual(sequence.current, 2)
    XCTAssertEqual(sequence.next(repeatMode: .off), 5)
    XCTAssertEqual(Set(sequence.order), Set(0..<6))
    XCTAssertEqual(sequence.order.count, 6)
    sequence.setShuffled(false)
    XCTAssertEqual(sequence.order, [0, 1, 2, 5, 3, 4])
  }

  func testMixedQueueEditsMaintainContiguousStorageIndicesAndValidSelection() {
    var sequence = PlaybackSequence()
    sequence.reset(count: 20, selected: 8, shuffle: true)
    for iteration in 0..<100 {
      sequence.append(playNext: iteration % 2 == 0)
      let storageCount = sequence.order.count
      if storageCount > 3 {
        let removed = sequence.order.last!
        sequence.remove([removed])
      }
      sequence.move(from: IndexSet(integer: sequence.order.count - 1), to: 0)
      XCTAssertEqual(Set(sequence.order), Set(0..<sequence.order.count))
      XCTAssertEqual(sequence.order.count, Set(sequence.order).count)
      XCTAssertTrue(sequence.order.contains(sequence.current!))
    }
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

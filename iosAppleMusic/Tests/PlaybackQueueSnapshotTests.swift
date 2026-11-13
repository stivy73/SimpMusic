import XCTest
@testable import LyricsContract

private struct QueueOccurrence:Identifiable,Equatable {let id:String;let song:String}
final class PlaybackQueueSnapshotTests:XCTestCase {
  func testNativeQueueLossPreservesOrderDuplicateSongsAndSelectedOccurrence() {
    let entries=[QueueOccurrence(id:"a",song:"Seal"),.init(id:"b",song:"Belinda"),.init(id:"c",song:"Seal")]
    var snapshot=PlaybackQueueSnapshot<QueueOccurrence>()
    snapshot.capture(entries,current:"c");snapshot.capture(entries,current:nil);snapshot.capture([],current:nil)
    XCTAssertEqual(snapshot.displayed([]),entries);XCTAssertEqual(snapshot.current?.id,"c")
  }
  func testNewNativeQueueWinsAndReplacesOldSelection() {
    var snapshot=PlaybackQueueSnapshot<QueueOccurrence>()
    snapshot.capture([.init(id:"a",song:"Seal")],current:"a")
    let native=[QueueOccurrence(id:"new",song:"Belinda")]
    XCTAssertEqual(snapshot.displayed(native),native)
    snapshot.capture(native,current:"new");XCTAssertEqual(snapshot.displayed([]),native)
    XCTAssertEqual(snapshot.current?.id,"new")
  }
  func testNewPlaybackIntentClearsOldQueueEvenIfPreparationFails() {
    var snapshot=PlaybackQueueSnapshot<QueueOccurrence>()
    snapshot.capture([.init(id:"a",song:"Seal")],current:"a");snapshot.clear();snapshot.capture([],current:nil)
    XCTAssertTrue(snapshot.displayed([]).isEmpty);XCTAssertNil(snapshot.current)
  }
}

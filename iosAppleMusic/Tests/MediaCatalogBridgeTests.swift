import XCTest
@testable import LyricsContract

private struct MediaSongFixture: Sendable { let id: String }
private actor MediaBatchFixture {
  var batches: [[String]] = []
  let failAt: Int?
  init(failAt:Int? = nil) { self.failAt=failAt }
  func fetch(_ ids:[String]) throws -> [MediaSongFixture] {
    batches.append(ids)
    if batches.count == failAt { throw URLError(.timedOut) }
    return ids.reversed().map { .init(id:$0) }
  }
  func requests() -> [[String]] { batches }
}
final class MediaCatalogBridgeTests: XCTestCase {
  func testOnlyExactUsableCatalogIDsAreAcceptedAndDeduplicated() {
    XCTAssertEqual(MediaCatalogBridge.catalogIDs(["", "0", "i.private", "l.album", "42", "42", " 123", "123 ", "１２３", "44"]),["42","44"])
  }
  func testFourteenDeviceTracksKeepTheirOrderEvenWhenAppleReturnsReversedResults() async throws {
    let ids=(1...14).map(String.init)
    let fixture=MediaBatchFixture()
    let result=try await MediaCatalogBridge.resolve(ids,id:{ (item:MediaSongFixture) in item.id },fetch:{ try await fixture.fetch($0) })
    XCTAssertEqual(result.items.map(\.id),ids)
    XCTAssertEqual(result.requested,14)
    XCTAssertEqual(result.unresolved,0)
  }
  func testMissingCatalogItemsAreCountedWithoutInventingReplacements() async throws {
    let result=try await MediaCatalogBridge.resolve(["11","12","13"],id:{ (item:MediaSongFixture) in item.id },fetch:{ _ in [.init(id:"12"),.init(id:"12")] })
    XCTAssertEqual(result.items.map(\.id),["12"])
    XCTAssertEqual(result.unresolved,2)
  }
  func testDoesNotPublishPartialResultsWhenLaterBatchFails() async {
    let fixture=MediaBatchFixture(failAt:2)
    do {
      _ = try await MediaCatalogBridge.resolve((1...201).map(String.init),id:{ (item:MediaSongFixture) in item.id },fetch:{ try await fixture.fetch($0) })
      XCTFail("Partial library must not be published")
    } catch { XCTAssertEqual((error as? URLError)?.code,.timedOut) }
    let requests=await fixture.requests()
    XCTAssertEqual(requests.map(\.count),[100,100])
  }
  func testUnexpectedCatalogItemCannotEnterTheLibrary() async {
    do {
      _ = try await MediaCatalogBridge.resolve(["11"],id:{ (item:MediaSongFixture) in item.id },fetch:{ _ in [.init(id:"99")] })
      XCTFail("Only IDs already observed on the device are allowed")
    } catch { XCTAssertTrue(error is MediaCatalogBridge.BridgeError) }
  }
  func testNoUsableIDsDoesNotMakeACatalogRequest() async throws {
    let fixture=MediaBatchFixture()
    let result=try await MediaCatalogBridge.resolve(["0",""],id:{ (item:MediaSongFixture) in item.id },fetch:{ try await fixture.fetch($0) })
    XCTAssertEqual(result.requested,0)
    let requests=await fixture.requests()
    XCTAssertTrue(requests.isEmpty)
  }
  func testCancellationStopsBeforeRequestingNextBatch() async {
    let fixture=MediaBatchFixture()
    let task=Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await MediaCatalogBridge.resolve(["11"],id:{ (item:MediaSongFixture) in item.id },fetch:{ try await fixture.fetch($0) })
    }
    do { _ = try await task.value; XCTFail("Cancelled request must stop") }
    catch { XCTAssertTrue(error is CancellationError) }
    let requests=await fixture.requests()
    XCTAssertTrue(requests.isEmpty)
  }
}

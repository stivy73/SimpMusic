import XCTest
@testable import LyricsContract

final class PlaylistPolicyTests:XCTestCase {
  func testMovesUseOccurrencesAndKeepDuplicateMediaIDs() throws {
    let values=["same:first","other","same:second"]
    XCTAssertEqual(try PlaylistPolicy.moved(values,from:0,to:3),["other","same:second","same:first"])
    XCTAssertEqual(try PlaylistPolicy.moved(values,from:2,to:0),["same:second","same:first","other"])
    XCTAssertEqual(try PlaylistPolicy.moved(values,from:1,to:1),values)
    XCTAssertThrowsError(try PlaylistPolicy.moved(values,from:4,to:0))
    XCTAssertThrowsError(try PlaylistPolicy.moved(values,from:0,to:4))
  }
  func testChangedSnapshotIsRejectedBeforeRewriting() throws {
    try PlaylistPolicy.requireSnapshot(["a","b","a"],current:["a","b","a"])
    XCTAssertThrowsError(try PlaylistPolicy.requireSnapshot(["a","b","a"],current:["a","a","b"]))
    XCTAssertThrowsError(try PlaylistPolicy.requireSnapshot(["a"],current:["a","new"]))
  }
  func testAddPermissionRequiresExactPlaylistAndExplicitBoolean() throws {
    func data(_ flag:Any,id:String="p.abc") throws -> Data {try JSONSerialization.data(withJSONObject:["data":[["id":id,"attributes":["canEdit":flag]]]])}
    XCTAssertTrue(try PlaylistPolicy.canAdd(data:data(true),status:200,id:"p.abc"))
    XCTAssertFalse(try PlaylistPolicy.canAdd(data:data(false),status:200,id:"p.abc"))
    XCTAssertThrowsError(try PlaylistPolicy.canAdd(data:data(1),status:200,id:"p.abc"))
    XCTAssertThrowsError(try PlaylistPolicy.canAdd(data:data(true),status:403,id:"p.abc"))
    XCTAssertThrowsError(try PlaylistPolicy.canAdd(data:data(true,id:"p.other"),status:200,id:"p.abc"))
  }
  func testPlaylistNameBoundaries() throws {
    XCTAssertEqual(try PlaylistPolicy.name("  In viaggio  "),"In viaggio")
    XCTAssertThrowsError(try PlaylistPolicy.name(" \n"))
    XCTAssertThrowsError(try PlaylistPolicy.name("A\nB"))
    XCTAssertThrowsError(try PlaylistPolicy.name(String(repeating:"x",count:201)))
  }
}

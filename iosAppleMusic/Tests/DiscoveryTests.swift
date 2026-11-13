import XCTest
@testable import LyricsContract

final class DiscoveryTests:XCTestCase {
  private struct Release {let id:String;let date:Date?}
  func testRecentReleasesUseReleaseDateDeduplicateAndExcludeFutureOrUnknown() {
    let now=Date(timeIntervalSince1970:20_000_000),day=86_400.0
    let input=[Release(id:"old",date:now.addingTimeInterval(-91*day)),Release(id:"new",date:now.addingTimeInterval(-day)),Release(id:"unknown",date:nil),Release(id:"future",date:now.addingTimeInterval(day)),Release(id:"boundary",date:now.addingTimeInterval(-90*day)),Release(id:"new",date:now.addingTimeInterval(-day)),Release(id:"a",date:now.addingTimeInterval(-day))]
    XCTAssertEqual(DiscoveryPolicy.recent(input,now:now,id:{$0.id},date:{$0.date}).map(\.id),["a","new","boundary"])
    XCTAssertEqual(input.count,7)
  }
  func testOriginalOrderCanBeReversedWithoutChangingTheSource() {
    var preference=BrowsePreferences();preference.descending=true
    let source=["third","first","second"]
    XCTAssertEqual(preference.sorted(source,title:{$0},artist:{$0}),["second","first","third"])
    preference.descending=false;XCTAssertEqual(preference.sorted(source,title:{$0},artist:{$0}),source)
  }
  func testRemoveOnlySelectedSearchPreservingRemainingOrder() {
    XCTAssertEqual(BrowseHistory.removing("SÉAL",from:["Rock","Seal","Jazz"]),["Rock","Jazz"])
    XCTAssertEqual(BrowseHistory.removing("missing",from:["Seal","Jazz"]),["Seal","Jazz"])
  }
  func testArtistFavoritesUseCatalogRelationshipsAndRetainPagination() throws {
    let input=Data(#"{"next":"/v1/me/library/artists?offset=100","data":[{"id":"r.one","relationships":{"catalog":{"data":[{"id":"123","type":"artists"}]}}},{"id":"r.local","relationships":{"catalog":{"data":[]}}}]}"#.utf8)
    let data=try ArtistFavoriteBridge.references(input,status:200)
    let json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    XCTAssertEqual(json["next"] as? String,"/v1/me/library/artists?offset=100")
    let values=try XCTUnwrap(json["data"] as? [[String:String]])
    XCTAssertEqual(values,[["id":"123"]])
  }
  func testMissingArtistRelationshipIsAnErrorRatherThanAnEmptyFavoriteList() {
    for input in [#"{"data":[{"id":"r.one"}]}"#,#"{"data":[{"relationships":{"catalog":{"data":[{"id":"123","type":"songs"}]}}}]}"#,#"{"data":[{"relationships":{"catalog":{"data":[{"id":"123/secret","type":"artists"}]}}}]}"#] {
      XCTAssertThrowsError(try ArtistFavoriteBridge.references(Data(input.utf8),status:200))
    }
    XCTAssertThrowsError(try ArtistFavoriteBridge.references(Data(#"{"data":[]}"#.utf8),status:403))
  }
  func testFavoriteArtistCatalogBatchMustBeCompleteAndConfirmed() throws {
    let input=Data(#"{"data":[{"id":"1","type":"artists","attributes":{"inFavorites":true}},{"id":"2","type":"artists","attributes":{"inFavorites":false}}]}"#.utf8)
    let result=try ArtistFavoriteBridge.favorites(input,status:200,expected:["1","2"])
    let page=try JSONSerialization.jsonObject(with:result) as! [String:Any]
    XCTAssertEqual((page["data"] as? [[String:Any]])?.compactMap{$0["id"] as? String},["1"])
    XCTAssertThrowsError(try ArtistFavoriteBridge.favorites(input,status:200,expected:["1","2","3"]))
  }
}

import XCTest
@testable import LyricsContract
final class MusicFavoriteRequestTests:XCTestCase {
  func testAddUsesOfficialTypedIDsAndNeverDeletes() throws {
    let request=try MusicFavoriteRequest.request(type:"songs",id:"12345")
    XCTAssertEqual(request.httpMethod,"POST")
    let url=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
    XCTAssertEqual(url.host,"api.music.apple.com");XCTAssertEqual(url.path,"/v1/me/favorites")
    XCTAssertEqual(url.queryItems,[.init(name:"ids[songs]",value:"12345")])
  }
  func testRejectsPrivateIDsAndURLInjection() {
    for id in ["","i.private","l.private","p.private","123/x","123?x","12&ids=other"] {
      XCTAssertThrowsError(try MusicFavoriteRequest.request(type:"songs",id:id))
    }
    XCTAssertThrowsError(try MusicFavoriteRequest.request(type:"invalid",id:"123"))
  }
  func testOnlyExplicitBooleanIsFavoriteState() throws {
    for (value,expected) in [("true",true),("false",false)] {
      XCTAssertEqual(try MusicFavoriteRequest.state(from:Data("{\"data\":[{\"attributes\":{\"inFavorites\":\(value)}}]}".utf8),status:200),expected)
    }
    for body in [#"{"data":[{"attributes":{}}]}"#,#"{"data":[{"attributes":{"inFavorites":1}}]}"#] {
      XCTAssertNil(try MusicFavoriteRequest.state(from:Data(body.utf8),status:200))
    }
    XCTAssertThrowsError(try MusicFavoriteRequest.state(from:Data(),status:202))
  }
  func testFavoriteFilteringPreservesNextAndRejectsUnknownState() throws {
    let body=Data(#"{"data":[{"id":"yes","attributes":{"inFavorites":true}},{"id":"no","attributes":{"inFavorites":false}}],"next":"/v1/me/library/songs?offset=100"}"#.utf8)
    let filtered=try MusicFavoriteRequest.favoritePage(body,status:200)
    let json=try JSONSerialization.jsonObject(with:filtered) as! [String:Any]
    XCTAssertEqual((json["data"] as? [[String:Any]])?.count,1)
    XCTAssertEqual(json["next"] as? String,"/v1/me/library/songs?offset=100")
    XCTAssertThrowsError(try MusicFavoriteRequest.favoritePage(Data(#"{"data":[{"attributes":{}}]}"#.utf8),status:200))
    XCTAssertThrowsError(try MusicFavoriteRequest.favoritePage(body,status:403))
  }
  func testCatalogMappingCannotGuessMissingAmbiguousOrUnauthorizedIDs() throws {
    XCTAssertEqual(try MusicFavoriteRequest.catalogID(from:Data(#"{"data":[{"id":"123"}]}"#.utf8),status:200),"123")
    for body in [#"{"data":[]}"#,#"{"data":[{"id":"1"},{"id":"2"}]}"#,#"{"errors":[],"data":[{"id":"1"}]}"#] {
      XCTAssertThrowsError(try MusicFavoriteRequest.catalogID(from:Data(body.utf8),status:200))
    }
    XCTAssertThrowsError(try MusicFavoriteRequest.catalogID(from:Data(#"{"data":[{"id":"123"}]}"#.utf8),status:403))
  }
}

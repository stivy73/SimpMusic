import XCTest
@testable import LyricsContract
private struct ExplicitSong:Decodable {let id:String}
final class MediaCatalogRequestTests:XCTestCase {
  func testFourteenIDsUseDocumentedIDsParameterAndAccountStorefront() throws {
    let ids=(1...14).map(String.init)
    let request=try MediaCatalogRequest.request(ids:ids,storefront:"IT")
    let url=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
    XCTAssertEqual(url.path,"/v1/catalog/it/songs")
    XCTAssertEqual(url.queryItems,[.init(name:"ids",value:ids.joined(separator:","))])
    XCTAssertEqual(request.cachePolicy,.reloadIgnoringLocalCacheData)
  }
  func testErrorsOrMalformedPayloadCannotBecomeUnavailableTracks() {
    for body in [#"{}"#,#"{"data":[],"errors":[]}"#,#"{"data":[],"next":"/other"}"#] {
      XCTAssertThrowsError(try MediaCatalogRequest.items(ExplicitSong.self,data:Data(body.utf8),status:200))
    }
    XCTAssertThrowsError(try MediaCatalogRequest.items(ExplicitSong.self,data:Data(#"{"data":[]}"#.utf8),status:403))
  }
  func testReturnsCatalogIDsWithoutFabricatingMatches() throws {
    let result=try MediaCatalogRequest.items(ExplicitSong.self,data:Data(#"{"data":[{"id":"2"},{"id":"1"}]}"#.utf8),status:200)
    XCTAssertEqual(result.map(\.id),["2","1"])
    XCTAssertThrowsError(try MediaCatalogRequest.request(ids:["i.private"],storefront:"IT"))
    XCTAssertThrowsError(try MediaCatalogRequest.request(ids:["1"],storefront:"IT/evil"))
  }
}

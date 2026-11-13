import XCTest
@testable import LyricsContract

final class CatalogArtworkLookupTests:XCTestCase {
  func testExactReportedSealIDReturnsItsAppleImage() throws {
    let data=Data(#"{"resultCount":1,"results":[{"wrapperType":"track","kind":"song","trackId":302788219,"trackName":"Kiss from a Rose","artistName":"Seal","artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/34/b5/2f/34b52f15-c64a-6971-78d3-277d08d9779d/dj.bxnijqdz.jpg/100x100bb.jpg"}]}"#.utf8)
    let url=try CatalogArtworkLookup.artwork(data,status:200,id:"302788219")
    XCTAssertEqual(url?.lastPathComponent,"100x100bb.jpg")
    XCTAssertNil(try CatalogArtworkLookup.artwork(data,status:200,id:"30475379"))
  }
  func testNoTitleMatchingAlbumSubstitutionOrUntrustedImageHost() throws {
    for item in [#"{"wrapperType":"collection","kind":"album","trackId":1}"#,
      #"{"wrapperType":"track","kind":"song","trackId":2,"trackName":"Same title","artworkUrl100":"https://is1.mzstatic.com/other.jpg"}"#,
      #"{"wrapperType":"track","kind":"song","trackId":1,"artworkUrl100":"https://mzstatic.com.attacker.test/cover.jpg"}"#,
      #"{"wrapperType":"track","kind":"song","trackId":true,"artworkUrl100":"https://is1.mzstatic.com/cover.jpg"}"#] {
      let body=Data(("{\"results\":["+item+"]}").utf8)
      XCTAssertNil(try CatalogArtworkLookup.artwork(body,status:200,id:"1"))
    }
  }
  func testLookupUsesOnlyExactIDAndStorefrontWithoutCredentials() throws {
    let request=try CatalogArtworkLookup.request(id:"302788219",country:"IT")
    let parts=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
    XCTAssertEqual(parts.host,"itunes.apple.com");XCTAssertEqual(parts.path,"/lookup")
    XCTAssertEqual(parts.queryItems,[.init(name:"id",value:"302788219"),.init(name:"country",value:"it"),.init(name:"entity",value:"song")])
    XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"))
    XCTAssertThrowsError(try CatalogArtworkLookup.request(id:"i.private",country:"it"))
    XCTAssertThrowsError(try CatalogArtworkLookup.request(id:"1",country:"it/evil"))
  }
  func testHTTPFailureAndMalformedPayloadCannotBecomeSuccess() {
    XCTAssertThrowsError(try CatalogArtworkLookup.artwork(Data(#"{"results":[]}"#.utf8),status:403,id:"1"))
    XCTAssertThrowsError(try CatalogArtworkLookup.artwork(Data(#"{}"#.utf8),status:200,id:"1"))
  }
}

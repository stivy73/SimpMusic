import XCTest
@testable import LyricsContract
final class MusicCloudProbeTests: XCTestCase {
  func testEmptyLibraryRequiresAnExplicitSuccessfulDataArray() throws {
    XCTAssertEqual(try MusicCloudProbe.parse(Data(#"{"data":[]}"#.utf8),status:200),.init(firstPageCount:0,hasMore:false))
    for body in [#"{}"#,#"{"errors":[{"code":"FORBIDDEN"}]}"#,#"{"data":[],"errors":[]}"#] {
      XCTAssertThrowsError(try MusicCloudProbe.parse(Data(body.utf8),status:200))
    }
  }
  func testPagedSampleIsNotReportedAsCompleteLibraryCount() throws {
    let sample = try MusicCloudProbe.parse(Data(#"{"data":[{"id":"fixture"}],"next":"/v1/me/library/albums?offset=1"}"#.utf8),status:200)
    XCTAssertEqual(sample,.init(firstPageCount:1,hasMore:true))
  }
  func testAuthenticationErrorIsNotAnEmptyLibrary() {
    for code in [401,403,500] { XCTAssertThrowsError(try MusicCloudProbe.parse(Data(#"{"data":[]}"#.utf8),status:code)) }
  }
  func testProbeUsesOnlyOfficialReadOnlyEndpointsWithoutCredentialHeaders() {
    for resource in MusicCloudProbe.Resource.allCases {
      let request = MusicCloudProbe.request(for:resource)
      XCTAssertEqual(request.httpMethod,"GET")
      XCTAssertEqual(request.url?.host,"api.music.apple.com")
      XCTAssertEqual(request.url?.scheme,"https")
      XCTAssertEqual(request.url?.query,"limit=1")
      XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"))
      XCTAssertNil(request.httpBody)
    }
  }
}

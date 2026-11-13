import XCTest
@testable import LyricsContract
private struct PersonalItem:Codable,Identifiable,Sendable {let id:String}
private actor SearchReplies {
  var calls:[URLRequest]=[]
  let bodies:[String]
  init(_ values:[String]) {bodies=values}
  func fetch(_ request:URLRequest) throws -> MusicCloudLibrary.Response {
    calls.append(request);guard calls.count<=bodies.count else{throw URLError(.timedOut)}
    return .init(data:Data(bodies[calls.count-1].utf8),status:200)
  }
  func requests()->[URLRequest] {calls}
}
final class PersonalSearchTests:XCTestCase {
  func testEveryPersonalCategoryUsesLibraryResourceAndExactTerm() async throws {
    for kind in MusicCloudProbe.Resource.allCases {
      let replies=SearchReplies(["{\"results\":{\"library-\(kind.rawValue)\":{\"data\":[{\"id\":\"personal\"}]}}}"])
      let client=MusicCloudLibrary(fetch:{try await replies.fetch($0)})
      let result=try await client.search(PersonalItem.self,resource:kind,term:"Seal & Belinda")
      XCTAssertEqual(result.items.map(\.id),["personal"])
      let requests=await replies.requests();let url=URLComponents(url:requests[0].url!,resolvingAgainstBaseURL:false)!
      XCTAssertEqual(url.path,"/v1/me/library/search")
      XCTAssertEqual(url.queryItems?.first(where:{$0.name=="types"})?.value,"library-"+kind.rawValue)
      XCTAssertEqual(url.queryItems?.first(where:{$0.name=="term"})?.value,"Seal & Belinda")
    }
  }
  func testPlaylistPaginationKeepsIDsAndRejectsQuerySwitch() async throws {
    let valid=SearchReplies([#"{"results":{"library-playlists":{"data":[{"id":"one"}],"next":"?term=test&types=library-playlists&offset=25"}}}"#,#"{"results":{"library-playlists":{"data":[{"id":"one"},{"id":"two"}]}}}"#])
    let result=try await MusicCloudLibrary(fetch:{try await valid.fetch($0)}).search(PersonalItem.self,resource:.playlists,term:"test")
    XCTAssertEqual(result.items.map(\.id),["one","two"]);XCTAssertEqual(result.pages,2)
    for next in ["?term=other&types=library-playlists","?term=test&types=library-songs","https://example.org/v1/me/library/search?term=test&types=library-playlists"] {
      let fixture=SearchReplies(["{\"results\":{\"library-playlists\":{\"data\":[],\"next\":\"\(next)\"}}}"])
      do {_ = try await MusicCloudLibrary(fetch:{try await fixture.fetch($0)}).search(PersonalItem.self,resource:.playlists,term:"test");XCTFail("must reject switched query")}
      catch {XCTAssertTrue(error is MusicCloudLibrary.LoadError)}
    }
  }
  func testFailedContinuationDoesNotPublishPartialPersonalSearch() async {
    let fixture=SearchReplies([#"{"results":{"library-songs":{"data":[{"id":"one"}],"next":"?term=test&types=library-songs&offset=25"}}}"#])
    do {_ = try await MusicCloudLibrary(fetch:{try await fixture.fetch($0)}).search(PersonalItem.self,resource:.songs,term:"test");XCTFail("partial search must fail")}
    catch {XCTAssertTrue(error is URLError)}
  }
}

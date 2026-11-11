import XCTest
@testable import LyricsContract
private struct CloudFixture: Codable, Identifiable, Sendable { let id: String }
private actor CloudPages {
  let pages: [MusicCloudLibrary.Response]
  var requests: [URLRequest] = []
  init(_ bodies: [String], status: Int = 200) { pages = bodies.map { .init(data:Data($0.utf8),status:status) } }
  func fetch(_ request: URLRequest) throws -> MusicCloudLibrary.Response {
    requests.append(request)
    guard requests.count <= pages.count else { throw URLError(.cannotConnectToHost) }
    return pages[requests.count-1]
  }
  func count() -> Int { requests.count }
}
final class MusicCloudLibraryTests: XCTestCase {
  func testCloudMergeKeepsDeviceOnlyItemsAndUsesUpdatedCloudMetadata() {
    struct Item: Identifiable { let id: String; let title: String }
    let result = MusicCloudLibrary.combining([Item(id:"shared",title:"New metadata"),Item(id:"cloud",title:"Cloud")],
      local:[Item(id:"shared",title:"Old metadata"),Item(id:"device",title:"Smart playlist")])
    XCTAssertEqual(result.map(\.id),["shared","cloud","device"])
    XCTAssertEqual(result.first?.title,"New metadata")
  }
  func testAllPagesAreLoadedInOrderAndDuplicatesDoNotDuplicateRows() async throws {
    let fixture = CloudPages([#"{"data":[{"id":"a"},{"id":"b"}],"next":"/v1/me/library/albums?offset=100"}"#,#"{"data":[{"id":"b"},{"id":"c"}]}"#])
    let client = MusicCloudLibrary(fetch:{ try await fixture.fetch($0) })
    let result = try await client.load(CloudFixture.self,resource:.albums)
    XCTAssertEqual(result.items.map(\.id),["a","b","c"])
    XCTAssertEqual(result.pages,2)
  }
  func testFailureOnSecondPageDoesNotReturnAnIncompleteCollection() async {
    let fixture = CloudPages([#"{"data":[{"id":"a"}],"next":"/v1/me/library/albums?offset=100"}"#])
    do {
      _ = try await MusicCloudLibrary(fetch:{ try await fixture.fetch($0) }).load(CloudFixture.self,resource:.albums)
      XCTFail("Incomplete collection must fail")
    } catch { XCTAssertTrue(error is URLError) }
  }
  func testPaginationDoesNotFollowOtherHostsCollectionsOrSchemes() throws {
    let base = URL(string:"https://api.music.apple.com/v1/me/library/albums?limit=100")!
    for next in ["https://example.org/v1/me/library/albums","http://api.music.apple.com/v1/me/library/albums","/v1/me/library/songs?offset=1","https://user:secret@api.music.apple.com/v1/me/library/albums","/v1/me/library/albums#part","/v1/me/library/albums/%2e%2e"] {
      XCTAssertThrowsError(try MusicCloudLibrary.nextURL(next,relativeTo:base,expectedPath:base.path))
    }
    XCTAssertEqual(try MusicCloudLibrary.nextURL("?offset=100",relativeTo:base,expectedPath:base.path).path,base.path)
  }
  func testRepeatedPageStopsBeforeRepeatingTheRequest() async {
    let fixture = CloudPages([#"{"data":[{"id":"a"}],"next":"/v1/me/library/albums?limit=100"}"#])
    do { _ = try await MusicCloudLibrary(fetch:{ try await fixture.fetch($0) }).load(CloudFixture.self,resource:.albums); XCTFail() }
    catch { guard case MusicCloudLibrary.LoadError.repeatedPage = error else { return XCTFail("Unexpected error") } }
    let count = await fixture.count(); XCTAssertEqual(count,1)
  }
  func testCancellationDoesNotIssueARequest() async {
    let fixture = CloudPages([#"{"data":[]}"#])
    let client = MusicCloudLibrary(fetch:{ try await fixture.fetch($0) })
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await client.load(CloudFixture.self,resource:.albums)
    }
    do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    let count = await fixture.count(); XCTAssertEqual(count,0)
  }
  func testEmptyCloudLibraryIsAnExplicitSuccessfulResult() async throws {
    let fixture = CloudPages([#"{"data":[]}"#])
    let result = try await MusicCloudLibrary(fetch:{ try await fixture.fetch($0) }).load(CloudFixture.self,resource:.songs)
    XCTAssertEqual(result.items.count,0); XCTAssertEqual(result.pages,1)
  }
  func testBadOrUnauthorizedResponsesAreNotAcceptedAsEmptyLibraries() async {
    for (body,status) in [(#"{"data":[]}"#,403),(#"{"errors":[{}]}"#,200),(#"{}"#,200)] {
      let fixture = CloudPages([body],status:status)
      do { _ = try await MusicCloudLibrary(fetch:{ try await fixture.fetch($0) }).load(CloudFixture.self,resource:.songs); XCTFail() }
      catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
    }
  }
}

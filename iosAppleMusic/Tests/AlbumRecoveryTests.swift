import XCTest
@testable import LyricsContract
private struct RecoveredAlbum: Codable, Identifiable, Sendable { let id:String }
private actor AlbumPages {
  var bodies:[String]
  var requests:[URLRequest]=[]
  init(_ bodies:[String]) { self.bodies=bodies }
  func fetch(_ request:URLRequest) throws -> MusicCloudLibrary.Response {
    requests.append(request)
    guard !bodies.isEmpty else { throw URLError(.timedOut) }
    return .init(data:Data(bodies.removeFirst().utf8),status:200)
  }
  func captured()->[URLRequest] { requests }
}
final class AlbumRecoveryTests:XCTestCase {
  func testHeavenOnEarthSearchEntersMainListWithoutLosingOriginalAlbum() async throws {
    let source=AlbumPages([#"{"results":{"library-albums":{"data":[{"id":"l.heaven"}]}}}"#])
    let reader=MusicCloudLibrary(fetch:{try await source.fetch($0)})
    let found=try await reader.searchAlbums(RecoveredAlbum.self,term:"Heaven on Earth")
    let result=MusicCloudLibrary.combining([RecoveredAlbum(id:"l.existing")],local:found.items)
    XCTAssertEqual(result.map(\.id),["l.existing","l.heaven"])
    XCTAssertEqual(MusicCloudLibrary.combining(result,local:found.items).count,2)
  }
  func testSearchReadsEveryPageAndDeduplicatesLibraryIDs() async throws {
    let source=AlbumPages([#"{"results":{"library-albums":{"data":[{"id":"l.a"}],"next":"/v1/me/library/search?term=Heaven&types=library-albums&offset=25"}}}"#,#"{"results":{"library-albums":{"data":[{"id":"l.a"},{"id":"l.b"}]}}}"#])
    let result=try await MusicCloudLibrary(fetch:{try await source.fetch($0)}).searchAlbums(RecoveredAlbum.self,term:"Heaven")
    XCTAssertEqual(result.items.map(\.id),["l.a","l.b"]);XCTAssertEqual(result.pages,2)
  }
  func testSearchDoesNotReturnPartialCollectionOnNextPageFailure() async {
    let source=AlbumPages([#"{"results":{"library-albums":{"data":[{"id":"l.a"}],"next":"/v1/me/library/search?term=Heaven&types=library-albums&offset=25"}}}"#])
    do { _ = try await MusicCloudLibrary(fetch:{try await source.fetch($0)}).searchAlbums(RecoveredAlbum.self,term:"Heaven");XCTFail("Partial search must fail") }
    catch { XCTAssertEqual((error as? URLError)?.code,.timedOut) }
  }
  func testSearchRejectsNextPageChangingHostTermOrResource() async {
    for next in ["https://example.com/v1/me/library/search?term=Heaven&types=library-albums","/v1/me/library/search?term=Other&types=library-albums","/v1/me/library/search?term=Heaven&types=albums","/v1/catalog/it/search?term=Heaven&types=library-albums"] {
      let body=try! JSONSerialization.data(withJSONObject:["results":["library-albums":["data":[],"next":next]]])
      let source=AlbumPages([String(data:body,encoding:.utf8)!])
      do { _ = try await MusicCloudLibrary(fetch:{try await source.fetch($0)}).searchAlbums(RecoveredAlbum.self,term:"Heaven");XCTFail("Unsafe next accepted") }
      catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
      let requests=await source.captured();XCTAssertEqual(requests.count,1)
    }
  }
  func testRememberedIDsAreRevalidatedWithPersonalLibraryEndpoint() async throws {
    let source=AlbumPages([#"{"data":[{"id":"l.heaven"}]}"#])
    let result=try await MusicCloudLibrary(fetch:{try await source.fetch($0)}).albumsByID(RecoveredAlbum.self,ids:["l.heaven","l.removed"],id:{$0.id})
    XCTAssertEqual(result.map(\.id),["l.heaven"])
    let requests=await source.captured();let request=try XCTUnwrap(requests.first)
    let url=try XCTUnwrap(URLComponents(url:request.url!,resolvingAgainstBaseURL:false))
    XCTAssertEqual(url.path,"/v1/me/library/albums")
    XCTAssertEqual(url.queryItems?.first?.value,"l.heaven,l.removed")
    XCTAssertEqual(request.cachePolicy,.reloadIgnoringLocalCacheData)
  }
  func testInvalidOrCatalogIDsCannotBeRestoredAsLibraryAlbums() {
    XCTAssertEqual(MusicCloudLibrary.libraryAlbumIDs(["123","i.song","l.","l.a/b","l.ok","l.ok","l.a?token=secret","l.other"]),["l.ok","l.other"])
  }
  func testRestoreRejectsUnexpectedIDAndAuthorizationFailure() async {
    let source=AlbumPages([#"{"data":[{"id":"l.unrequested"}]}"#])
    do { _ = try await MusicCloudLibrary(fetch:{try await source.fetch($0)}).albumsByID(RecoveredAlbum.self,ids:["l.heaven"],id:{$0.id});XCTFail("Unexpected resource") }
    catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
    do { _ = try await MusicCloudLibrary(fetch:{_ in .init(data:Data(#"{"data":[]}"#.utf8),status:403)}).albumsByID(RecoveredAlbum.self,ids:["l.heaven"],id:{$0.id});XCTFail("Authorization failure") }
    catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
  }
  func testEmptyRememberedIDsMakesNoRequest() async throws {
    let source=AlbumPages([])
    let result=try await MusicCloudLibrary(fetch:{try await source.fetch($0)}).albumsByID(RecoveredAlbum.self,ids:[],id:{$0.id})
    XCTAssertTrue(result.isEmpty);let requests=await source.captured();XCTAssertTrue(requests.isEmpty)
  }
}

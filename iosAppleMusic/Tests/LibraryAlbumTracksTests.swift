import XCTest
@testable import LyricsContract

private struct OwnedTrack: Decodable, Identifiable, Sendable { let id: String }
private actor TrackPages {
  let pages: [String]
  var calls: [URLRequest] = []
  init(_ pages: [String]) { self.pages = pages }
  func fetch(_ request: URLRequest) throws -> MusicCloudLibrary.Response {
    calls.append(request)
    guard calls.count <= pages.count else { throw URLError(.timedOut) }
    return .init(data: Data(pages[calls.count - 1].utf8), status: 200)
  }
  func requests() -> [URLRequest] { calls }
}
final class LibraryAlbumTracksTests: XCTestCase {
  func testOwnedTracksKeepLibraryIDsAcrossEveryPageAndSkipMusicVideos() async throws {
    let pages = TrackPages([
      #"{"data":[{"id":"i.one","type":"library-songs"},{"id":"i.video","type":"library-music-videos"}],"next":"/v1/me/library/albums/l.owned/tracks?offset=100"}"#,
      #"{"data":[{"id":"i.one","type":"library-songs"},{"id":"i.two","type":"library-songs"}]}"#])
    let result = try await MusicCloudLibrary(fetch: { try await pages.fetch($0) }).albumTracks(OwnedTrack.self, albumID: "l.owned")
    XCTAssertEqual(result.items.map(\.id), ["i.one", "i.two"]); XCTAssertEqual(result.pages, 2)
    let requests = await pages.requests()
    XCTAssertEqual(requests.first?.url?.path, "/v1/me/library/albums/l.owned/tracks")
  }
  func testFailedContinuationDoesNotPublishHalfAnAlbum() async {
    let pages = TrackPages([#"{"data":[{"id":"i.one","type":"library-songs"}],"next":"?offset=100"}"#])
    do {
      _ = try await MusicCloudLibrary(fetch: { try await pages.fetch($0) }).albumTracks(OwnedTrack.self, albumID: "l.owned")
      XCTFail("Must fail atomically")
    } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
  }
  func testCatalogAlbumOrChangedRelationshipCannotBeUsedAsPersonalSongs() async {
    let pages = TrackPages([])
    do {
      _ = try await MusicCloudLibrary(fetch: { try await pages.fetch($0) }).albumTracks(OwnedTrack.self, albumID: "123")
      XCTFail("Catalog ID is not an owned album ID")
    } catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
    let calls = await pages.requests(); XCTAssertTrue(calls.isEmpty)
    for next in ["/v1/catalog/it/albums/123/tracks", "/v1/me/library/albums/l.other/tracks", "https://example.org/v1/me/library/albums/l.owned/tracks"] {
      let body = "{\"data\":[],\"next\":\"\(next)\"}"
      do {
        _ = try await MusicCloudLibrary(fetch: { _ in .init(data: Data(body.utf8), status: 200) }).albumTracks(OwnedTrack.self, albumID: "l.owned")
        XCTFail("Changed source accepted")
      } catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
    }
  }
  func testCatalogSongsOrMalformedResourcesAreNotSilentlyTreatedAsOwnedTracks() async {
    for body in [#"{"data":[{"id":"42","type":"songs"}]}"#, #"{"data":[{"id":"i.one"}]}"#] {
      do {
        _ = try await MusicCloudLibrary(fetch: { _ in .init(data: Data(body.utf8), status: 200) }).albumTracks(OwnedTrack.self, albumID: "l.owned")
        XCTFail("Not a valid library track")
      } catch { XCTAssertTrue(error is MusicCloudLibrary.LoadError) }
    }
  }
}

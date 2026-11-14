import XCTest
@testable import LyricsContract

final class BrowseArtworkTests:XCTestCase {
  func testMissingArtistCoverUsesExactPersonalCatalogRelationship() throws {
    let source=try BrowseArtworkRequest.identity("r:r.owned")
    let request=try BrowseArtworkRequest.request(source,country:"IT",catalogMapping:true)
    XCTAssertEqual(request.url?.path,"/v1/me/library/artists/r.owned/catalog")
    let mapped=try XCTUnwrap(BrowseArtworkRequest.catalogIdentity(Data(#"{"data":[{"id":"42","type":"artists"}]}"#.utf8),status:200,source:source))
    XCTAssertEqual(try BrowseArtworkRequest.request(mapped,country:"IT").url?.path,"/v1/catalog/it/artists/42")
    let data=Data(#"{"data":[{"id":"42","type":"artists","attributes":{"artwork":{"url":"https://is1-ssl.mzstatic.com/image/thumb/artist/{w}x{h}{c}.{f}?signed=preserved"}}}]}"#.utf8)
    let image=try XCTUnwrap(BrowseArtworkRequest.artwork(data,status:200,identity:mapped))
    XCTAssertEqual(image.path,"/image/thumb/artist/600x600bb.jpg")
    XCTAssertEqual(image.query,"signed=preserved")
  }
  func testSongAlbumPlaylistAndArtistNamespacesRemainSeparate() throws {
    for (key,path) in [("s:i.upload","/v1/me/library/songs/i.upload"),("a:l.album","/v1/me/library/albums/l.album"),("p:p.private","/v1/me/library/playlists/p.private"),("p:pl.catalog","/v1/catalog/it/playlists/pl.catalog"),("r:42","/v1/catalog/it/artists/42")] {
      XCTAssertEqual(try BrowseArtworkRequest.request(BrowseArtworkRequest.identity(key),country:"it").url?.path,path)
    }
  }
  func testWrongArtistOrResourceCannotSupplyAnotherItemsCover() throws {
    let identity=try BrowseArtworkRequest.identity("r:42")
    for data in [#"{"data":[{"id":"99","type":"artists"}]}"#,#"{"data":[{"id":"42","type":"songs"}]}"#,#"{"data":[],"errors":[]}"#] {
      XCTAssertThrowsError(try BrowseArtworkRequest.artwork(Data(data.utf8),status:200,identity:identity))
    }
    let source=try BrowseArtworkRequest.identity("r:r.owned")
    XCTAssertThrowsError(try BrowseArtworkRequest.catalogIdentity(Data(#"{"data":[{"id":"42","type":"songs"}]}"#.utf8),status:200,source:source))
  }
  func testAbsentImagesAndUnmatchedLocalArtistsDoNotInventArtwork() throws {
    let identity=try BrowseArtworkRequest.identity("r:42")
    XCTAssertNil(try BrowseArtworkRequest.artwork(Data(#"{"data":[{"id":"42","type":"artists","attributes":{"name":"Same name"}}]}"#.utf8),status:200,identity:identity))
    XCTAssertNil(try BrowseArtworkRequest.catalogIdentity(Data(#"{"data":[]}"#.utf8),status:200,source:BrowseArtworkRequest.identity("r:r.local")))
  }
  func testMalformedIDsUntrustedImagesAndHTTPFailuresAreRejected() throws {
    for id in ["r:..","r:42/other","r:42?token=secret","unknown:42","r:"] {XCTAssertThrowsError(try BrowseArtworkRequest.identity(id))}
    let identity=try BrowseArtworkRequest.identity("r:42")
    let data=Data(#"{"data":[{"id":"42","type":"artists","attributes":{"artwork":{"url":"https://example.org/image.jpg"}}}]}"#.utf8)
    XCTAssertThrowsError(try BrowseArtworkRequest.artwork(data,status:200,identity:identity))
    XCTAssertThrowsError(try BrowseArtworkRequest.artwork(Data(#"{"data":[]}"#.utf8),status:403,identity:identity))
  }
}

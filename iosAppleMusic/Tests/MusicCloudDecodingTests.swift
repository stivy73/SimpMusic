#if canImport(MusicKit)
import XCTest
import MusicKit
@testable import LyricsContract
final class MusicCloudDecodingTests: XCTestCase {
  func testAlbumTrackRecoveryPreservesActualLibrarySongPlaybackParameters() async throws {
    let data = Data(#"{"data":[{"id":"i.owned","type":"library-songs","attributes":{"name":"Owned recording","artistName":"Artist","albumName":"Owned album","durationInMillis":180000,"playParams":{"id":"i.owned","kind":"song","isLibrary":true}}}]}"#.utf8)
    let result = try await MusicCloudLibrary(fetch: { _ in .init(data: data, status: 200) }).albumTracks(Song.self, albumID: "l.owned")
    let song = try XCTUnwrap(result.items.first)
    XCTAssertEqual(song.id.rawValue, "i.owned")
    let parameters = try XCTUnwrap(song.playParameters)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
    XCTAssertEqual(fields["id"] as? String, "i.owned")
    XCTAssertEqual(fields["isLibrary"] as? Bool, true)
  }
  func testLibraryAlbumKeepsItsLibraryIdentityAndPlaybackParameters() async throws {
    let data = Data(#"{"data":[{"id":"l.fixture","type":"library-albums","attributes":{"name":"Fixture album","artistName":"Fixture artist","trackCount":2,"genreNames":[],"releaseDate":"2020-01-01","playParams":{"id":"l.fixture","kind":"album","isLibrary":true}}}]}"#.utf8)
    let result = try await MusicCloudLibrary(fetch:{ _ in .init(data:data,status:200) }).load(Album.self,resource:.albums)
    XCTAssertEqual(result.items.first?.id.rawValue,"l.fixture")
    XCTAssertEqual(result.items.first?.title,"Fixture album")
    XCTAssertNotNil(result.items.first?.playParameters)
  }
  func testLibraryPlaylistAndSongDecodeWithoutChangingTheirPlayParameters() async throws {
    let song = Data(#"{"data":[{"id":"i.fixture","type":"library-songs","attributes":{"name":"Fixture song","artistName":"Fixture artist","albumName":"Fixture album","durationInMillis":180000,"playParams":{"id":"i.fixture","kind":"song","isLibrary":true}}}]}"#.utf8)
    let songs = try await MusicCloudLibrary(fetch:{ _ in .init(data:song,status:200) }).load(Song.self,resource:.songs)
    XCTAssertEqual(songs.items.first?.id.rawValue,"i.fixture"); XCTAssertNotNil(songs.items.first?.playParameters)
    let playlist = Data(#"{"data":[{"id":"p.fixture","type":"library-playlists","attributes":{"name":"Fixture playlist","hasCatalog":false,"canEdit":true,"playParams":{"id":"p.fixture","kind":"playlist","isLibrary":true}}}]}"#.utf8)
    let playlists = try await MusicCloudLibrary(fetch:{ _ in .init(data:playlist,status:200) }).load(Playlist.self,resource:.playlists)
    XCTAssertEqual(playlists.items.first?.id.rawValue,"p.fixture"); XCTAssertNotNil(playlists.items.first?.playParameters)
  }
}
#endif

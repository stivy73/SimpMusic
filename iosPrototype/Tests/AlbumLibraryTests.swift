import XCTest
@testable import PrototypeCore

@MainActor
final class AlbumLibraryTests: XCTestCase {
  private let account = YouTubeSession(cookies: "SAPISID=fixture", identity: "A", clientVersion: "test")
  private let album = LibraryAlbum(id: "MPREalbum", title: "Album", artist: "Artist", artwork: nil)
  private var detail: AlbumDetail {
    AlbumDetail(album: album, songs: ["a", "b"].map {
      PlaybackTrack(id: $0, title: $0, artist: "Artist", artwork: nil)
    }, audioPlaylistID: "OLAK5uy_album")
  }
  private actor Writes {
    var events: [String] = []
    func record(_ value: String) { events.append(value) }
  }

  func testAlbumHeartDoesNotRequireAllTrackLikesToReflectConfirmedSave() async {
    let writes = Writes()
    let model = LibraryModel(session: account, save: { _ in }, fetch: { _ in [] },
      fetchCollection: { _, _ in [] }, rateSong: { _, id, _ in
        await writes.record(id)
        if id == "b" { throw LibraryError.http(403) }
      }, saveAlbum: { _, id in await writes.record(id) })
    await model.saveAlbumAndLikeTracks(detail)
    XCTAssertTrue(model.isAlbumSaved(album.id))
    XCTAssertTrue(model.isLiked("a"))
    XCTAssertFalse(model.isLiked("b"))
    XCTAssertTrue(model.syncError?.contains("Album salvato") == true)
    XCTAssertTrue(model.pendingAlbumSaves.isEmpty)
    let events = await writes.events
    XCTAssertEqual(events, ["OLAK5uy_album", "a", "b"])
  }

  func testSavingAlbumAndTracksIsConfirmedAndIdempotent() async {
    let writes = Writes()
    let model = LibraryModel(session: account, save: { _ in }, fetch: { _ in [] },
      fetchCollection: { _, _ in [] }, rateSong: { _, id, _ in await writes.record(id) },
      saveAlbum: { _, id in await writes.record(id) })
    await model.saveAlbumAndLikeTracks(detail)
    await model.saveAlbumAndLikeTracks(detail)
    XCTAssertEqual(model.albums.map(\.id), [album.id])
    XCTAssertTrue(detail.songs.allSatisfy { model.isLiked($0.id) })
    XCTAssertNil(model.syncError)
    let events = await writes.events
    XCTAssertEqual(events, ["OLAK5uy_album", "a", "b"])
  }

  func testAlbumRejectionDoesNotInsertAlbumOrLikeTracks() async {
    let writes = Writes()
    let model = LibraryModel(session: account, save: { _ in }, fetch: { _ in [] },
      fetchCollection: { _, _ in [] }, rateSong: { _, id, _ in await writes.record(id) },
      saveAlbum: { _, _ in throw LibraryError.rejected })
    await model.saveAlbumAndLikeTracks(detail)
    XCTAssertFalse(model.isAlbumSaved(album.id))
    XCTAssertTrue(model.pendingAlbumSaves.isEmpty)
    XCTAssertNotNil(model.syncError)
    let events = await writes.events
    XCTAssertTrue(events.isEmpty)
  }

  func testMissingPlaylistAndSignedOutCannotWrite() async {
    let writes = Writes()
    let model = LibraryModel(session: account, save: { _ in }, fetch: { _ in [] },
      fetchCollection: { _, _ in [] }, rateSong: { _, id, _ in await writes.record(id) },
      saveAlbum: { _, id in await writes.record(id) })
    await model.saveAlbumAndLikeTracks(AlbumDetail(album: album, songs: detail.songs))
    XCTAssertFalse(model.isAlbumSaved(album.id))
    XCTAssertNotNil(model.syncError)
    model.disconnect()
    await model.saveAlbumAndLikeTracks(detail)
    XCTAssertTrue(model.showLogin)
    let events = await writes.events
    XCTAssertTrue(events.isEmpty)
  }

  func testLateAlbumConfirmationCannotPopulateAnotherAccount() async {
    let writes = Writes()
    let model = LibraryModel(session: account, save: { _ in }, fetch: { _ in [] },
      fetchCollection: { _, _ in [] }, rateSong: { _, id, _ in await writes.record(id) },
      saveAlbum: { _, _ in try? await Task.sleep(for: .milliseconds(40)) })
    let detail = self.detail
    let task = Task { await model.saveAlbumAndLikeTracks(detail) }
    while model.pendingAlbumSaves.isEmpty { await Task.yield() }
    model.connect(YouTubeSession(cookies: "SAPISID=other", identity: "B", clientVersion: "test"))
    await task.value
    XCTAssertTrue(model.albums.isEmpty)
    XCTAssertTrue(model.pendingAlbumSaves.isEmpty)
    XCTAssertNil(model.syncError)
    let events = await writes.events
    XCTAssertTrue(events.isEmpty)
  }

  func testStaleAlbumRefreshCannotEraseNewSaveAndRepeatedTapIsIgnored() async {
    let writes = Writes()
    let model = LibraryModel(session: account, save: { _ in }, fetch: { _ in
      try? await Task.sleep(for: .milliseconds(80))
      return []
    }, fetchCollection: { _, _ in [] }, rateSong: { _, id, _ in await writes.record(id) },
      saveAlbum: { _, id in
        await writes.record(id)
        try await Task.sleep(for: .milliseconds(30))
      })
    model.refresh()
    let detail = self.detail
    let task = Task { await model.saveAlbumAndLikeTracks(detail) }
    while model.pendingAlbumSaves.isEmpty { await Task.yield() }
    XCTAssertFalse(model.isAlbumSaved(album.id))
    await model.saveAlbumAndLikeTracks(detail)
    await task.value
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertTrue(model.isAlbumSaved(album.id))
    XCTAssertFalse(model.loading)
    let events = await writes.events
    XCTAssertEqual(events, ["OLAK5uy_album", "a", "b"])
  }
}

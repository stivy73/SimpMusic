import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

@MainActor
final class RemoteLibraryTests: XCTestCase {
  private let account = YouTubeSession(
    cookies: "SAPISID=test", identity: "A", clientVersion: "test")
  private func song(_ id: String) -> DiscoveryItem {
    DiscoveryItem(kind: .song, mediaId: id, title: id, subtitle: "Artist", artwork: nil)
  }
  private func model(
    fetch: @escaping LibraryModel.FetchCollection,
    rate: @escaping LibraryModel.RateSong = { _, _, _ in }
  ) -> LibraryModel {
    LibraryModel(
      session: account, save: { _ in }, fetch: { _ in [] }, fetchCollection: fetch, rateSong: rate)
  }

  func testImportLikesIsIdempotentAndConfirmsOnlyAcknowledgedItems() async {
    actor Writes {
      var ids: [String] = []
      func write(_ id: String, liked: Bool) throws {
        if id == "failure" { throw LibraryError.http(403) }
        if liked { ids.append(id) }
      }
    }
    let writes = Writes()
    let library = model(
      fetch: { _, _ in
        [
          DiscoveryItem(
            kind: .song, mediaId: "existing", title: "existing", subtitle: "Artist", artwork: nil)
        ]
      },
      rate: { _, id, liked in try await writes.write(id, liked: liked) })
    var confirmed: [String] = []
    await library.importLikes([
      song("existing"), song("new"), song("new"), song("failure"), song("later"),
    ]) {
      confirmed.append($0.mediaId)
    }
    XCTAssertEqual(confirmed, ["existing", "new"])
    let ids = await writes.ids
    XCTAssertEqual(ids, ["new"])
    XCTAssertTrue(library.isLiked("existing"))
    XCTAssertTrue(library.isLiked("new"))
    XCTAssertFalse(library.isLiked("failure"))
    XCTAssertFalse(library.isLiked("later"))
    XCTAssertTrue(library.pendingLikes.isEmpty)
    XCTAssertNotNil(library.syncError)
    let success = await library.setLike(song("new"), liked: true)
    XCTAssertTrue(success)
    let repeated = await writes.ids
    XCTAssertEqual(repeated, ["new"])
  }

  func testAccountChangeDuringImportDoesNotAcknowledgeOrTouchNewAccount() async {
    let library = model(
      fetch: { _, _ in [] },
      rate: { _, _, _ in
        try await Task.sleep(for: .milliseconds(80))
      })
    var confirmed = 0
    let task = Task {
      await library.importLikes([song("new"), song("later")]) { _ in confirmed += 1 }
    }
    while !library.pendingLikes.contains("new") { await Task.yield() }
    library.connect(YouTubeSession(cookies: "SAPISID=other", identity: "B", clientVersion: "test"))
    await task.value
    XCTAssertEqual(confirmed, 0)
    XCTAssertFalse(library.isLiked("new"))
    XCTAssertTrue(library.pendingLikes.isEmpty)
  }

  func testCollectionsUseDifferentAccountEndpoints() {
    XCTAssertEqual(RemoteLibraryKind.songs.browseID, "FEmusic_liked_videos")
    XCTAssertEqual(RemoteLibraryKind.likes.browseID, "VLLM")
    XCTAssertEqual(RemoteLibraryKind.playlists.browseID, "FEmusic_liked_playlists")
    XCTAssertEqual(RemoteLibraryKind.artists.browseID, "FEmusic_library_corpus_artists")
  }

  func testAllPagesDeduplicateAndKeepOrder() async throws {
    let result = try await RemoteLibraryCollection.completed(kind: .likes) { token in
      try await HomeFixture.page(
        token == nil ? ["song1", "song2"] : ["song2", "song3"],
        next: token == nil ? "next" : nil)
    }
    XCTAssertEqual(result.map(\.mediaId), ["song1", "song2", "song3"])
  }

  func testRepeatedContinuationIsAnErrorNotASuccessfulPartialLibrary() async {
    do {
      _ = try await RemoteLibraryCollection.completed(kind: .likes) { _ in
        try await HomeFixture.page(["song1"], next: "repeated")
      }
      XCTFail("Repeated token was accepted")
    } catch LibraryError.repeatedContinuation {} catch { XCTFail("Unexpected error: \(error)") }
  }

  func testFailedPageDoesNotExposePartialLikesOrAllowWrite() async {
    actor Counter {
      var count = 0
      func add() { count += 1 }
    }
    let counter = Counter()
    let model = model(
      fetch: { _, kind in
        try await RemoteLibraryCollection.completed(kind: kind) { token in
          if token != nil { throw URLError(.notConnectedToInternet) }
          return try await HomeFixture.page(["song1"], next: "more")
        }
      }, rate: { _, _, _ in await counter.add() })
    await model.load(.likes)
    XCTAssertFalse(model.state(.likes).loaded)
    XCTAssertTrue(model.state(.likes).items.isEmpty)
    XCTAssertNotNil(model.state(.likes).error)
    await model.toggleLike(song("song1"))
    let writes = await counter.count
    XCTAssertEqual(writes, 0)
    XCTAssertNotNil(model.syncError)
  }

  func testLeavingScreenDoesNotCancelSharedLikesLoad() async {
    let library = model(fetch: { _, _ in
      try await Task.sleep(for: .milliseconds(40))
      return []
    })
    let screen = Task { await library.load(.likes) }
    while !library.state(.likes).loading { await Task.yield() }
    // A SwiftUI .task is cancelled when its screen disappears. This is a
    // model-owned collection request, also used by the album/player hearts.
    screen.cancel()
    await screen.value
    XCTAssertTrue(library.state(.likes).loaded)
    XCTAssertNil(library.state(.likes).error)
    await library.toggleLike(song("album-track"))
    XCTAssertTrue(library.isLiked("album-track"))
    XCTAssertNil(library.syncError)
  }

  func testLikeFailureReportsOriginalCollectionError() async {
    let library = model(fetch: { _, _ in throw LibraryError.http(403) })
    await library.toggleLike(song("album-track"))
    XCTAssertTrue(library.syncError?.contains("HTTP 403") == true)
    XCTAssertFalse(library.isLiked("album-track"))
  }

  func testConfirmedLikeAndUnlikeUpdateCollection() async {
    actor Writes {
      var values: [Bool] = []
      func add(_ value: Bool) { values.append(value) }
    }
    let writes = Writes()
    let model = model(fetch: { _, _ in [] }, rate: { _, _, liked in await writes.add(liked) })
    await model.toggleLike(song("s"))
    XCTAssertTrue(model.isLiked("s"))
    XCTAssertTrue(model.pendingLikes.isEmpty)
    await model.toggleLike(song("s"))
    XCTAssertFalse(model.isLiked("s"))
    let values = await writes.values
    XCTAssertEqual(values, [true, false])
  }

  func testPendingLikeIsUnconfirmedAndRepeatedTapCannotReverseIt() async {
    actor Gate {
      var writes = 0
      var finished = false
      var continuation: CheckedContinuation<Void, Never>?
      func write() async {
        writes += 1
        if !finished { await withCheckedContinuation { continuation = $0 } }
      }
      func finish() {
        finished = true
        continuation?.resume()
        continuation = nil
      }
    }
    let gate = Gate()
    let library = model(fetch: { _, _ in [] }, rate: { _, _, _ in await gate.write() })
    let write = Task { await library.toggleLike(song("s")) }
    while library.pendingLikes.isEmpty { await Task.yield() }
    XCTAssertFalse(library.isLiked("s"))
    await library.toggleLike(song("s"))
    await gate.finish()
    await write.value
    XCTAssertTrue(library.isLiked("s"))
    XCTAssertTrue(library.pendingLikes.isEmpty)
    let writes = await gate.writes
    XCTAssertEqual(writes, 1)
  }

  func testFailedUnlikeKeepsExistingLike() async {
    let existing = song("s")
    let model = model(
      fetch: { _, _ in [existing] }, rate: { _, _, _ in throw LibraryError.http(403) })
    await model.toggleLike(existing)
    XCTAssertTrue(model.isLiked("s"))
    XCTAssertNotNil(model.syncError)
    XCTAssertTrue(model.pendingLikes.isEmpty)
  }

  func testLogoutAndSameAccountReconnectRejectLateMutation() async {
    let item = song("s")
    let model = model(
      fetch: { _, _ in [] },
      rate: { _, _, _ in
        try? await Task.sleep(for: .milliseconds(100))
      })
    let write = Task { await model.toggleLike(item) }
    while model.pendingLikes.isEmpty { await Task.yield() }
    model.disconnect()
    model.connect(account)
    await model.load(.likes)
    await write.value
    XCTAssertFalse(model.isLiked("s"))
    XCTAssertNil(model.syncError)
    XCTAssertTrue(model.pendingLikes.isEmpty)
  }

  func testAccountSwitchClearsEveryCollectionAndRejectsLatePages() async {
    let existing = song("s")
    let model = model(fetch: { session, _ in
      if session.identity == "A" { try? await Task.sleep(for: .milliseconds(80)) }
      return [existing]
    })
    let load = Task { await model.load(.likes) }
    while !model.state(.likes).loading { await Task.yield() }
    model.disconnect()
    await load.value
    XCTAssertTrue(model.collections.isEmpty)
    XCTAssertNil(model.session)
  }

  func testAlbumRefreshDoesNotClearOtherCollections() async {
    let existing = song("s")
    let model = model(fetch: { _, _ in [existing] })
    await model.load(.likes)
    await model.reload()
    XCTAssertTrue(model.isLiked("s"))
    XCTAssertTrue(model.state(.likes).loaded)
  }

  func testReconnectingSameSessionInvalidatesLoadsAndPublishesANewAccountRevision() async {
    actor Reads {
      var count = 0
      func next() -> Int { count += 1; return count }
    }
    let reads = Reads()
    let account = self.account
    let model = model(fetch: { _, _ in
      let n = await reads.next()
      return [DiscoveryItem(kind: .playlist, mediaId: "VL\(n)", title: "Playlist \(n)", subtitle: "", artwork: nil)]
    })
    await model.load(.playlists)
    let previous = model.accountRevision
    model.showLogin = true
    model.connect(account)
    XCTAssertEqual(model.session, account)
    XCTAssertNotEqual(model.accountRevision, previous)
    XCTAssertFalse(model.showLogin)
    XCTAssertFalse(model.state(.playlists).loaded)
    await model.load(.playlists)
    XCTAssertEqual(model.state(.playlists).items.map(\.mediaId), ["VL2"])
    XCTAssertNil(model.state(.playlists).error)
  }

  func testWrappedPlaylistGridAndEmptyMessagesUseTheSameLibraryEnvelope() async throws {
    for rows in [
      [["gridRenderer": ["items": [HomeFixture.item("VLpersonal")]]]],
      [["messageRenderer": ["text": ["simpleText": "No playlists in your library"]]]],
    ] as [[[String: Any]]] {
      let data = try JSONSerialization.data(withJSONObject: ["contents": [
        "singleColumnBrowseResultsRenderer": ["tabs": [["tabRenderer": ["selected": true,
          "content": ["sectionListRenderer": ["contents": [["itemSectionRenderer": ["contents": rows]]]]]]]]]]])
      let normalized = try LibraryBrowseEnvelope.normalize(data)
      let page = try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: normalized, strictItems: true))
      let items = page.shelves.flatMap(\.items)
      XCTAssertEqual(items.map(\.mediaId), rows.first?["gridRenderer"] != nil ? ["VLpersonal"] : [])
    }
  }

  func testLibraryGridContinuationAndCreateTile() async throws {
    let json: [String: Any] = [
      "contents": [
        "singleColumnBrowseResultsRenderer": [
          "tabs": [
            [
              "tabRenderer": [
                "selected": true,
                "content": [
                  "sectionListRenderer": [
                    "contents": [
                      [
                        "gridRenderer": [
                          "items": [
                            [
                              "musicTwoRowItemRenderer": [
                                "navigationEndpoint": ["createPlaylistEndpoint": [:]]
                              ]
                            ],
                            HomeFixture.item("VLpersonal"),
                          ], "continuations": [["nextContinuationData": ["continuation": "page2"]]],
                        ]
                      ]
                    ]
                  ]
                ],
              ]
            ]
          ]
        ]
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    let page = try await HomePage(
      YouTubeMusicClient().decodeDiscoveryPage(from: data, strictItems: true))
    XCTAssertEqual(page.shelves.flatMap(\.items).map(\.mediaId), ["VLpersonal"])
    XCTAssertEqual(page.continuation, "page2")
  }

  func testLikedPlaylistHeadersKeepTracksAndContinuation() async throws {
    let header: [String: Any] = ["title": HomeFixture.text("Mi piace"),
      "menu": ["privateMenuRenderer": ["value": "DO_NOT_READ"]]]
    for wrapper in [
      ["musicResponsiveHeaderRenderer": header],
      ["musicEditablePlaylistDetailHeaderRenderer": ["header": ["musicResponsiveHeaderRenderer": header]]],
    ] as [[String: Any]] {
      for twoColumns in [false, true] {
        let trackSection: [String: Any] = [
          "musicPlaylistShelfRenderer": [
            "contents": [HomeFixture.item("song1"), HomeFixture.item("song2")],
            "continuations": [["nextContinuationData": ["continuation": "page2"]]],
          ]
        ]
        let main: [String: Any] = [
          "sectionListRenderer": ["contents": twoColumns ? [wrapper] : [wrapper, trackSection]]
        ]
        var browse: [String: Any] = [
          "tabs": [["tabRenderer": ["selected": true, "content": main]]]
        ]
        if twoColumns {
          browse["secondaryContents"] = ["sectionListRenderer": ["contents": [trackSection]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["contents": [
          twoColumns ? "twoColumnBrowseResultsRenderer" : "singleColumnBrowseResultsRenderer": browse
        ]])
        let result = try await RemoteLibraryCollection.completed(kind: .likes) { token in
          if token != nil { return try await HomeFixture.page(["song2", "song3"]) }
          return try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(
            from: LibraryBrowseEnvelope.normalize(data), strictItems: true))
        }
        XCTAssertEqual(result.map(\.mediaId), ["song1", "song2", "song3"])
      }
    }
  }

  func testHeaderWithoutTrackCollectionIsNotAnEmptyLikesList() async throws {
    let data = try HomeFixture.data(rows: [["musicResponsiveHeaderRenderer": ["title": HomeFixture.text("Mi piace")]]])
    let normalized = try LibraryBrowseEnvelope.normalize(data)
    do {
      _ = try await YouTubeMusicClient().decodeDiscoveryPage(from: normalized, strictItems: true)
      XCTFail("Header-only response was accepted as a complete empty collection")
    } catch {}
  }

  func testUnknownRendererReportsSchemaNameWithoutValues() throws {
    let data = try HomeFixture.data(rows: [["newLibraryShelfRenderer": ["token": "PRIVATE_TOKEN"]]])
    XCTAssertThrowsError(try LibraryBrowseEnvelope.normalize(data)) { error in
      XCTAssertTrue(error.localizedDescription.contains("newLibraryShelfRenderer"))
      XCTAssertFalse(error.localizedDescription.contains("PRIVATE_TOKEN"))
    }
  }

  func testUnknownSecondaryColumnCannotBecomePartialLikes() throws {
    let data = try JSONSerialization.data(withJSONObject: ["contents": ["twoColumnBrowseResultsRenderer": [
      "tabs": [["tabRenderer": ["selected": true, "content": ["sectionListRenderer": ["contents": [
        ["musicResponsiveHeaderRenderer": ["title": HomeFixture.text("Mi piace")]]]]]]]],
      "secondaryContents": ["sectionListRenderer": ["contents": [
        ["musicPlaylistShelfRenderer": ["contents": [HomeFixture.item("song1")]]],
        ["newLibraryShelfRenderer": ["token": "PRIVATE_TOKEN"]],
      ]]],
    ]]])
    XCTAssertThrowsError(try LibraryBrowseEnvelope.normalize(data)) { error in
      XCTAssertTrue(error.localizedDescription.contains("newLibraryShelfRenderer"))
    }
  }

  func testUnknownLibraryMediaIsNotSilentlyMarkedEmpty() async throws {
    let data = try HomeFixture.data(rows: [
      [
        "musicShelfRenderer": [
          "contents": [
            ["musicResponsiveListItemRenderer": ["unknown": "changed schema"]]
          ]
        ]
      ]
    ])
    do {
      _ = try await YouTubeMusicClient().decodeDiscoveryPage(from: data, strictItems: true)
      XCTFail("Unreadable song incorrectly accepted as an empty collection")
    } catch {}
  }
}

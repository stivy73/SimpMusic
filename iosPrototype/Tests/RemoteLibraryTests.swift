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
    let library = model(fetch: { _, _ in [DiscoveryItem(kind: .song, mediaId: "existing", title: "existing", subtitle: "Artist", artwork: nil)] },
      rate: { _, id, liked in try await writes.write(id, liked: liked) })
    var confirmed: [String] = []
    await library.importLikes([song("existing"), song("new"), song("new"), song("failure"), song("later")]) {
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
    let library = model(fetch: { _, _ in [] }, rate: { _, _, _ in
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

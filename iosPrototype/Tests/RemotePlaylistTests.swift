import Foundation
import XCTest

@testable import PrototypeCore

enum PlaylistFixture {
  static func row(_ video: String, set: String) -> [String: Any] {
    [
      "musicResponsiveListItemRenderer": [
        "playlistItemData": ["videoId": video, "playlistSetVideoId": set],
        "flexColumns": [
          ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text(video)]]
        ],
      ]
    ]
  }
  static func data(
    owned: Bool = true, rows: [[String: Any]], token: String? = nil, continuation: Bool = false
  ) throws -> Data {
    var shelf: [String: Any] = ["contents": rows]
    if let token { shelf["continuations"] = [["nextContinuationData": ["continuation": token]]] }
    let root: [String: Any] =
      continuation
      ? ["continuationContents": ["musicPlaylistShelfContinuation": shelf]]
      : [
        "header": owned ? ["musicEditablePlaylistDetailHeaderRenderer": [:]] : [:],
        "contents": [
          "singleColumnBrowseResultsRenderer": [
            "tabs": [
              [
                "tabRenderer": [
                  "selected": true,
                  "content": [
                    "sectionListRenderer": ["contents": [["musicPlaylistShelfRenderer": shelf]]]
                  ],
                ]
              ]
            ]
          ]
        ],
      ]
    return try JSONSerialization.data(withJSONObject: root)
  }
  static func playlist(owned: Bool = true) -> RemotePlaylist {
    RemotePlaylist(
      editable: owned,
      entries: ["a", "b", "c"].map { id in
        RemotePlaylistEntry(
          id: id,
          item: DiscoveryItem(
            kind: .song, mediaId: "same-video", title: id, subtitle: "", artwork: nil),
          setVideoID: id)
      })
  }
}

@MainActor
final class RemotePlaylistTests: XCTestCase {
  func testDuplicateSongsKeepTheirOccurrenceIDsAcrossPages() async throws {
    let result = try await RemotePlaylist.completed { token in
      try PlaylistFixture.data(
        owned: token == nil,
        rows: token == nil
          ? [PlaylistFixture.row("same", set: "one")] : [PlaylistFixture.row("same", set: "two")],
        token: token == nil ? "next" : nil, continuation: token != nil)
    }
    XCTAssertTrue(result.editable)
    XCTAssertEqual(result.entries.map(\.id), ["one", "two"])
    XCTAssertEqual(result.entries.map(\.item.mediaId), ["same", "same"])
  }
  func testReadOnlyPlaylistAndEmptyOwnedPlaylist() async throws {
    let readOnly = try await RemotePlaylist.completed { _ in
      try PlaylistFixture.data(owned: false, rows: [])
    }
    XCTAssertFalse(readOnly.editable)
    let owned = try await RemotePlaylist.completed { _ in try PlaylistFixture.data(rows: []) }
    XCTAssertTrue(owned.editable)
    XCTAssertTrue(owned.entries.isEmpty)
  }
  func testMovesUseOccurrenceIDsAndSupportLastPosition() throws {
    let entries = PlaylistFixture.playlist().entries
    XCTAssertEqual(
      try RemotePlaylist.moveAction(entries: entries, from: 0, to: 3),
      .move(setID: "a", before: nil))
    XCTAssertEqual(
      try RemotePlaylist.moveAction(entries: entries, from: 2, to: 0),
      .move(setID: "c", before: "a"))
  }
  func testReadOnlyPlaylistNeverWritesAndFailedWriteKeepsEntries() async {
    let session = YouTubeSession(cookies: "SAPISID=test", identity: "A", clientVersion: "test")
    let model = RemotePlaylistModel(
      id: "VLtest", fetch: { _, _ in PlaylistFixture.playlist(owned: false) },
      edit: { _, _, _ in XCTFail("Read-only mutation") })
    await model.configure(session: session)
    let accepted = await model.apply(.add("song"))
    XCTAssertFalse(accepted)
    let failing = RemotePlaylistModel(
      id: "VLtest", fetch: { _, _ in PlaylistFixture.playlist() },
      edit: { _, _, _ in throw LibraryError.http(403) })
    await failing.configure(session: session)
    let saved = await failing.apply(.remove(videoID: "same-video", setID: "b"))
    XCTAssertFalse(saved)
    XCTAssertEqual(failing.detail?.entries.map(\.id), ["a", "b", "c"])
    XCTAssertNotNil(failing.error)
  }
}

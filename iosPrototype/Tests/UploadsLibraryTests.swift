import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

private enum UploadFixture {
  static let albumID = "FEmusic_library_privately_owned_release_detail_private"
  static let artistID = "FEmusic_library_privately_owned_artist_detail_private"
  static func run(_ text: String, id: String) -> [String: Any] {
    ["text": text, "navigationEndpoint": ["browseEndpoint": ["browseId": id]]]
  }
  static func row(_ id: String, menuID: Bool = true) -> [String: Any] {
    var row: [String: Any] = [
      "flexColumns": [
        [
          "musicResponsiveListItemFlexColumnRenderer": [
            "text": HomeFixture.text("My own recording")
          ]
        ],
        [
          "musicResponsiveListItemFlexColumnRenderer": [
            "text": ["runs": [run("My artist", id: artistID)]]
          ]
        ],
        [
          "musicResponsiveListItemFlexColumnRenderer": [
            "text": ["runs": [run("My album", id: albumID)]]
          ]
        ],
      ],
      "fixedColumns": [
        ["musicResponsiveListItemFixedColumnRenderer": ["text": HomeFixture.text("3:45")]]
      ],
      "thumbnail": HomeFixture.thumbnail,
    ]
    if menuID {
      row["menu"] = [
        "menuRenderer": [
          "items": [
            [
              "menuServiceItemRenderer": [
                "serviceEndpoint": ["queueAddEndpoint": ["queueTarget": ["videoId": id]]]
              ]
            ],
            [
              "menuServiceItemRenderer": [
                "serviceEndpoint": [
                  "musicDeletePrivatelyOwnedEntityCommand": ["entityId": "PRIVATE_ENTITY"]
                ]
              ]
            ],
          ]
        ]
      ]
    } else {
      row["playlistItemData"] = ["videoId": id]
    }
    return ["musicResponsiveListItemRenderer": row]
  }
  static func data(_ ids: [String], next: String? = nil, initial: Bool = true) throws -> Data {
    var shelf: [String: Any] = ["contents": ids.map { row($0) }]
    if let next { shelf["continuations"] = [["nextContinuationData": ["continuation": next]]] }
    return try JSONSerialization.data(
      withJSONObject: initial
        ? ["contents": ["sectionListRenderer": ["contents": [["musicShelfRenderer": shelf]]]]]
        : ["continuationContents": ["musicShelfContinuation": shelf]])
  }
}

final class UploadsLibraryTests: XCTestCase {
  func testMenuOnlyIDAndPrivateMetadataAreDecodedWithoutPublicPageTypes() async throws {
    for menuID in [true, false] {
      let data = try HomeFixture.data(rows: [
        ["musicShelfRenderer": ["contents": [UploadFixture.row("private-song", menuID: menuID)]]]
      ])
      let page = try await HomePage(
        YouTubeMusicClient().decodeDiscoveryPage(from: data, strictItems: true))
      let item = try XCTUnwrap(page.shelves.first?.items.first)
      XCTAssertEqual(item.mediaId, "private-song")
      XCTAssertEqual(item.title, "My own recording")
      XCTAssertEqual(item.subtitle, "My artist")
      XCTAssertEqual(item.albumTitle, "My album")
      XCTAssertEqual(item.albumBrowseID, UploadFixture.albumID)
      XCTAssertEqual(item.artistBrowseID, UploadFixture.artistID)
      XCTAssertEqual(item.durationSeconds, 225)
      XCTAssertEqual(item.isUploaded, true)
    }
  }

  func testEveryUploadsPageIsIncludedAndRemainsPrivate() async throws {
    XCTAssertEqual(RemoteLibraryKind.uploads.browseID, "FEmusic_library_privately_owned_tracks")
    XCTAssertEqual(
      RemoteLibraryKind.uploadAlbums.browseID, "FEmusic_library_privately_owned_releases")
    let items = try await RemoteLibraryCollection.completed(kind: .uploads) { token in
      let data = try UploadFixture.data(
        token == nil ? ["a", "b"] : ["b", "c"],
        next: token == nil ? "more" : nil, initial: token == nil)
      return try await HomePage(
        YouTubeMusicClient().decodeDiscoveryPage(
          from: LibraryBrowseEnvelope.normalize(data), strictItems: true))
    }
    XCTAssertEqual(items.map(\.mediaId), ["a", "b", "c"])
    XCTAssertTrue(items.allSatisfy { $0.isUploaded == true })
    let track = PlaybackTrack(items[0]).withAlbumArtwork(
      URL(string: "https://example.org/cover.jpg"))
    XCTAssertEqual(track.isUploaded, true)
    XCTAssertEqual(track.discoveryItem.isUploaded, true)
    let saved = try JSONDecoder().decode(PlaybackTrack.self, from: JSONEncoder().encode(track))
    XCTAssertEqual(saved.isUploaded, true)
    let legacy = Data(#"{"id":"old","title":"Old track","artist":"Artist"}"#.utf8)
    XCTAssertNil(try JSONDecoder().decode(PlaybackTrack.self, from: legacy).isUploaded)
  }

  func testPrivateAlbumAndAllItsTracksKeepTheirAccountRequirement() async throws {
    let tile: [String: Any] = [
      "musicTwoRowItemRenderer": [
        "title": HomeFixture.text("My album"),
        "subtitle": ["runs": [UploadFixture.run("My artist", id: UploadFixture.artistID)]],
        "navigationEndpoint": ["browseEndpoint": ["browseId": UploadFixture.albumID]],
        "thumbnailRenderer": HomeFixture.thumbnail,
      ]
    ]
    let data = try HomeFixture.data(rows: [["gridRenderer": ["items": [tile]]]])
    let albums = try await RemoteLibraryCollection.completed(kind: .uploadAlbums) { _ in
      try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: data, strictItems: true))
    }
    let album = try XCTUnwrap(albums.first)
    XCTAssertEqual(album.kind, .album)
    XCTAssertEqual(album.subtitle, "My artist")
    XCTAssertEqual(album.isUploaded, true)
    let fallback = LibraryAlbum(
      id: album.mediaId, title: album.title, artist: album.subtitle, artwork: album.artwork)
    let detail = try await AlbumDetail.completed(album: fallback) { _ in
      try UploadFixture.data(["a", "b"])
    }
    XCTAssertTrue(detail.album.isUploaded)
    XCTAssertEqual(detail.songs.map(\.id), ["a", "b"])
    XCTAssertTrue(detail.songs.allSatisfy { $0.isUploaded == true })
    // Personal albums are already owned; they must not send a commercial album-save operation.
    XCTAssertNil(detail.audioPlaylistID)
  }

  func testMissingOrInvalidAccountNeverFallsBackToPublicAudio() async throws {
    let invalid = YouTubeSession(
      cookies: "NO_AUTH=not-a-secret", identity: "test", clientVersion: "test")
    for session in [nil, invalid] {
      do {
        _ = try await YouTubeAudio().resolve(
          videoID: "private-song", session: session, accountOnly: true)
        XCTFail("Private audio resolved without a valid account")
      } catch let failure as AudioResolutionFailure {
        XCTAssertTrue(failure.networkDiagnostic.contains("Caricamento personale"))
        XCTAssertFalse(failure.resolutionReport.contains("PUBLIC_"))
      }
    }
    for kind in [RemoteLibraryKind.uploads, .uploadAlbums] {
      do {
        _ = try await HomeDiscovery(session: nil).libraryPage(kind: kind)
        XCTFail("Private collection requested without an account")
      } catch LibraryError.authentication {}
    }
  }
}

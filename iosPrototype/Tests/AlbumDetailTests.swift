import Foundation
import XCTest

@testable import PrototypeCore

private enum AlbumFixture {
  static let fallback = LibraryAlbum(
    id: "MPREalbum", title: "Titolo iniziale", artist: "Album • Artista • 1988", artwork: nil)
  static func song(_ id: String, duration: String = "3:00") -> [String: Any] {
    [
      "musicResponsiveListItemRenderer": [
        "playlistItemData": ["videoId": id],
        "flexColumns": [
          ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text(id)]],
          [
            "musicResponsiveListItemFlexColumnRenderer": [
              "text": [
                "runs": [
                  ["text": "Artista", "navigationEndpoint": HomeFixture.endpoint("UCartist")]
                ]
              ]
            ]
          ],
        ],
        "fixedColumns": [
          ["musicResponsiveListItemFixedColumnRenderer": ["text": HomeFixture.text(duration)]]
        ],
      ]
    ]
  }
  static func page(_ ids: [String], next: String? = nil, initial: Bool = true) throws -> Data {
    var shelf: [String: Any] = ["contents": ids.map { song($0) }]
    if let next { shelf["continuations"] = [["nextContinuationData": ["continuation": next]]] }
    var root: [String: Any]
    if initial {
      root = [
        "header": [
          "musicResponsiveHeaderRenderer": [
            "title": HomeFixture.text("Album completo"),
            "subtitle": HomeFixture.text("Album • 1988"),
            "straplineTextOne": [
              "runs": [["text": "Artista", "navigationEndpoint": HomeFixture.endpoint("UCartist")]]
            ],
            "thumbnail": HomeFixture.thumbnail,
            "description": [
              "musicDescriptionShelfRenderer": [
                "description": HomeFixture.text("La storia dell’album.")
              ]
            ],
          ]
        ],
        "contents": [
          "sectionListRenderer": [
            "contents": [
              ["musicPlaylistShelfRenderer": shelf],
              HomeFixture.shelf(["song-unrelated"], title: "Ti potrebbe piacere"),
            ]
          ]
        ],
      ]
    } else {
      root = ["continuationContents": ["musicPlaylistShelfContinuation": shelf]]
    }
    return try JSONSerialization.data(withJSONObject: root)
  }
}

final class AlbumDetailTests: XCTestCase {
  func testAlbumCoverIsChosenInsteadOfArtistAvatarInHeader() async throws {
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: AlbumFixture.page(["song-a"])) as? [String: Any])
    var wrapper = root["header"] as! [String: Any]
    var header = wrapper["musicResponsiveHeaderRenderer"] as! [String: Any]
    header["straplineThumbnail"] = [
      "musicThumbnailRenderer": [
        "thumbnail": ["thumbnails": [["url": "https://example.org/artist-face.jpg"]]]
      ]
    ]
    wrapper["musicResponsiveHeaderRenderer"] = header
    root["header"] = wrapper
    let data = try JSONSerialization.data(withJSONObject: root)
    let detail = try await AlbumDetail.completed(album: AlbumFixture.fallback) { _ in data }
    XCTAssertEqual(detail.album.artwork?.absoluteString, "https://example.org/art.jpg")
    XCTAssertEqual(detail.songs.first?.artwork, detail.album.artwork)
  }

  func testAlbumHeaderSuppliesArtistWhenTrackHasOnlyTitleAndDuration() async throws {
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: AlbumFixture.page(["song-a"])) as? [String: Any])
    var row = AlbumFixture.song("song-a")
    var renderer = row["musicResponsiveListItemRenderer"] as! [String: Any]
    renderer["flexColumns"] = Array((renderer["flexColumns"] as! [[String: Any]]).prefix(1))
    row["musicResponsiveListItemRenderer"] = renderer
    root["contents"] = [
      "sectionListRenderer": ["contents": [["musicPlaylistShelfRenderer": ["contents": [row]]]]]
    ]
    let data = try JSONSerialization.data(withJSONObject: root)
    let detail = try await AlbumDetail.completed(album: AlbumFixture.fallback) { _ in data }
    XCTAssertEqual(detail.songs.first?.artist, "Artista")
    XCTAssertEqual(detail.songs.first?.artistBrowseID, "UCartist")
    XCTAssertEqual(detail.songs.first?.artistReferences?.map(\.name), ["Artista"])
  }

  func testEveryArtistIdentifierSurvivesAlbumQueueAndSavedTrack() async throws {
    var root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: AlbumFixture.page(["song-a"])) as? [String: Any])
    var row = AlbumFixture.song("song-a")
    var renderer = row["musicResponsiveListItemRenderer"] as! [String: Any]
    var columns = renderer["flexColumns"] as! [[String: Any]]
    columns.append([
      "musicResponsiveListItemFlexColumnRenderer": [
        "text": [
          "runs": [
            ["text": "Secondo artista", "navigationEndpoint": HomeFixture.endpoint("UCsecond")]
          ]
        ]
      ]
    ])
    renderer["flexColumns"] = columns
    row["musicResponsiveListItemRenderer"] = renderer
    root["contents"] = [
      "sectionListRenderer": ["contents": [["musicPlaylistShelfRenderer": ["contents": [row]]]]]
    ]
    let data = try JSONSerialization.data(withJSONObject: root)
    let detail = try await AlbumDetail.completed(album: AlbumFixture.fallback) { _ in data }
    let song = try XCTUnwrap(detail.songs.first)
    XCTAssertEqual(song.artistReferences?.map(\.id), ["UCartist", "UCsecond"])
    XCTAssertEqual(song.artistBrowseID, "UCartist")
    XCTAssertEqual(PlaybackTrack(song.discoveryItem).artistReferences, song.artistReferences)
    let saved = try JSONDecoder().decode(PlaybackTrack.self, from: JSONEncoder().encode(song))
    XCTAssertEqual(saved.artistReferences, song.artistReferences)
  }

  func testMetadataNumberedTracksAndDurationsExcludeRecommendations() async throws {
    let result = try await AlbumDetail.completed(album: AlbumFixture.fallback) { _ in
      try AlbumFixture.page(["song-a", "song-b"])
    }
    XCTAssertEqual(result.album.title, "Album completo")
    XCTAssertEqual(result.album.artist, "Artista")
    XCTAssertEqual(result.year, "1988")
    XCTAssertEqual(result.description, "La storia dell’album.")
    XCTAssertEqual(result.songs.map(\.id), ["song-a", "song-b"])
    XCTAssertEqual(result.durationSeconds, 360)
    for song in result.songs {
      XCTAssertEqual(song.albumBrowseID, "MPREalbum")
      XCTAssertEqual(song.albumTitle, "Album completo")
      XCTAssertEqual(song.artistBrowseID, "UCartist")
      XCTAssertEqual(song.artwork, result.album.artwork)
    }
  }
  func testEveryPageAndRepeatedTrackOccurrencePreserveAlbumOrder() async throws {
    let result = try await AlbumDetail.completed(album: AlbumFixture.fallback) { token in
      try AlbumFixture.page(
        token == nil ? ["song-a", "song-b"] : ["song-a", "song-c"],
        next: token == nil ? "second" : nil, initial: token == nil)
    }
    XCTAssertEqual(result.songs.map(\.id), ["song-a", "song-b", "song-a", "song-c"])
    XCTAssertEqual(result.durationSeconds, 720)
  }
  func testRepeatedContinuationRejectsPartialAlbum() async {
    do {
      _ = try await AlbumDetail.completed(album: AlbumFixture.fallback) { token in
        try AlbumFixture.page(["song-a"], next: "repeated", initial: token == nil)
      }
      XCTFail("Repeated continuation accepted")
    } catch LibraryError.repeatedContinuation {} catch { XCTFail("Unexpected \(error)") }
  }
  func testFailedNextPageDoesNotReturnAnIncompleteDownloadList() async {
    do {
      _ = try await AlbumDetail.completed(album: AlbumFixture.fallback) { token in
        if token != nil { throw URLError(.notConnectedToInternet) }
        return try AlbumFixture.page(["song-a"], next: "second")
      }
      XCTFail("Partial album accepted")
    } catch {}
  }
  func testRecommendationsAloneAreNotAnAlbum() async {
    do {
      _ = try await AlbumDetail.completed(album: AlbumFixture.fallback) { _ in
        try HomeFixture.data(rows: [HomeFixture.shelf(["song-other"])])
      }
      XCTFail("Recommendation carousel accepted as track list")
    } catch {}
  }
  func testUnknownDurationIsNotPresentedAsACompleteTotal() {
    let result = AlbumDetail(
      album: AlbumFixture.fallback,
      songs: [PlaybackTrack(id: "a", title: "A", artist: "", artwork: nil)])
    XCTAssertNil(result.durationSeconds)
    XCTAssertEqual(result.songs.first?.artist, AlbumFixture.fallback.artist)
  }
  func testAlbumFavoritesMetadataRoundTripsWithoutLosingArtwork() throws {
    let album = LibraryAlbum(
      id: "MPREid", title: "Album", artist: "Artist",
      artwork: URL(string: "https://example.org/album.jpg"))
    let value = try JSONDecoder().decode([LibraryAlbum].self, from: JSONEncoder().encode([album]))
    XCTAssertEqual(value, [album])
  }
}

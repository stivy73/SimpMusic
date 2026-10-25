import Foundation
import XCTest

@testable import PrototypeCore

private actor RadioScript {
  var pages: [Data]
  var requests: [(RadioEndpoint, String?)] = []
  init(_ pages: [Data]) { self.pages = pages }
  func load(_ endpoint: RadioEndpoint, _ continuation: String?) throws -> Data {
    requests.append((endpoint, continuation))
    guard !pages.isEmpty else { throw RadioError.unavailable }
    return pages.removeFirst()
  }
}

final class MusicRadioTests: XCTestCase {
  private func page(_ contents: String, token: String? = nil, initial: Bool = false) -> Data {
    let continuations =
      token.map {
        ",\"continuations\":[{\"nextRadioContinuationData\":{\"continuation\":\"\($0)\"}}]"
      } ?? ""
    let panel = "{\"contents\":[\(contents)]\(continuations)}"
    let json =
      initial
      ? "{\"contents\":{\"singleColumnMusicWatchNextResultsRenderer\":{\"tabbedRenderer\":{\"watchNextTabbedResultsRenderer\":{\"tabs\":[{\"tabRenderer\":{\"content\":{\"musicQueueRenderer\":{\"content\":{\"playlistPanelRenderer\":\(panel)}}}}}]}}}}}"
      : "{\"continuationContents\":{\"playlistPanelContinuation\":\(panel)}}"
    return Data(json.utf8)
  }
  private func track(_ id: String) -> String {
    #"{"playlistPanelVideoRenderer":{"videoId":"ID","title":{"runs":[{"text":"Title"}]},"longBylineText":{"runs":[{"text":"Artist","navigationEndpoint":{"browseEndpoint":{"browseId":"UCartist"}}},{"text":" • "},{"text":"Album","navigationEndpoint":{"browseEndpoint":{"browseId":"MPREalbum"}}}]},"lengthText":{"runs":[{"text":"3:21"}]},"thumbnail":{"thumbnails":[{"url":"https://example.org/small.jpg"},{"url":"https://example.org/large.jpg"}]}}}"#
      .replacingOccurrences(of: "ID", with: id)
  }
  private var automix: String {
    #"{"automixPreviewVideoRenderer":{"content":{"automixPlaylistVideoRenderer":{"navigationEndpoint":{"watchPlaylistEndpoint":{"playlistId":"RDAutomix","params":"server-param","videoId":"mix"}}}}}}"#
  }
  func testInitialQueueKeepsAlbumArtistDurationAndLargestCover() throws {
    let result = try RadioPage.decode(
      page(track("seed"), token: "one", initial: true), endpoint: .song("seed"))
    let item = try XCTUnwrap(result.items.first)
    XCTAssertEqual(item.mediaId, "seed")
    XCTAssertEqual(item.title, "Title")
    XCTAssertEqual(item.subtitle, "Artist")
    XCTAssertEqual(item.artistBrowseID, "UCartist")
    XCTAssertEqual(item.albumBrowseID, "MPREalbum")
    XCTAssertEqual(item.albumTitle, "Album")
    XCTAssertEqual(item.durationSeconds, 201)
    XCTAssertEqual(item.artwork?.lastPathComponent, "large.jpg")
    XCTAssertEqual(result.continuation, "one")
  }
  func testContinuationAndUnavailableEntries() throws {
    let invalid =
      #"{"playlistPanelVideoRenderer":{"videoId":"bad","title":{"simpleText":"Unavailable"},"isPlayable":false}}"#
    let result = try RadioPage.decode(page(track("next") + "," + invalid), endpoint: .song("seed"))
    XCTAssertEqual(result.items.map(\.mediaId), ["next"])
    XCTAssertNil(result.continuation)
  }
  func testUnknownResponseIsRejectedInsteadOfInventingRecommendations() {
    XCTAssertThrowsError(try RadioPage.decode(Data("{}".utf8), endpoint: .song("seed")))
  }
  func testArtistRadioUsesServerEndpointAndNeverFabricatesArtistPlaylist() throws {
    let data = Data(
      #"{"header":{"musicImmersiveHeaderRenderer":{"startRadioButton":{"buttonRenderer":{"navigationEndpoint":{"watchEndpoint":{"playlistId":"RDartist","params":"from-server","videoId":"artist-seed","index":2}}}}}}}"#
        .utf8)
    let endpoint = try RadioEndpoint.artist(in: data)
    XCTAssertEqual(endpoint.playlistID, "RDartist")
    XCTAssertEqual(endpoint.videoID, "artist-seed")
    XCTAssertEqual(endpoint.params, "from-server")
    XCTAssertEqual(endpoint.index, 2)
    XCTAssertThrowsError(try RadioEndpoint.artist(in: Data("{}".utf8)))
  }
  func testAutomixPointerAndContinuationStayOnCorrectEndpoint() async throws {
    let script = RadioScript([
      page(track("seed") + "," + automix, initial: true),
      page(track("suggested"), token: "mix-token"), page(track("later")),
    ])
    let service = MusicRadio { try await script.load($0, $1) }
    let result = try await service.page(endpoint: .song("seed"))
    XCTAssertEqual(result.items.map(\.mediaId), ["seed", "suggested"])
    XCTAssertEqual(result.endpoint.playlistID, "RDAutomix")
    _ = try await service.page(endpoint: result.endpoint, continuation: result.continuation)
    let requests = await script.requests
    XCTAssertEqual(requests.count, 3)
    XCTAssertEqual(requests[1].0.params, "server-param")
    XCTAssertEqual(requests[2].0.playlistID, "RDAutomix")
    XCTAssertEqual(requests[2].1, "mix-token")
  }
  func testAutomixCycleFailsWithoutUnboundedRequests() async throws {
    let script = RadioScript([page(automix), page(automix)])
    do {
      _ = try await MusicRadio { try await script.load($0, $1) }.page(endpoint: .song("seed"))
      XCTFail("Cyclic automix accepted")
    } catch RadioError.repeatedPage {}
    let count = await script.requests.count
    XCTAssertEqual(count, 2)
  }
  func testCursorExcludesManualQueueAndDuplicateSuggestionsAndRejectsRepeatedTokens() throws {
    var cursor = RadioCursor(endpoint: .song("seed"))
    let first = try RadioPage.decode(
      page(
        track("seed") + "," + track("manual") + "," + track("new") + "," + track("new"),
        token: "one"), endpoint: .song("seed"))
    XCTAssertEqual(try cursor.accept(first, excluding: ["seed", "manual"]).map(\.mediaId), ["new"])
    XCTAssertFalse(cursor.exhausted)
    XCTAssertThrowsError(try cursor.accept(first, excluding: []))
    let last = try RadioPage.decode(page(track("last")), endpoint: .song("seed"))
    XCTAssertEqual(try cursor.accept(last, excluding: []).count, 1)
    XCTAssertTrue(cursor.exhausted)
  }
}

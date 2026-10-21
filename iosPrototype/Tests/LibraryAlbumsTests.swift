import XCTest

@testable import PrototypeCore

final class LibraryAlbumsTests: XCTestCase {
  private func item(_ id: String) -> [String: Any] {
    [
      "musicTwoRowItemRenderer": [
        "navigationEndpoint": [
          "browseEndpoint": [
            "browseId": id,
            "browseEndpointContextSupportedConfigs": [
              "browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ALBUM"]
            ],
          ]
        ],
        "title": ["runs": [["text": "Album \(id)"]]],
        "subtitle": ["runs": [["text": "Artista"]]],
        "thumbnailRenderer": [
          "musicThumbnailRenderer": [
            "thumbnail": ["thumbnails": [["url": "https://example.org/cover.jpg"]]]
          ]
        ],
      ]
    ]
  }
  private func page(_ ids: [String], next: String? = nil, initial: Bool = false) throws
    -> LibraryAlbumsPage
  {
    var grid: [String: Any] = ["items": ids.map(item)]
    if let next { grid["continuations"] = [["nextContinuationData": ["continuation": next]]] }
    let json: [String: Any] =
      initial
      ? [
        "contents": [
          "singleColumnBrowseResultsRenderer": [
            "tabs": [
              [
                "tabRenderer": [
                  "content": ["sectionListRenderer": ["contents": [["gridRenderer": grid]]]]
                ]
              ]
            ]
          ]
        ]
      ]
      : ["continuationContents": ["gridContinuation": grid]]
    return try LibraryAlbumsPage.parse(JSONSerialization.data(withJSONObject: json))
  }
  func testAlbumRendererAndFirstPage() throws {
    let result = try page(["MPRE1"], next: "next", initial: true)
    XCTAssertEqual(result.albums.first?.title, "Album MPRE1")
    XCTAssertEqual(result.albums.first?.artist, "Artista")
    XCTAssertEqual(result.albums.first?.artwork?.host, "example.org")
    XCTAssertEqual(result.continuations, ["next"])
  }
  func testEmptyLibrary() throws { XCTAssertTrue(try page([], initial: true).albums.isEmpty) }
  func testMultipleContinuationsDeduplicateAlbums() async throws {
    let first = try page(["A"], next: "one", initial: true)
    let second = try page(["A", "B"], next: "two")
    let last = try page(["C", "B"])
    let albums = try await LibraryAlbumsPage.completed { token in
      switch token {
      case nil: first
      case "one": second
      default: last
      }
    }
    XCTAssertEqual(albums.map(\.id), ["A", "B", "C"])
  }
  func testRepeatedContinuationIsError() async throws {
    let repeated = try page(["A"], next: "same")
    do {
      _ = try await LibraryAlbumsPage.completed { _ in repeated }
      XCTFail("Repeated tokens must fail")
    } catch LibraryError.repeatedContinuation {} catch { XCTFail("Unexpected error") }
  }
  func testContinuationFailureDoesNotReturnPartialLibrary() async throws {
    let first = try page(["A"], next: "next")
    do {
      _ = try await LibraryAlbumsPage.completed { token in
        if token != nil { throw LibraryError.http(503) }
        return first
      }
      XCTFail("Partial success must not escape")
    } catch LibraryError.http(503) {} catch { XCTFail("Unexpected error") }
  }
  func testMalformedAndUnauthenticatedResponse() throws {
    for json in [
      "{}", "{\"contents\":{\"sectionListRenderer\":{\"contents\":[{\"unknownRenderer\":{}}]}}}",
      "{\"continuationContents\":{\"gridContinuation\":{\"items\":[{}]}}}",
    ] {
      XCTAssertThrowsError(try LibraryAlbumsPage.parse(Data(json.utf8)))
    }
    let loggedOut =
      "{\"responseContext\":{\"serviceTrackingParams\":[{\"params\":[{\"key\":\"logged_in\",\"value\":\"0\"}]}]}}"
    XCTAssertThrowsError(try LibraryAlbumsPage.parse(Data(loggedOut.utf8))) { error in
      guard case LibraryError.authentication = error else { return XCTFail("Expected auth error") }
    }
  }
  func testCookieAuthenticationAndAccountIdentity() throws {
    let account = YouTubeSession(
      cookies: "SAPISID=test", accountIndex: "1", delegatedID: "brand",
      identity: "user", clientVersion: "1.test")
    XCTAssertEqual(
      try account.authorization(timestamp: 1),
      "SAPISIDHASH 1_3e818942372dd3b77f9cd5debf20a5b353a9ba02")
    XCTAssertEqual(
      try JSONDecoder().decode(YouTubeSession.self, from: JSONEncoder().encode(account)), account)
    XCTAssertThrowsError(
      try YouTubeSession(cookies: "", identity: "", clientVersion: "").authorization())
  }
  func testDiagnosticIncludesOnlySchemaKeys() throws {
    let data = Data(
      """
      {"continuationContents":{"gridContinuation":{"items":[],"continuations":[
      {"unexpectedContinuation":{"token":"PRIVATE_TOKEN", "email":"PRIVATE_EMAIL"}}]}}}
      """.utf8)
    XCTAssertThrowsError(try LibraryAlbumsPage.parse(data)) { error in
      XCTAssertTrue(error.localizedDescription.contains("nextContinuationData"))
      XCTAssertFalse(error.localizedDescription.contains("PRIVATE"))
    }
  }

  func testOnlySelectedTabIsParsedAndLazyTabsAreIgnored() throws {
    let active: [String: Any] = [
      "tabRenderer": [
        "selected": true,
        "content": [
          "sectionListRenderer": ["contents": [["gridRenderer": ["items": [item("MPRE1")]]]]]
        ],
      ]
    ]
    let lazy: [String: Any] = [
      "tabRenderer": ["content": ["sectionListRenderer": ["trackingParams": "ignored"]]]
    ]
    for tabs in [[active, lazy], [lazy, active]] {
      let response: [String: Any] = [
        "contents": ["singleColumnBrowseResultsRenderer": ["tabs": tabs]]
      ]
      let page = try LibraryAlbumsPage.parse(JSONSerialization.data(withJSONObject: response))
      XCTAssertEqual(page.albums.map(\.id), ["MPRE1"])
    }
  }

  func testMalformedSelectedTabCannotFallBackToAnotherAccountOrTab() throws {
    let tabs: [[String: Any]] = [
      ["tabRenderer": ["selected": true, "content": ["sectionListRenderer": [:]]]],
      [
        "tabRenderer": [
          "content": [
            "sectionListRenderer": ["contents": [["gridRenderer": ["items": [item("MPRE_wrong")]]]]]
          ]
        ]
      ],
    ]
    let response: [String: Any] = [
      "contents": ["singleColumnBrowseResultsRenderer": ["tabs": tabs]]
    ]
    XCTAssertThrowsError(
      try LibraryAlbumsPage.parse(JSONSerialization.data(withJSONObject: response)))
  }

}

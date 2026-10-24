import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

enum HomeFixture {
  static func text(_ value: String) -> [String: Any] { ["runs": [["text": value]]] }
  static func endpoint(_ id: String, params: String? = nil) -> [String: Any] {
    var browse: [String: Any] = ["browseId": id]
    if let params { browse["params"] = params }
    browse["browseEndpointContextSupportedConfigs"] = [
      "browseEndpointContextMusicConfig": ["pageType": "MUSIC_PAGE_TYPE_ARTIST"]
    ]
    return ["browseEndpoint": browse]
  }
  static var thumbnail: [String: Any] {
    [
      "musicThumbnailRenderer": [
        "thumbnail": ["thumbnails": [["url": "https://example.org/art.jpg"]]]
      ]
    ]
  }
  static func item(_ id: String) -> [String: Any] {
    [
      "musicTwoRowItemRenderer": [
        "title": text("Titolo \(id)"),
        "subtitle": ["runs": [["text": "Artista", "navigationEndpoint": endpoint("UCartist")]]],
        "navigationEndpoint": id.hasPrefix("song")
          ? ["watchEndpoint": ["videoId": id]] : endpoint(id),
        "thumbnailRenderer": thumbnail,
      ]
    ]
  }
  static func shelf(_ ids: [String], title: String = "Ascolta di nuovo") -> [String: Any] {
    [
      "musicCarouselShelfRenderer": [
        "header": [
          "musicCarouselShelfBasicHeaderRenderer": [
            "title": text(title), "strapline": text("Account"), "thumbnail": thumbnail,
            "moreContentButton": [
              "buttonRenderer": ["navigationEndpoint": endpoint("more", params: "more-params")]
            ],
          ]
        ],
        "contents": ids.map(item),
        // A shelf's token must not replace the page continuation.
        "continuations": [["nextContinuationData": ["continuation": "nested-shelf-token"]]],
      ]
    ]
  }
  static func categories() -> [String: Any] {
    [
      "gridRenderer": [
        "header": ["gridHeaderRenderer": ["title": text("Generi")]],
        "items": [
          [
            "musicNavigationButtonRenderer": [
              "buttonText": text("Pop"), "solid": ["leftStripeColor": 0xFF12_3456],
              "clickCommand": endpoint("FEmusic_moods_and_genres_category", params: "pop-params"),
            ]
          ]
        ],
      ]
    ]
  }
  static func data(rows: [[String: Any]], next: String? = nil, initial: Bool = true) throws -> Data
  {
    var list: [String: Any] = ["contents": rows]
    if let next { list["continuations"] = [["nextContinuationData": ["continuation": next]]] }
    let json: [String: Any] =
      initial
      ? [
        "contents": [
          "singleColumnBrowseResultsRenderer": [
            "tabs": [
              [
                "tabRenderer": [
                  "selected": true, "content": ["sectionListRenderer": list],
                ]
              ]
            ]
          ]
        ]
      ]
      : ["continuationContents": ["sectionListContinuation": list]]
    return try JSONSerialization.data(withJSONObject: json)
  }
  static func page(_ ids: [String], next: String? = nil) async throws -> HomePage {
    let data = try data(rows: [shelf(ids)], next: next)
    return try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: data))
  }
}

final class HomeDiscoveryTests: XCTestCase {
  func testSearchEnvelopePreservesResponsiveArtistAndAlbumRows() async throws {
    func row(_ id: String, type: String) -> [String: Any] {
      var nav = HomeFixture.endpoint(id)
      nav["browseEndpoint"] = [
        "browseId": id,
        "browseEndpointContextSupportedConfigs": [
          "browseEndpointContextMusicConfig": ["pageType": type]
        ],
      ]
      return [
        "musicResponsiveListItemRenderer": [
          "navigationEndpoint": nav,
          "flexColumns": [
            ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text("Nome")]],
            ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text("Dettagli")]],
          ], "thumbnail": HomeFixture.thumbnail,
        ]
      ]
    }
    let root: [String: Any] = [
      "contents": [
        "tabbedSearchResultsRenderer": [
          "tabs": [
            [
              "tabRenderer": [
                "selected": true,
                "content": [
                  "sectionListRenderer": [
                    "contents": [
                      [
                        "musicShelfRenderer": [
                          "title": HomeFixture.text("Risultati"),
                          "contents": [
                            row("UCartist", type: "MUSIC_PAGE_TYPE_ARTIST"),
                            row("MPREalbum", type: "MUSIC_PAGE_TYPE_ALBUM"),
                          ],
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
    let data = try JSONSerialization.data(withJSONObject: root)
    let page = try await YouTubeMusicClient().decodeDiscoveryPage(from: data)
    let items = HomePage(page).shelves.flatMap(\.items)
    XCTAssertEqual(items.map(\.kind), [.artist, .album])
    XCTAssertEqual(items.map(\.mediaId), ["UCartist", "MPREalbum"])
  }

  func testMixedCarouselPreservesOrderMetadataAndNavigation() async throws {
    let data = try HomeFixture.data(
      rows: [HomeFixture.shelf(["song1", "MPREalbum", "VLplaylist", "UCartist"])],
      next: "page-token")
    let page = try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: data))
    let shelf = try XCTUnwrap(page.shelves.first)
    XCTAssertEqual(shelf.items.map(\.kind), [.song, .album, .playlist, .artist])
    XCTAssertEqual(shelf.items.map(\.mediaId), ["song1", "MPREalbum", "VLplaylist", "UCartist"])
    XCTAssertEqual(shelf.title, "Ascolta di nuovo")
    XCTAssertEqual(shelf.subtitle, "Account")
    XCTAssertEqual(shelf.avatar?.host, "example.org")
    XCTAssertEqual(shelf.more, BrowseTarget(browseId: "more", params: "more-params"))
    XCTAssertEqual(page.continuation, "page-token")
    XCTAssertEqual(shelf.items.first?.subtitle, "Artista")
    XCTAssertEqual(shelf.items.first?.artwork?.host, "example.org")
  }

  func testCategoryTitleColorAndParamsComeFromRenderer() async throws {
    let data = try HomeFixture.data(rows: [HomeFixture.categories()])
    let page = try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: data))
    XCTAssertEqual(page.categories.first?.title, "Generi")
    let category = try XCTUnwrap(page.categories.first?.items.first)
    XCTAssertEqual(category.title, "Pop")
    XCTAssertEqual(category.stripeColor, 0xFF12_3456)
    XCTAssertEqual(category.target.params, "pop-params")
    XCTAssertEqual(category.target.browseId, "FEmusic_moods_and_genres_category")
  }

  func testEmptyAndUnexpectedEnvelopesAreDistinct() async throws {
    let empty = try HomeFixture.data(rows: [])
    let page = try await YouTubeMusicClient().decodeDiscoveryPage(from: empty)
    XCTAssertTrue(page.sections.isEmpty)
    XCTAssertNil(page.continuationToken)
    for json in [
      "{}", "{\"error\":{\"code\":401}}",
      "{\"contents\":{\"sectionListRenderer\":{\"contents\":{}}}}",
    ] {
      do {
        _ = try await YouTubeMusicClient().decodeDiscoveryPage(from: Data(json.utf8))
        XCTFail("Malformed pages must fail")
      } catch {}
    }
  }

  func testContinuationActionAndResponsiveSong() async throws {
    let row: [String: Any] = [
      "musicResponsiveListItemRenderer": [
        "playlistItemData": ["videoId": "song1"],
        "flexColumns": [
          ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text("Canzone")]]
        ],
        "thumbnail": HomeFixture.thumbnail,
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: [
      "onResponseReceivedActions": [
        [
          "appendContinuationItemsAction": [
            "continuationItems": [
              row,
              [
                "continuationItemRenderer": [
                  "continuationEndpoint": ["continuationCommand": ["token": "next"]]
                ]
              ],
            ]
          ]
        ]
      ]
    ])
    let page = try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: data))
    XCTAssertEqual(page.shelves.first?.items.first?.mediaId, "song1")
    XCTAssertEqual(page.shelves.first?.items.first?.title, "Canzone")
    XCTAssertEqual(page.continuation, "next")
  }

  func testTwoColumnPlaylistKeepsSecondaryTracksAndTheirContinuation() async throws {
    let playlist: [String: Any] = [
      "musicPlaylistShelfRenderer": [
        "contents": [HomeFixture.item("song1")],
        "continuations": [["nextContinuationData": ["continuation": "playlist-next"]]],
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: [
      "contents": [
        "twoColumnBrowseResultsRenderer": [
          "tabs": [
            [
              "tabRenderer": [
                "selected": false,
                "content": [
                  "sectionListRenderer": ["contents": [HomeFixture.shelf(["songOtherTab"])]]
                ],
              ]
            ],
            [
              "tabRenderer": [
                "selected": true, "content": ["sectionListRenderer": ["contents": []]],
              ]
            ],
          ],
          "secondaryContents": ["sectionListRenderer": ["contents": [playlist]]],
        ]
      ]
    ])
    let page = try await HomePage(YouTubeMusicClient().decodeDiscoveryPage(from: data))
    XCTAssertEqual(page.shelves.flatMap(\.items).map(\.mediaId), ["song1"])
    XCTAssertEqual(page.continuation, "playlist-next")
  }

  func testMalformedContinuationAndUnknownRendererAreErrors() async throws {
    for list: [String: Any] in [
      ["contents": [], "continuations": [["nextContinuationData": ["continuation": ""]]]],
      ["contents": [["unexpectedRenderer": [:]]]],
    ] {
      let data = try JSONSerialization.data(withJSONObject: [
        "contents": ["sectionListRenderer": list]
      ])
      do {
        _ = try await YouTubeMusicClient().decodeDiscoveryPage(from: data)
        XCTFail("Unsupported data must not look like a complete empty page")
      } catch {}
    }
  }
}

@MainActor
final class HomeModelTests: XCTestCase {
  private func session(_ id: String, cookies: String = "SAPISID=test") -> YouTubeSession {
    .init(cookies: cookies, identity: id, clientVersion: "test")
  }

  func testMultipleContinuationsMergeAndDeduplicateShelfItems() async throws {
    let first = try await HomeFixture.page(["song1"], next: "one")
    let second = try await HomeFixture.page(["song1", "song2"], next: "two")
    let last = try await HomeFixture.page(["song2", "song3"])
    let model = HomeModel(
      target: BrowseTarget(browseId: "test"),
      fetch: { _, _, token in
        switch token {
        case nil: first
        case "one": second
        default: last
        }
      })
    await model.configure(session: nil)
    await model.loadMore()
    await model.loadMore()
    XCTAssertEqual(model.shelves.count, 1)
    XCTAssertEqual(model.shelves.first?.items.map(\.mediaId), ["song1", "song2", "song3"])
    XCTAssertNil(model.continuation)
    XCTAssertNil(model.continuationError)
  }

  func testRepeatedContinuationStopsWithVisibleError() async throws {
    let page = try await HomeFixture.page(["song1"], next: "repeat")
    let model = HomeModel(target: BrowseTarget(browseId: "test"), fetch: { _, _, _ in page })
    await model.configure(session: nil)
    await model.loadMore()
    XCTAssertNil(model.continuation)
    XCTAssertNotNil(model.continuationError)
    XCTAssertEqual(model.shelves.first?.items.count, 1)
    await model.loadMore()
    XCTAssertFalse(model.loadingMore)
  }

  func testUnnamedPlaylistTracksMergeAcrossPages() async throws {
    let firstData = try HomeFixture.data(
      rows: [
        [
          "musicPlaylistShelfRenderer": [
            "contents": [HomeFixture.item("song1"), HomeFixture.item("song2")]
          ]
        ]
      ], next: "next")
    let lastData = try JSONSerialization.data(withJSONObject: [
      "continuationContents": [
        "musicPlaylistShelfContinuation": [
          "contents": [HomeFixture.item("song2"), HomeFixture.item("song3")]
        ]
      ]
    ])
    let parser = YouTubeMusicClient()
    let first = try await HomePage(parser.decodeDiscoveryPage(from: firstData))
    let last = try await HomePage(parser.decodeDiscoveryPage(from: lastData))
    let model = HomeModel(
      target: BrowseTarget(browseId: "VLplaylist"),
      fetch: { _, _, token in token == nil ? first : last })
    await model.configure(session: nil)
    await model.loadMore()
    XCTAssertEqual(model.shelves.count, 1)
    XCTAssertEqual(model.shelves.first?.items.map(\.mediaId), ["song1", "song2", "song3"])
  }

  func testContinuationFailureIsVisibleAndRetryDoesNotDuplicate() async throws {
    actor Attempt {
      var count = 0
      func failOnce() -> Bool {
        count += 1
        return count == 1
      }
    }
    let attempt = Attempt()
    let first = try await HomeFixture.page(["song1"], next: "next")
    let last = try await HomeFixture.page(["song1", "song2"])
    let model = HomeModel(
      target: BrowseTarget(browseId: "test"),
      fetch: { _, _, token in
        if token == nil { return first }
        if await attempt.failOnce() { throw LibraryError.http(503) }
        return last
      })
    await model.configure(session: nil)
    await model.loadMore()
    XCTAssertNotNil(model.continuationError)
    XCTAssertEqual(model.continuation, "next")
    XCTAssertEqual(model.shelves.first?.items.count, 1)
    await model.loadMore()
    XCTAssertNil(model.continuationError)
    XCTAssertNil(model.continuation)
    XCTAssertEqual(model.shelves.first?.items.count, 2)
  }

  func testAccountSwitchAndLogoutRejectLateResults() async throws {
    let old = try await HomeFixture.page(["songOld"])
    let current = try await HomeFixture.page(["songNew"])
    let anonymous = try await HomeFixture.page(["songPublic"])
    let model = HomeModel(
      target: BrowseTarget(browseId: "test"),
      fetch: { session, _, _ in
        if session?.identity == "old" {
          try? await Task.sleep(for: .milliseconds(100))
          return old
        }
        return session == nil ? anonymous : current
      })
    let pending = Task { await model.configure(session: session("old")) }
    await Task.yield()
    await model.configure(session: session("new"))
    await pending.value
    XCTAssertEqual(model.shelves.first?.items.first?.mediaId, "songNew")
    await model.configure(session: nil)
    XCTAssertEqual(model.shelves.first?.items.first?.mediaId, "songPublic")
    XCTAssertNil(model.error)
  }

  func testFilterParamsAndCookieRenewalTriggerFreshHome() async throws {
    actor Requests {
      var values: [(String, String?, String?)] = []
      func add(_ session: YouTubeSession?, _ target: BrowseTarget) {
        values.append((target.browseId, target.params, session?.cookies))
      }
    }
    let requests = Requests()
    let page = try await HomeFixture.page(["song1"])
    let model = HomeModel(fetch: { session, target, _ in
      await requests.add(session, target)
      return page
    })
    await model.configure(session: session("same"))
    let relax = HomeFilter.values[1]
    await model.select(relax)
    XCTAssertEqual(model.selectedFilter, relax)
    await model.configure(session: session("same", cookies: "SAPISID=renewed"))
    XCTAssertEqual(model.selectedFilter, .all)
    let values = await requests.values
    XCTAssertTrue(values.contains { $0.0 == "FEmusic_home" && $0.1 == relax.params })
    XCTAssertTrue(values.contains { $0.0 == "FEmusic_moods_and_genres" })
    XCTAssertEqual(values.filter { $0.0 == "FEmusic_home" }.count, 3)
  }

  func testFirstPageAuthFailureDoesNotShowPreviousAccount() async throws {
    let page = try await HomeFixture.page(["song1"])
    let model = HomeModel(
      target: BrowseTarget(browseId: "test"),
      fetch: { session, _, _ in
        if session?.identity == "expired" { throw LibraryError.authentication }
        return page
      })
    await model.configure(session: session("old"))
    await model.configure(session: session("expired"))
    XCTAssertTrue(model.shelves.isEmpty)
    XCTAssertTrue(model.error?.contains("scaduta") == true)
    XCTAssertFalse(model.loading)
  }
}

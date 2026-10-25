import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

private actor SearchAttempts {
  var value = 0
  func next() -> Int {
    value += 1
    return value
  }
}

@MainActor
final class MusicSearchTests: XCTestCase {
  private func item(_ id: String, kind: DiscoveryItem.Kind = .song) -> DiscoveryItem {
    DiscoveryItem(kind: kind, mediaId: id, title: id, subtitle: "Artist", artwork: nil)
  }
  private func account(_ id: String, cookie: String = "fixture") -> YouTubeSession {
    YouTubeSession(cookies: cookie, identity: id, clientVersion: "fixture-version")
  }
  func testAllCategoriesKeepTypesAndPartialErrorsSeparate() async {
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, query, filter, _ in
        if filter == .podcasts { throw LibraryError.http(503) }
        return MusicSearchPage(items: [
          DiscoveryItem(
            kind: filter.kind, mediaId: filter.identifier, title: query, subtitle: "Artist",
            artwork: nil)
        ])
      })
    await model.submit("  Fleetwood Mac  ")?.value
    XCTAssertEqual(model.sections.count, 7)
    XCTAssertEqual(model.submittedQuery, "Fleetwood Mac")
    XCTAssertEqual(model.sections.first?.items.first?.title, "Fleetwood Mac")
    XCTAssertNotNil(model.sections.last?.error)
    XCTAssertFalse(model.loading)
    XCTAssertEqual(model.history, ["Fleetwood Mac"])
    XCTAssertEqual(MusicSearchFilter.carPlay, [.songs, .artists, .albums])
  }
  func testFirstFastSectionAppearsWhileOtherSourcesStillLoading() async throws {
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, _, filter, _ in
        if filter != .songs { try await Task.sleep(for: .milliseconds(150)) }
        return MusicSearchPage(items: [
          DiscoveryItem(
            kind: filter.kind, mediaId: filter.identifier, title: "Result", subtitle: "",
            artwork: nil)
        ])
      })
    let pending = model.submit("query")
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(model.sections.first?.items.count, 1)
    XCTAssertTrue(model.sections.dropFirst().contains { $0.loading })
    XCTAssertTrue(model.loading)
    await pending?.value
    XCTAssertFalse(model.loading)
  }
  func testCategorySwitchRejectsLateResultsAndUsesSubmittedQueryNotDraft() async {
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, query, filter, _ in
        if filter == .songs { try? await Task.sleep(for: .milliseconds(100)) }
        return MusicSearchPage(items: [
          DiscoveryItem(
            kind: filter.kind, mediaId: filter.identifier, title: query, subtitle: "", artwork: nil)
        ])
      })
    model.select(.category(.songs))
    let old = model.submit("original")
    model.query = "unsubmitted draft"
    await model.select(.category(.artists))?.value
    await old?.value
    XCTAssertEqual(model.sections.map(\.filter), [.artists])
    XCTAssertEqual(model.sections.first?.items.first?.title, "original")
    XCTAssertEqual(model.submittedQuery, "original")
  }
  func testNewQueryAndClearRejectLateSearchResponses() async {
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, query, filter, _ in
        if query == "old" { try? await Task.sleep(for: .milliseconds(100)) }
        return MusicSearchPage(items: [
          DiscoveryItem(kind: filter.kind, mediaId: query, title: query, subtitle: "", artwork: nil)
        ])
      })
    model.select(.category(.songs))
    let old = model.submit("old")
    await model.submit("new")?.value
    await old?.value
    XCTAssertEqual(model.sections.first?.items.first?.mediaId, "new")
    let cleared = model.submit("old")
    model.clear()
    await cleared?.value
    XCTAssertTrue(model.sections.isEmpty)
    XCTAssertEqual(model.submittedQuery, "")
    XCTAssertFalse(model.loading)
  }
  func testAccountChangeAndLogoutClearPreviousResultsAndRerunOnNewIdentity() async {
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { session, _, filter, _ in
        if session?.identity == "old" { try? await Task.sleep(for: .milliseconds(100)) }
        return MusicSearchPage(items: [
          DiscoveryItem(
            kind: filter.kind, mediaId: session?.identity ?? "public", title: "Result",
            subtitle: "", artwork: nil)
        ])
      })
    model.select(.category(.songs))
    model.configure(session: account("old"))
    let old = model.submit("query")
    model.configure(session: account("new"))
    await old?.value
    // Wait on an explicit current-account request too; the old response must never reappear.
    await model.submit()?.value
    XCTAssertEqual(model.sections.first?.items.first?.mediaId, "new")
    model.configure(session: nil)
    await model.submit()?.value
    XCTAssertEqual(model.sections.first?.items.first?.mediaId, "public")
  }
  func testContinuationRetryPreservesResultsAndTokenAndDeduplicates() async {
    let attempts = SearchAttempts()
    let first = item("a")
    let second = item("b")
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, _, _, token in
        if token == nil { return MusicSearchPage(items: [first], continuation: "next") }
        if await attempts.next() == 1 { throw LibraryError.http(503) }
        return MusicSearchPage(items: [first, second])
      })
    model.select(.category(.songs))
    await model.submit("query")?.value
    await model.loadMore(.songs)?.value
    XCTAssertEqual(model.sections.first?.items.map(\.mediaId), ["a"])
    XCTAssertEqual(model.sections.first?.continuation, "next")
    XCTAssertNotNil(model.sections.first?.moreError)
    await model.loadMore(.songs)?.value
    XCTAssertEqual(model.sections.first?.items.map(\.mediaId), ["a", "b"])
    XCTAssertNil(model.sections.first?.continuation)
    XCTAssertNil(model.sections.first?.moreError)
  }
  func testRepeatedContinuationStopsPaginationAndKeepsExistingItems() async {
    let first = item("a")
    let second = item("b")
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, _, _, token in
        MusicSearchPage(items: token == nil ? [first] : [first, second], continuation: "same")
      })
    model.select(.category(.songs))
    await model.submit("query")?.value
    await model.loadMore(.songs)?.value
    XCTAssertEqual(model.sections.first?.items.map(\.mediaId), ["a", "b"])
    XCTAssertNil(model.sections.first?.continuation)
    XCTAssertTrue(model.sections.first?.moreError?.contains("ripetuto") == true)
    XCTAssertNil(model.loadMore(.songs))
  }
  func testLateContinuationCannotAppendToNewQuery() async {
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, query, filter, token in
        if token != nil { try? await Task.sleep(for: .milliseconds(100)) }
        return MusicSearchPage(
          items: [
            DiscoveryItem(
              kind: filter.kind, mediaId: query + (token ?? ""), title: query, subtitle: "",
              artwork: nil)
          ], continuation: token == nil ? "next" : nil)
      })
    model.select(.category(.songs))
    await model.submit("first")?.value
    let old = model.loadMore(.songs)
    await model.submit("second")?.value
    await old?.value
    XCTAssertEqual(model.sections.first?.items.map(\.mediaId), ["second"])
  }
  func testCategoryRetryDoesNotReloadSuccessfulCategories() async {
    let attempts = SearchAttempts()
    let model = MusicSearchModel(
      history: [], saveHistory: { _ in },
      fetch: { _, _, filter, _ in
        if filter == .albums {
          if await attempts.next() == 1 { throw LibraryError.authentication }
        }
        return MusicSearchPage(items: [
          DiscoveryItem(
            kind: filter.kind, mediaId: filter.identifier, title: "Result", subtitle: "",
            artwork: nil)
        ])
      })
    await model.submit("query")?.value
    XCTAssertTrue(model.sections.first { $0.filter == .albums }?.error?.contains("scaduta") == true)
    await model.retry(.albums)?.value
    XCTAssertNil(model.sections.first { $0.filter == .albums }?.error)
    XCTAssertEqual(model.sections.first { $0.filter == .songs }?.items.count, 1)
  }
  func testHistoryIsBoundedCaseInsensitiveAndCanBeDeleted() async {
    let model = MusicSearchModel(
      history: (1...25).map { "Query \($0)" }, saveHistory: { _ in },
      fetch: { _, _, _, _ in MusicSearchPage(items: []) })
    XCTAssertEqual(model.history.count, 20)
    model.select(.category(.songs))
    await model.submit("query 5")?.value
    XCTAssertEqual(model.history.first, "query 5")
    XCTAssertFalse(model.history.contains("Query 5"))
    XCTAssertEqual(model.history.count, 20)
    model.removeHistory("query 5")
    XCTAssertEqual(model.history.count, 19)
    model.removeHistory()
    XCTAssertTrue(model.history.isEmpty)
  }
}

final class MusicSearchDecodingTests: XCTestCase {
  func testFilteredSearchKeepsShelfContinuationBesideHeaders() async throws {
    let data = try HomeFixture.data(rows: [
      ["musicHeaderRenderer": ["title": HomeFixture.text("Results")]],
      [
        "musicShelfRenderer": [
          "contents": [HomeFixture.item("song-a")],
          "continuations": [["nextContinuationData": ["continuation": "shelf-next"]]],
        ]
      ],
    ])
    let search = try await MusicSearchPage.decode(data, filter: .songs)
    XCTAssertEqual(search.items.map(\.mediaId), ["song-a"])
    XCTAssertEqual(search.continuation, "shelf-next")
    let home = try await YouTubeMusicClient().decodeDiscoveryPage(from: data)
    XCTAssertNil(home.continuationToken)
  }

  func testPodcastAndPlaylistRowsKeepBrowseDestinationsAndPagination() async throws {
    func row(_ id: String, _ type: String) -> [String: Any] {
      var endpoint = HomeFixture.endpoint(id)
      endpoint["browseEndpoint"] = [
        "browseId": id,
        "browseEndpointContextSupportedConfigs": [
          "browseEndpointContextMusicConfig": ["pageType": type]
        ],
      ]
      return [
        "musicResponsiveListItemRenderer": [
          "navigationEndpoint": endpoint,
          "flexColumns": [
            ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text("Title")]],
            ["musicResponsiveListItemFlexColumnRenderer": ["text": HomeFixture.text("Creator")]],
          ], "thumbnail": HomeFixture.thumbnail,
        ]
      ]
    }
    let rows = [
      row("MPSPshow", "MUSIC_PAGE_TYPE_PODCAST_SHOW"), row("VLlist", "MUSIC_PAGE_TYPE_PLAYLIST"),
    ]
    let data = try JSONSerialization.data(withJSONObject: [
      "continuationContents": [
        "musicShelfContinuation": [
          "contents": rows, "continuations": [["nextContinuationData": ["continuation": "next"]]],
        ]
      ]
    ])
    let page = try await MusicSearchPage.decode(data, filter: .podcasts)
    XCTAssertEqual(page.items.map(\.mediaId), ["MPSPshow", "VLlist"])
    XCTAssertEqual(page.items.first?.target?.browseId, "MPSPshow")
    XCTAssertEqual(page.continuation, "next")
    let songs = try await MusicSearchPage.decode(data, filter: .songs)
    XCTAssertTrue(songs.items.isEmpty)
  }
}

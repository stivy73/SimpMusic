import Foundation
import XCTest

@testable import PrototypeCore

@MainActor final class DiscoveryExtrasTests: XCTestCase {
  private let account = YouTubeSession(
    cookies: "SAPISID=fixture", identity: "A", clientVersion: "test")
  private func item(_ id: String, kind: DiscoveryItem.Kind = .album) -> DiscoveryItem {
    DiscoveryItem(kind: kind, mediaId: id, title: id, subtitle: "Artista", artwork: nil)
  }
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  func testWidgetSnapshotRoundTripAndNoCredentialsOrSignedURLs() throws {
    let url = try folder()
    defer { try? FileManager.default.removeItem(at: url) }
    let value = WidgetSnapshot(
      track: .init(
        id: "track", title: "Brano", artist: "Artista", duration: 200, elapsed: 90, playing: true),
      playlists: [.init(id: "PLtest", title: "Playlist", subtitle: "Privata")], todaySeconds: 100,
      weekSeconds: 700, weekPlays: 4)
    try value.write(at: url)
    XCTAssertEqual(WidgetSnapshot.read(at: url), value)
    let data = try String(contentsOf: url.appendingPathComponent("widgets.json"), encoding: .utf8)
    for forbidden in ["cookie", "apiKey", "googlevideo", "http"] {
      XCTAssertFalse(data.contains(forbidden))
    }
    XCTAssertEqual(
      WidgetSnapshot.Track(
        id: "x", title: "", artist: "", duration: .nan, elapsed: .infinity, playing: false
      ).elapsed, 0)
    XCTAssertNil(WidgetSnapshot.artworkURL("../secret.jpg", directory: url))
    XCTAssertNotNil(WidgetSnapshot.artworkURL("art-safe.jpg", directory: url))
  }
  func testWidgetCorruptStateIsEmptyAndRoutesAreStrict() throws {
    let url = try folder()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("invalid".utf8).write(to: url.appendingPathComponent("widgets.json"))
    XCTAssertNil(WidgetSnapshot.read(at: url).track)
    for route in [
      AppRoute.player, .library, .statistics, .playlist("VLplaylist_1"), .album("MPREalbum"),
    ] {
      XCTAssertEqual(AppRoute(url: route.url), route)
    }
    for text in [
      "https://example.com/player", "notenarrate://playlist?id=../secret",
      "notenarrate://playlist?id=x&id=y", "notenarrate://player/path",
      "notenarrate://album?id=abc&key=secret", "notenarrate://user:pass@player",
      "notenarrate://player#fragment",
    ] {
      XCTAssertNil(AppRoute(url: URL(string: text)!), text)
    }
  }
  func testMixRequiresAccountAndEmptyErrorIsHonest() async {
    let model = DiscoveryCatalogModel(
      destination: .mixes,
      fetch: { _, _, _, _ in
        XCTFail("No anonymous Mix request")
        return HomePage(shelves: [])
      })
    await model.configure(session: nil)
    XCTAssertFalse(model.loading)
    XCTAssertTrue(model.shelves.isEmpty)
    XCTAssertNotNil(model.error)
  }
  func testPodcastsUseLiveHomeChipRatherThanRetiredEndpoint() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "header": [
        "chips": [
          [
            "chipCloudChipRenderer": [
              "text": ["runs": [["text": "Podcast"]]],
              "navigationEndpoint": [
                "browseEndpoint": ["browseId": "FEmusic_home", "params": "podcast-params"]
              ],
            ]
          ]
        ]
      ]
    ])
    let target = try DiscoveryCatalog.podcastTarget(in: data)
    XCTAssertEqual(target.browseId, "FEmusic_home")
    XCTAssertEqual(target.params, "podcast-params")
    XCTAssertThrowsError(try DiscoveryCatalog.podcastTarget(in: Data("{}".utf8)))
  }
  func testDedicatedChartsPaginationDeduplicatesAndCountryResets() async {
    let model = DiscoveryCatalogModel(
      destination: .charts,
      fetch: { _, destination, country, token in
        XCTAssertEqual(destination, .charts)
        return HomePage(
          shelves: [
            HomeShelf(
              id: "rank", title: "Classifica",
              items: [
                DiscoveryItem(
                  kind: .song, mediaId: country + (token ?? "first"), title: "Brano",
                  subtitle: "Artista", artwork: nil)
              ])
          ], continuation: token == nil ? "next" : nil)
      })
    await model.configure(session: nil, country: "IT")
    await model.more()
    XCTAssertEqual(model.shelves[0].items.map(\.mediaId), ["ITfirst", "ITnext"])
    await model.configure(session: nil, country: "ZZ")
    XCTAssertEqual(model.shelves[0].items.map(\.mediaId), ["ZZfirst"])
  }
  func testStaleDiscoveryCannotOverwriteNewCountry() async throws {
    let model = DiscoveryCatalogModel(
      destination: .charts,
      fetch: { _, _, country, _ in
        if country == "IT" { try await Task.sleep(for: .milliseconds(100)) }
        return HomePage(shelves: [HomeShelf(id: country, title: country, items: [])])
      })
    let old = Task { await model.configure(session: nil, country: "IT") }
    try await Task.sleep(for: .milliseconds(10))
    await model.configure(session: nil, country: "US")
    await old.value
    XCTAssertEqual(model.shelves.map(\.id), ["US"])
  }
  func testReleaseBaselineDedupAndArtistSeparation() {
    let artist = item("UCartist", kind: .artist)
    let other = item("UCother", kind: .artist)
    var state = ArtistReleaseState()
    XCTAssertTrue(state.ingest(artist: artist, releases: [item("old"), item("old")]).isEmpty)
    XCTAssertEqual(
      state.ingest(artist: artist, releases: [item("new"), item("old")]).map(\.release.mediaId),
      ["new"])
    XCTAssertTrue(state.ingest(artist: artist, releases: [item("new")]).isEmpty)
    XCTAssertTrue(state.ingest(artist: other, releases: [item("new")]).isEmpty)
    XCTAssertEqual(state.notices.count, 1)
    XCTAssertTrue(state.ingest(artist: artist, releases: [item("video", kind: .song)]).isEmpty)
  }
  func testReleasePersistenceAccountIsolationAndReenableBaseline() async throws {
    actor Catalog {
      var ids = ["old"]
      func add() { ids = ["new", "old"] }
      func values() -> [DiscoveryItem] {
        ids.map {
          DiscoveryItem(kind: .album, mediaId: $0, title: $0, subtitle: "Artista", artwork: nil)
        }
      }
    }
    let remote = Catalog()
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = ArtistReleases(directory: directory, fetch: { _, _ in await remote.values() })
    let artist = item("UCartist", kind: .artist)
    model.configure(account)
    model.setEnabled(true)
    let initial = await model.check(artists: [artist], force: true)
    XCTAssertTrue(initial.isEmpty)
    await remote.add()
    let added = await model.check(artists: [artist], force: true)
    XCTAssertEqual(added.count, 1)
    model.configure(
      YouTubeSession(cookies: "SAPISID=fixture", identity: "B", clientVersion: "test"))
    XCTAssertFalse(model.state.enabled)
    XCTAssertTrue(model.state.notices.isEmpty)
    model.configure(account)
    XCTAssertEqual(model.state.notices.count, 1)
    model.setEnabled(false)
    model.setEnabled(true)
    let baseline = await model.check(artists: [artist], force: true)
    XCTAssertTrue(baseline.isEmpty)
    model.configure(nil)
    XCTAssertTrue(model.state.notices.isEmpty)
  }
  func testFailedReleaseFetchDoesNotConsumeBaselineOrTimestamp() async throws {
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = ArtistReleases(
      directory: directory, fetch: { _, _ in throw URLError(.notConnectedToInternet) })
    model.configure(account)
    model.setEnabled(true)
    _ = await model.check(artists: [item("UCartist", kind: .artist)], force: true)
    XCTAssertNil(model.state.lastCheck)
    XCTAssertTrue(model.state.known.isEmpty)
    XCTAssertNotNil(model.error)
  }
  func testFollowOnlyCommitsConfirmedWritesAndDoesNotInventState() async {
    let artist = item("UCartist", kind: .artist)
    let model = LibraryModel(
      session: account, save: { _ in }, fetch: { _ in [] }, fetchCollection: { _, _ in [] },
      followArtist: { _, _, _ in throw LibraryError.rejected })
    await model.toggleFollow(artist)
    XCTAssertFalse(model.isFollowed(artist.mediaId))
    XCTAssertTrue(model.pendingFollows.isEmpty)
    XCTAssertNotNil(model.syncError)
    let success = LibraryModel(
      session: account, save: { _ in }, fetch: { _ in [] }, fetchCollection: { _, _ in [] },
      followArtist: { _, id, followed in XCTAssertEqual(id, "UCartist") })
    await success.toggleFollow(artist)
    XCTAssertTrue(success.isFollowed(artist.mediaId))
    await success.toggleFollow(artist)
    XCTAssertFalse(success.isFollowed(artist.mediaId))
  }
  func testSuggestionsRejectInvalidJSONAndFalseCatalogMatch() throws {
    let json =
      #"{"songs":[{"title":"Heroes","artist":"David Bowie","reason":"Rock"},{"title":"Heroes","artist":"David Bowie","reason":"Duplicato"},{"title":"","artist":"X","reason":""}]}"#
    let suggestions = try MusicSuggestion.decode(Data(json.utf8))
    XCTAssertEqual(suggestions.count, 1)
    XCTAssertThrowsError(try MusicSuggestion.decode(Data(#"{"songs":[]}"#.utf8)))
    let sameTitle = DiscoveryItem(
      kind: .song, mediaId: "cover", title: "Heroes", subtitle: "Cover Band", artwork: nil)
    XCTAssertNil(suggestions[0].match(in: [sameTitle]))
    let actual = DiscoveryItem(
      kind: .song, mediaId: "real", title: "Heroes (2017 Remastered)", subtitle: "David Bowie",
      artwork: nil)
    XCTAssertEqual(suggestions[0].match(in: [sameTitle, actual])?.mediaId, "real")
    XCTAssertNil(
      suggestions[0].match(in: [
        DiscoveryItem(
          kind: .song, mediaId: "tribute", title: "Heroes", subtitle: "David Bowie Tribute Band",
          artwork: nil)
      ]))
    XCTAssertNotNil(
      suggestions[0].match(in: [
        DiscoveryItem(
          kind: .song, mediaId: "duet", title: "Heroes", subtitle: "David Bowie, Guest",
          artwork: nil)
      ]))
    let substring = MusicSuggestion(title: "Heroes", artist: "Bowie", reason: "")
    XCTAssertNil(
      substring.match(in: [
        DiscoveryItem(
          kind: .song, mediaId: "fake", title: "Heroes", subtitle: "Bowietribute", artwork: nil)
      ]))
  }
  func testSuggestionsKeepUnavailableVisibleButOnlyVerifiedPlayable() async {
    let model = MusicSuggestionsModel(
      generate: { _, _, _, _ in
        [
          MusicSuggestion(title: "Real", artist: "Artist", reason: "Motivo"),
          MusicSuggestion(title: "Absent", artist: "Artist", reason: "Motivo"),
        ]
      },
      search: { _, query in
        query.hasPrefix("Real")
          ? [
            DiscoveryItem(
              kind: .song, mediaId: "real-id", title: "Real", subtitle: "Artist", artwork: nil)
          ] : []
      })
    await model.start(
      key: "fixture", model: "gemini-test", request: "Rock", seeds: [], session: nil)
    XCTAssertEqual(model.results.count, 2)
    XCTAssertEqual(model.results.compactMap(\.item).count, 1)
    XCTAssertFalse(model.busy)
    model.reset()
    XCTAssertTrue(model.results.isEmpty)
  }
  func testSuggestionCancellationCannotRepopulateOldAccountResults() async throws {
    let model = MusicSuggestionsModel(
      generate: { _, _, _, _ in
        try await Task.sleep(for: .milliseconds(100))
        return [MusicSuggestion(title: "Old", artist: "Artist", reason: "")]
      },
      search: { _, _ in
        XCTFail("Cancelled generation must not search")
        return []
      })
    let task = Task {
      await model.start(key: "fixture", model: "test", request: "Rock", seeds: [], session: account)
    }
    try await Task.sleep(for: .milliseconds(10))
    model.reset()
    await task.value
    XCTAssertTrue(model.results.isEmpty)
    XCTAssertFalse(model.busy)
  }
}


final class GeminiSongRadioTests: XCTestCase {
  private let seed = PlaybackTrack(id: "seed", title: "Seed", artist: "Original", artwork: nil)
  func testFreshGenerationEveryTimeAndRejectsRecentAlternateIDsAndUnverifiedSongs() async throws {
    actor Calls {
      var count = 0
      func next(_ excluded: [PlaybackTrack]) -> Int { count += 1; return count }
    }
    let calls = Calls()
    let radio = GeminiSongRadio(generate: { _, _, _, excluded in
      let number = await calls.next(excluded)
      return [
        MusicSuggestion(title: "Recent", artist: "Artist", reason: ""),
        MusicSuggestion(title: "Fresh \(number)", artist: "Artist", reason: ""),
        MusicSuggestion(title: "Fake", artist: "Wrong", reason: "")]
    }, search: { _, query in
      if query.hasPrefix("Recent") {
        return [DiscoveryItem(kind: .song, mediaId: "alternate-video", title: "Recent (2024 Remastered)", subtitle: "Artist", artwork: nil)]
      }
      if query.hasPrefix("Fresh") {
        let title = String(query.dropLast(" Artist".count))
        return [DiscoveryItem(kind: .song, mediaId: title, title: title, subtitle: "Artist", artwork: nil)]
      }
      return []
    })
    let excluded = [PlaybackTrack(id: "old", title: "Recent", artist: "Artist", artwork: nil)]
    let first = try await radio.songs(seed: seed, excluding: excluded, key: "fixture", model: "fixture", session: nil)
    let second = try await radio.songs(seed: seed, excluding: excluded + first.map(PlaybackTrack.init), key: "fixture", model: "fixture", session: nil)
    XCTAssertEqual(first.map(\.title), ["Fresh 1"])
    XCTAssertEqual(second.map(\.title), ["Fresh 2"])
    let count = await calls.count
    XCTAssertEqual(count, 2)
  }
  func testNoVerifiedNewSongFailsInsteadOfFallingBackToRepeatedYouTubeRadio() async {
    let radio = GeminiSongRadio(generate: { _, _, _, _ in
      [MusicSuggestion(title: "Seed", artist: "Original", reason: "")]
    }, search: { _, _ in
      [DiscoveryItem(kind: .song, mediaId: "other-id", title: "Seed", subtitle: "Original", artwork: nil)]
    })
    do {
      _ = try await radio.songs(seed: seed, excluding: [], key: "fixture", model: "fixture", session: nil)
      XCTFail("A repeated seed was accepted")
    } catch RadioError.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
  }
  func testHistoryIsBoundedDeduplicatesAndSurvivesRelaunch() throws {
    var history = SongRadioHistory()
    history.remember((0..<240).map { PlaybackTrack(id: String($0), title: "Song \($0)", artist: "Artist", artwork: nil) })
    history.remember([PlaybackTrack(id: "new-video", title: "Song 239 (2020 Remaster)", artist: "Artist", artwork: nil)])
    let restored = try JSONDecoder().decode(SongRadioHistory.self, from: JSONEncoder().encode(history))
    XCTAssertEqual(restored.tracks.count, 200)
    XCTAssertEqual(restored.tracks.last?.id, "new-video")
    XCTAssertFalse(restored.tracks.contains { $0.id == "239" })
    XCTAssertEqual(SongRadioHistory.identity(title: "Recent (2024 Remastered)", artist: "ARTIST"), "recent|artist")
  }
}

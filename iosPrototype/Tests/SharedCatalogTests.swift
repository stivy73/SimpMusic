import Foundation
import XCTest

@testable import PrototypeCore

@MainActor final class SharedCatalogTests: XCTestCase {
  private let spotifyID = "37i9dQZF1DXcBWIGoYBM5M"
  private let applePlaylist = "pl.f4d106fed2bd41149aaacabb233eb5eb"
  private func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
  }
  private func html(_ value: Any, id: String) throws -> Data {
    Data(
      ("<script type='application/json' id='\(id)'>"
        + String(decoding: try json(value), as: UTF8.self) + "</script>").utf8)
  }
  private func spotifyEntity(_ kind: SharedCatalogLink.Kind = .playlist, count: Int = 3) -> [String:
    Any]
  {
    [
      "id": spotifyID, "type": kind.rawValue, "name": "Raccolta",
      "artists": [["name": "David Bowie"]], "duration": 200000,
      "trackList": (0..<count).map { n in
        [
          "uri": "spotify:track:" + spotifyID, "entityType": "track", "title": "Brano \(n)",
          "subtitle": "David Bowie", "duration": 200000,
        ]
      },
    ]
  }
  private func spotifyHTML(_ entity: [String: Any]) throws -> Data {
    try html(["props": ["pageProps": ["state": ["data": ["entity": entity]]]]], id: "__NEXT_DATA__")
  }
  private func item(
    _ title: String = "Heroes", artist: String = "David Bowie", duration: Double = 200,
    id: String = "youtube-real"
  ) -> DiscoveryItem {
    .init(
      kind: .song, mediaId: id, title: title, subtitle: artist, artwork: nil,
      durationSeconds: duration)
  }
  func testAllSixLinkTypesAndLocaleTrackingAreCanonicalized() throws {
    for kind in [SharedCatalogLink.Kind.track, .album, .playlist] {
      let spotify = SharedCatalogLink(provider: .spotify, kind: kind, id: spotifyID)
      XCTAssertEqual(
        SharedMusicTarget.parse([
          "https://open.spotify.com/intl-it/\(kind.rawValue)/\(spotifyID)?si=private"
        ]), .catalog(spotify))
      let apple = SharedCatalogLink(
        provider: .appleMusic, kind: kind, id: kind == .playlist ? applePlaylist : "594061856")
      XCTAssertEqual(
        SharedMusicTarget.parse([
          "https://music.apple.com/it/\(kind == .track ? "song" : kind.rawValue)/titolo/\(apple.id)?app=music&ls=1"
        ]), .catalog(apple))
      let roundTrip = try JSONDecoder().decode(
        SharedMusicTarget.self, from: JSONEncoder().encode(SharedMusicTarget.catalog(apple)))
      XCTAssertEqual(roundTrip, .catalog(apple))
      XCTAssertFalse(apple.url.absoluteString.contains("app="))
    }
    XCTAssertEqual(
      SharedMusicTarget.parse([
        "https://music.apple.com/us/album/rumours/594061854?i=594061856&at=tracking"
      ]),
      .catalog(.init(provider: .appleMusic, kind: .track, id: "594061856", country: "us")))
  }
  func testShortLinksLoseTrackingAndDoNotStoreArbitraryHosts() {
    for address in [
      "https://spotify.link/abcDEF123?si=secret", "https://apple.co/3aBcDe?token=secret",
    ] {
      guard case .catalog(let link) = SharedMusicTarget.parse([address]) else {
        return XCTFail(address)
      }
      XCTAssertEqual(link.kind, .shortLink)
      XCTAssertFalse(link.url.absoluteString.contains("secret"))
    }
    for address in [
      "https://open.spotify.com.evil.test/track/\(spotifyID)",
      "https://evil@open.spotify.com/track/\(spotifyID)",
      "https://open.spotify.com:443/album/\(spotifyID)",
      "http://open.spotify.com/track/\(spotifyID)",
      "https://music.apple.com/it/album/594061854?i=594061856&i=594061857",
      "https://spotify.link/a%2E%2E/b",
    ] {
      XCTAssertNil(SharedMusicTarget.parse([address]), address)
    }
    XCTAssertFalse(
      SharedCatalogRedirects.allowed(URL(string: "https://localhost/test")!, provider: .spotify))
    XCTAssertFalse(
      SharedCatalogRedirects.allowed(
        URL(string: "https://music.apple.com/us/song/12345")!, provider: .spotify))
    XCTAssertFalse(
      SharedCatalogRedirects.allowed(
        URL(string: "http://open.spotify.com/track/\(spotifyID)")!, provider: .spotify))
  }
  func testProviderLabelAndInboxKeepTypedCollectionsWithoutTracking() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let inbox = SharedMusicInbox(directory: folder)
    for provider in [SharedCatalogLink.Provider.appleMusic, .spotify] {
      for kind in [SharedCatalogLink.Kind.track, .album, .playlist] {
        let id = provider == .spotify ? spotifyID : kind == .playlist ? applePlaylist : "594061854"
        let target = SharedMusicTarget.catalog(.init(provider: provider, kind: kind, id: id))
        try inbox.save(.init(target: target))
        XCTAssertTrue(target.label.contains(provider.title))
        XCTAssertTrue(target.label.contains(kind.title))
      }
    }
    XCTAssertEqual(inbox.pending().count, 6)
    // Old YouTube requests remain decodable alongside new cases.
    try inbox.save(.init(target: .video("dQw4w9WgXcQ")))
    XCTAssertEqual(inbox.pending().count, 7)
  }
  func testSpotifyTrackAlbumAndPlaylistMetadataKeepAllSourcePositions() throws {
    for kind in [SharedCatalogLink.Kind.track, .album, .playlist] {
      let link = SharedCatalogLink(provider: .spotify, kind: kind, id: spotifyID)
      let collection = try SharedCatalogResolver.spotify(
        spotifyHTML(spotifyEntity(kind, count: 75)), link: link)
      XCTAssertEqual(collection.tracks.count, kind == .track ? 1 : 75)
      XCTAssertEqual(Set(collection.tracks.map(\.id)).count, collection.tracks.count)
      if kind != .track {
        XCTAssertEqual(collection.tracks.last?.title, "Brano 74")
        XCTAssertNotNil(collection.warning)  // The public embed does not prove full playlist coverage.
      }
    }
  }
  func testSpotifyRejectsDifferentIDsEpisodesMissingArtistAndInvalidStructure() throws {
    let link = SharedCatalogLink(provider: .spotify, kind: .playlist, id: spotifyID)
    var entity = spotifyEntity()
    entity["id"] = "wrong"
    XCTAssertThrowsError(try SharedCatalogResolver.spotify(spotifyHTML(entity), link: link))
    entity = spotifyEntity()
    entity["trackList"] = [
      [
        "entityType": "episode", "uri": "spotify:episode:" + spotifyID, "title": "Podcast",
        "subtitle": "Host",
      ]
    ]
    XCTAssertThrowsError(try SharedCatalogResolver.spotify(spotifyHTML(entity), link: link))
    entity = spotifyEntity(.track)
    entity["artists"] = []
    XCTAssertThrowsError(
      try SharedCatalogResolver.spotify(
        spotifyHTML(entity), link: .init(provider: .spotify, kind: .track, id: spotifyID)))
    XCTAssertThrowsError(
      try SharedCatalogResolver.spotify(Data("<html>Login</html>".utf8), link: link))
  }
  func testSpotifyPartialAndOversizedCollectionsAreExplicit() throws {
    let link = SharedCatalogLink(provider: .spotify, kind: .album, id: spotifyID)
    var entity = spotifyEntity(.album)
    entity["totalTracks"] = 20
    let collection = try SharedCatalogResolver.spotify(spotifyHTML(entity), link: link)
    XCTAssertTrue(collection.warning?.contains("3 tracce su 20") == true)
    XCTAssertThrowsError(
      try SharedCatalogResolver.spotify(spotifyHTML(spotifyEntity(.album, count: 501)), link: link))
  }
  func testAppleLookupUsesExactSongAndCompleteAlbumCount() throws {
    let song: [String: Any] = [
      "kind": "song", "trackId": 594_061_856, "collectionId": 594_061_854, "trackName": "Dreams",
      "artistName": "Fleetwood Mac", "trackTimeMillis": 257000,
    ]
    let album: [String: Any] = [
      "wrapperType": "collection", "collectionId": 594_061_854, "collectionName": "Rumours",
      "artistName": "Fleetwood Mac", "trackCount": 1,
    ]
    let data = try json(["results": [album, song]])
    let collection = try SharedCatalogResolver.appleLookup(
      data, link: .init(provider: .appleMusic, kind: .album, id: "594061854"))
    XCTAssertEqual(collection.title, "Rumours")
    XCTAssertNil(collection.warning)
    XCTAssertEqual(collection.tracks.first?.duration, 257)
    let track = try SharedCatalogResolver.appleLookup(
      data, link: .init(provider: .appleMusic, kind: .track, id: "594061856"))
    XCTAssertEqual(track.title, "Dreams")
    XCTAssertEqual(track.total, 1)
    XCTAssertThrowsError(
      try SharedCatalogResolver.appleLookup(
        data, link: .init(provider: .appleMusic, kind: .track, id: "594061857")))
    XCTAssertThrowsError(
      try SharedCatalogResolver.appleLookup(
        data, link: .init(provider: .appleMusic, kind: .album, id: "999999999")))
  }
  func testApplePageScopesTrackListToSharedCollectionAndReportsMissingTracks() throws {
    let link = SharedCatalogLink(provider: .appleMusic, kind: .playlist, id: applePlaylist)
    let rows: [[String: Any]] = (0..<3).map {
      [
        "title": "Brano \($0)", "artistName": "Artista", "duration": 180000,
        "contentDescriptor": ["kind": "song", "identifiers": ["storeAdamID": "\(100000 + $0)"]],
      ]
    }
    let sections: [[String: Any]] = [
      [
        "itemKind": "containerDetailHeaderLockup",
        "items": [["title": "Playlist", "subtitleLinks": [["title": "Curatore"]]]],
      ],
      [
        "itemKind": "trackLockup",
        "containerContentDescriptor": ["identifiers": ["storeAdamID": "recommendation"]],
        "items": rows,
      ],
      [
        "itemKind": "trackLockup",
        "containerContentDescriptor": ["identifiers": ["storeAdamID": applePlaylist]],
        "items": rows,
      ],
    ]
    let page = try html(["data": [["data": ["sections": sections]]]], id: "serialized-server-data")
    var data = page
    data.append(try html(["numTracks": 10], id: "schema:music-playlist"))
    let collection = try SharedCatalogResolver.applePage(data, link: link)
    XCTAssertEqual(collection.tracks.count, 3)
    XCTAssertEqual(collection.tracks.last?.title, "Brano 2")
    XCTAssertTrue(collection.warning?.contains("3 tracce su 10") == true)
    XCTAssertThrowsError(
      try SharedCatalogResolver.applePage(
        data, link: .init(provider: .appleMusic, kind: .playlist, id: "pl.anotherplaylist")))
  }
  func testMatchingRejectsCoversRemixesLiveAndWrongDurations() {
    let source = SharedCatalogTrack(
      id: "source", title: "Heroes", artists: ["David Bowie"], duration: 200)
    XCTAssertNil(
      source.match([
        item(artist: "Cover Band"), item("Heroes (Live)"), item("Heroes (Remix)"),
        item(duration: 400),
      ]))
    XCTAssertEqual(source.match([item("Heroes (2017 Remaster)")])?.title, "Heroes (2017 Remaster)")
    XCTAssertEqual(source.match([item(id: "correct")])?.mediaId, "correct")
    let remix = SharedCatalogTrack(
      id: "source", title: "Heroes (Remix)", artists: ["David Bowie"], duration: 200)
    XCTAssertNil(remix.match([item()]))
  }
  func testAppleSongOnRedirectedAlbumPageSelectsOnlyRequestedTrack() throws {
    let rows: [[String: Any]] = (0..<3).map { index in
      [
        "title": "Brano \(index)", "artistName": "Artista", "duration": 180000,
        "contentDescriptor": ["kind": "song", "identifiers": ["storeAdamID": "\(100000 + index)"]],
      ]
    }
    let sections: [[String: Any]] = [
      [
        "itemKind": "containerDetailHeaderLockup",
        "items": [["title": "Album", "subtitleLinks": [["title": "Artista"]]]],
      ],
      [
        "itemKind": "trackLockup",
        "containerContentDescriptor": ["identifiers": ["storeAdamID": "album"]], "items": rows,
      ],
    ]
    let data = try html(["data": [["data": ["sections": sections]]]], id: "serialized-server-data")
    let collection = try SharedCatalogResolver.applePage(
      data, link: .init(provider: .appleMusic, kind: .track, id: "100001"))
    XCTAssertEqual(collection.title, "Brano 1")
    XCTAssertEqual(collection.tracks.count, 1)
    XCTAssertEqual(collection.total, 1)
    XCTAssertNil(collection.warning)
  }
  func testMatchingRequiresEveryCreditedArtist() {
    let source = SharedCatalogTrack(
      id: "source", title: "Heroes", artists: ["David Bowie", "Queen"], duration: 200)
    XCTAssertNil(source.match([item()]))
    XCTAssertNotNil(source.match([item(artist: "David Bowie, Queen")]))
  }
  func testResolverExpandsShortLinkWithSameProviderOnly() async throws {
    let data = try spotifyHTML(spotifyEntity(.track))
    let resolver = SharedCatalogResolver { _, _ in
      .init(
        data: data,
        url: URL(string: "https://open.spotify.com/track/37i9dQZF1DXcBWIGoYBM5M?si=tracking")!)
    }
    let result = try await resolver.resolve(
      .init(provider: .spotify, kind: .shortLink, id: "spotify.link/abc123"))
    XCTAssertEqual(result.link.kind, .track)
    XCTAssertEqual(result.tracks.count, 1)
    XCTAssertNil(result.link.url.query)
    let bad = SharedCatalogResolver { _, _ in
      .init(data: data, url: URL(string: "https://music.apple.com/us/song/594061856")!)
    }
    do {
      _ = try await bad.resolve(
        .init(provider: .spotify, kind: .shortLink, id: "spotify.link/abc123"))
      XCTFail()
    } catch {}
  }
  func testParallelConversionKeepsOrderAndRetriesFailuresWithoutDroppingSourceRows() async throws {
    let data = try spotifyHTML(spotifyEntity())
    let resolver = SharedCatalogResolver { url, _ in .init(data: data, url: url) }
    let importer = SharedCatalogImport(
      resolver: resolver,
      search: { _, query in
        if query.contains("Brano 1") { throw URLError(.timedOut) }
        if query.contains("Brano 0") { try await Task.sleep(for: .milliseconds(30)) }
        let title = query.replacingOccurrences(of: " David Bowie", with: "")
        return [
          .init(
            kind: .song, mediaId: title, title: title, subtitle: "David Bowie", artwork: nil,
            durationSeconds: 200)
        ]
      })
    await importer.load(.init(provider: .spotify, kind: .playlist, id: spotifyID))
    await importer.resolve(session: nil)
    XCTAssertFalse(importer.busy)
    XCTAssertEqual(importer.completed, 3)
    XCTAssertEqual(importer.orderedMatches.map(\.title), ["Brano 0", "Brano 2"])
    XCTAssertEqual(importer.collection?.tracks.count, 3)
    XCTAssertNotNil(importer.failures[1])
    importer.clearMatches()
    XCTAssertTrue(importer.orderedMatches.isEmpty)
  }
  func testUncertainMatchRequiresExplicitCandidateSelection() async throws {
    let data = try spotifyHTML(spotifyEntity(.track))
    let importer = SharedCatalogImport(
      resolver: .init { url, _ in .init(data: data, url: url) },
      search: { _, _ in
        [
          .init(
            kind: .song, mediaId: "chosen", title: "Raccolta (Live)", subtitle: "David Bowie",
            artwork: nil)
        ]
      })
    await importer.load(.init(provider: .spotify, kind: .track, id: spotifyID))
    await importer.resolve(session: nil)
    XCTAssertTrue(importer.matches.isEmpty)
    importer.choose(item(id: "not-a-candidate"), at: 0)
    XCTAssertTrue(importer.matches.isEmpty)
    importer.choose(importer.candidates[0]![0], at: 0)
    XCTAssertEqual(importer.orderedMatches.first?.mediaId, "chosen")
  }
  func testCancellationDoesNotPublishLateSearchResults() async throws {
    let data = try spotifyHTML(spotifyEntity(.track))
    let importer = SharedCatalogImport(
      resolver: .init { url, _ in .init(data: data, url: url) },
      search: { _, _ in
        try? await Task.sleep(for: .milliseconds(100))
        return [
          .init(
            kind: .song, mediaId: "late", title: "Raccolta", subtitle: "David Bowie", artwork: nil)
        ]
      })
    await importer.load(.init(provider: .spotify, kind: .track, id: spotifyID))
    let task = Task { await importer.resolve(session: nil) }
    try await Task.sleep(for: .milliseconds(20))
    task.cancel()
    await task.value
    XCTAssertTrue(importer.matches.isEmpty)
    XCTAssertFalse(importer.busy)
  }
  func testMissingTrackCanBeFoundWithEditedQueryAndChosenForImport() async throws {
    let data = try spotifyHTML(spotifyEntity(.track))
    let importer = SharedCatalogImport(
      resolver: .init { url, _ in .init(data: data, url: url) },
      search: { _, query in
        if query != "Titolo corretto" { return [] }
        return [
          .init(
            kind: .song, mediaId: "corrected", title: "Titolo corretto", subtitle: "David Bowie",
            artwork: nil)
        ]
      })
    await importer.load(.init(provider: .spotify, kind: .track, id: spotifyID))
    await importer.resolve(session: nil)
    XCTAssertTrue(importer.orderedMatches.isEmpty)
    await importer.searchCandidates(at: 0, query: "Titolo corretto", session: nil)
    XCTAssertEqual(importer.candidates[0]?.count, 1)
    importer.choose(importer.candidates[0]![0], at: 0)
    XCTAssertEqual(importer.orderedMatches.first?.mediaId, "corrected")
  }
}

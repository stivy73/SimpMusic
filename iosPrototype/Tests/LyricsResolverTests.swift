import Foundation
import XCTest

@testable import PrototypeCore

private final class LyricsStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, headers, data) = try Self.handler!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

private actor LyricsCounter {
  var count = 0
  func increment() -> Int {
    count += 1
    return count
  }
}

final class LyricsResolverTests: XCTestCase {
  private let query = LyricsQuery(
    videoID: "video", title: "Ricordi", artist: "Artista di prova", durationSeconds: 180)
  private let words = "Testo originale di prova. Il narratore ricorda una serata con gli amici."

  private func session(
    _ handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)
  ) -> URLSession {
    LyricsStub.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LyricsStub.self]
    return URLSession(configuration: configuration)
  }

  private func record(
    id: Int = 123, title: String = "Ricordi", artist: String = "Artista di prova",
    duration: Double = 180, instrumental: Bool = false, plain: String? = nil, synced: String? = nil
  ) -> LrclibRecord {
    LrclibRecord(
      id: id, trackName: title, artistName: artist, duration: duration,
      instrumental: instrumental, plainLyrics: plain, syncedLyrics: synced)
  }

  private func data(title: String = "Ricordi", artist: String = "Artista di prova") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      [
        "id": 123, "trackName": title, "artistName": artist, "duration": 180,
        "instrumental": false, "plainLyrics": words,
      ]
    ])
  }

  func testPrimarySuccessNeverContactsFallback() async throws {
    let session = session { _ in
      XCTFail("Fallback should not run")
      return (500, [:], Data())
    }
    let words = words
    let resolver = LyricsResolver(session: session, primary: { _ in words })
    let result = try await resolver.resolve(query)
    XCTAssertEqual(result?.source, .youtube)
    XCTAssertEqual(result?.text, words)
  }

  func testMissingPrimarySearchesOnlineWithMetadataAndWithoutCredentials() async throws {
    let payload = try data()
    let session = session { request in
      XCTAssertEqual(request.url?.host, "lrclib.net")
      XCTAssertEqual(request.url?.path, "/api/search")
      let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
      XCTAssertEqual(items.first(where: { $0.name == "track_name" })?.value, "Ricordi")
      XCTAssertEqual(items.first(where: { $0.name == "artist_name" })?.value, "Artista di prova")
      XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")!.contains("NoteNarrate/"))
      XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
      XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
      XCTAssertEqual(request.timeoutInterval, 10)
      return (200, [:], payload)
    }
    let fallback = LyricsCounter()
    let resolver = LyricsResolver(session: session, primary: { _ in nil })
    let result = try await resolver.resolve(query) { _ = await fallback.increment() }
    let calls = await fallback.count
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(result?.source, .lrclib)
    XCTAssertEqual(result?.text, words)
    XCTAssertEqual(result?.sourceURL?.absoluteString, "https://lrclib.net/api/get/123")
    let context = try Interpretation.context(
      title: query.title, artist: query.artist, lyrics: result!.text)
    XCTAssertTrue(context.contains(words))
  }

  func testPrimaryHTTPFailureStillUsesFallback() async throws {
    let payload = try data()
    let resolver = LyricsResolver(
      session: session { _ in (200, [:], payload) },
      primary: { _ in
        throw URLError(.badServerResponse)
      })
    let result = try await resolver.resolve(query)
    XCTAssertEqual(result?.source, .lrclib)
  }

  func testSlowPrimaryFallsBackWithoutConsumingBackgroundTime() async throws {
    let payload = try data()
    let resolver = LyricsResolver(
      session: session { _ in (200, [:], payload) },
      primary: { _ in
        try await Task.sleep(for: .seconds(30))
        return nil
      }, primaryTimeout: .milliseconds(30))
    let start = Date()
    let result = try await resolver.resolve(query)
    XCTAssertEqual(result?.source, .lrclib)
    XCTAssertLessThan(Date().timeIntervalSince(start), 1)
  }

  func testTemporaryFallbackFailureIsRetriedOnce() async throws {
    var calls = 0
    let payload = try data()
    let resolver = LyricsResolver(
      session: session { _ in
        calls += 1
        return calls == 1 ? (503, [:], Data()) : (200, [:], payload)
      }, primary: { _ in nil })
    let result = try await resolver.resolve(query)
    XCTAssertEqual(result?.source, .lrclib)
    XCTAssertEqual(calls, 2)
  }

  func testEmptyResultsRemainEmptyAndAreNotCached() async throws {
    var requests = 0
    let resolver = LyricsResolver(
      session: session { _ in
        requests += 1
        return (200, [:], Data("[]".utf8))
      }, primary: { _ in nil })
    let first = try await resolver.resolve(query)
    let retry = try await resolver.resolve(query)
    XCTAssertNil(first)
    XCTAssertNil(retry)
    XCTAssertEqual(requests, 2)
    XCTAssertThrowsError(
      try Interpretation.context(title: "T", artist: "A", lyrics: first?.text ?? ""))
  }

  func testCacheAvoidsNetworkAndForceRefreshReplacesText() async throws {
    let counter = LyricsCounter()
    let resolver = LyricsResolver(primary: { _ in "Testo di prova \(await counter.increment())" })
    let first = try await resolver.resolve(query)
    let cached = try await resolver.resolve(query)
    XCTAssertEqual(first, cached)
    let refreshed = try await resolver.resolve(query, force: true)
    XCTAssertNotEqual(first, refreshed)
    let calls = await counter.count
    XCTAssertEqual(calls, 2)
  }

  func testRemasterAndTopicSuffixesSearchCleanMetadata() async throws {
    var requestedTitles: [String] = []
    let payload = try data(title: "Sogni", artist: "Artista")
    let resolver = LyricsResolver(
      session: session { request in
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        requestedTitles.append(items.first(where: { $0.name == "track_name" })!.value!)
        if requestedTitles.count == 1 { return (200, [:], Data("[]".utf8)) }
        XCTAssertEqual(items.first(where: { $0.name == "artist_name" })?.value, "Artista")
        return (200, [:], payload)
      }, primary: { _ in nil })
    let result = try await resolver.resolve(
      LyricsQuery(videoID: "x", title: "Sogni (2004 Remaster)", artist: "Artista - Topic"))
    XCTAssertEqual(requestedTitles, ["Sogni (2004 Remaster)", "Sogni"])
    XCTAssertEqual(result?.text, words)
    XCTAssertEqual(LyricsResolver.searchTitle("Sogni (Live)"), "Sogni (Live)")
    XCTAssertEqual(LyricsResolver.searchTitle("Sogni (Parte II)"), "Sogni (Parte II)")
  }

  func testRejectsNamesakeDifferentArtistAndWrongDuration() {
    XCTAssertNil(LyricsResolver.select([record(artist: "Altro artista", plain: words)], for: query))
    XCTAssertNil(LyricsResolver.select([record(title: "Altra canzone", plain: words)], for: query))
    XCTAssertNil(LyricsResolver.select([record(duration: 240, plain: words)], for: query))
    let result = LyricsResolver.select([record(duration: 185, plain: words)], for: query)
    XCTAssertEqual(result?.text, words)
  }

  func testRejectsInstrumentalAndEmptyLyrics() {
    XCTAssertNil(LyricsResolver.select([record(instrumental: true, plain: words)], for: query))
    XCTAssertNil(LyricsResolver.select([record(plain: " \n")], for: query))
    XCTAssertNil(LyricsResolver.usableText("Lyrics not available."))
    XCTAssertNil(LyricsResolver.usableText("<html>Error</html>"))
  }

  func testLRCFallbackRemovesTimestampsAndMetadataPreservingAllLines() {
    let text =
      "[ar:Artista]\n[ti:Ricordi]\n[00:01.20][00:03.00]Prima riga\n[00:04.00]\n[00:05.10]<00:05.10>Seconda <00:06.30>riga"
    let result = LyricsResolver.select([record(synced: text)], for: query)
    XCTAssertEqual(result?.text, "Prima riga\n\nSeconda riga")
  }

  func testChoosesNearestDurationWithValidTextNotFirstRecord() {
    let result = LyricsResolver.select(
      [
        record(id: 1, duration: 189, plain: "Versione lontana"),
        record(id: 2, duration: 180, plain: nil),
        record(id: 3, duration: 181, plain: words),
      ], for: query)
    XCTAssertEqual(result?.text, words)
    XCTAssertTrue(result!.sourceURL!.path.hasSuffix("/3"))
  }

  func testHTTPAndMalformedJSONDoNotBecomeLyrics() async {
    for (status, data) in [(503, Data()), (200, Data("{broken".utf8))] {
      let resolver = LyricsResolver(
        session: session { _ in (status, [:], data) }, primary: { _ in nil })
      do {
        _ = try await resolver.resolve(query)
        XCTFail("Expected error")
      } catch LyricsLookupError.unavailable {} catch { XCTFail("Unexpected error") }
    }
  }

  func testRateLimitHonorsRetryAfterWithoutAnotherRequest() async {
    var requests = 0
    let resolver = LyricsResolver(
      session: session { _ in
        requests += 1
        return (429, ["Retry-After": "120"], Data("Not JSON".utf8))
      }, primary: { _ in nil })
    for _ in 0..<2 {
      do {
        _ = try await resolver.resolve(query)
        XCTFail("Expected limit")
      } catch LyricsLookupError.rateLimited {} catch { XCTFail("Unexpected error") }
    }
    XCTAssertEqual(requests, 1)
  }

  func testCancellationDoesNotStartFallback() async {
    let resolver = LyricsResolver(
      session: session { _ in
        XCTFail("Cancelled")
        return (500, [:], Data())
      },
      primary: { _ in
        try await Task.sleep(for: .seconds(1))
        return nil
      })
    let query = query
    let task = Task { try await resolver.resolve(query) }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {} catch { XCTFail("Unexpected error") }
  }

  func testMissingMetadataDoesNotSendBroadSearch() async throws {
    let resolver = LyricsResolver(
      session: session { _ in
        XCTFail("No artist")
        return (500, [:], Data())
      }, primary: { _ in nil })
    let result = try await resolver.resolve(
      LyricsQuery(videoID: "x", title: "Ricordi", artist: " "))
    XCTAssertNil(result)
  }

  func testCatalogNullDurationAndMalformedRecordDoNotHideValidLyrics() async throws {
    let payload = try JSONSerialization.data(withJSONObject: [
      [
        "id": 7, "trackName": "Ricordi", "artistName": "Artista di prova", "duration": NSNull(),
        "instrumental": false, "plainLyrics": words,
      ],
      ["id": "broken", "trackName": "Ricordi"],
      [
        "id": 123, "trackName": "Ricordi", "artistName": "Artista di prova", "duration": 180,
        "instrumental": false, "plainLyrics": words,
      ],
    ])
    let resolver = LyricsResolver(
      session: session { _ in (200, [:], payload) }, primary: { _ in nil })
    let result = try await resolver.resolve(query)
    XCTAssertEqual(result?.sourceURL?.path, "/api/get/123")
  }

  func testNullDurationWorksWhenPlaybackDurationIsNotYetKnown() async throws {
    let payload = try JSONSerialization.data(withJSONObject: [
      [
        "id": 7, "trackName": "Ricordi", "artistName": "Artista di prova", "duration": NSNull(),
        "instrumental": false, "plainLyrics": words,
      ]
    ])
    let resolver = LyricsResolver(
      session: session { _ in (200, [:], payload) }, primary: { _ in nil })
    let result = try await resolver.resolve(
      LyricsQuery(videoID: "x", title: "Ricordi", artist: "Artista di prova"))
    XCTAssertEqual(result?.text, words)
  }
}

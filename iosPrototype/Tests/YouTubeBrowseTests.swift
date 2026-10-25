import Foundation
import XCTest

@testable import PrototypeCore

private final class BrowseProtocolStore: @unchecked Sendable {
  struct Entry {
    let status: Int
    let body: Data
    var requests: [URLRequest] = []
  }
  private let lock = NSLock()
  private var entries: [String: Entry] = [:]
  func register(status: Int, body: Data) -> String {
    lock.withLock {
      let id = UUID().uuidString
      entries[id] = Entry(status: status, body: body)
      return id
    }
  }
  func receive(_ request: URLRequest) -> Entry? {
    lock.withLock {
      guard let id = request.value(forHTTPHeaderField: "X-Home-Test"), var entry = entries[id]
      else { return nil }
      entry.requests.append(request)
      entries[id] = entry
      return entry
    }
  }
  func requests(_ id: String) -> [URLRequest] { lock.withLock { entries[id]?.requests ?? [] } }
  func remove(_ id: String) { _ = lock.withLock { entries.removeValue(forKey: id) } }
}

private final class BrowseURLProtocol: URLProtocol, @unchecked Sendable {
  static let store = BrowseProtocolStore()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let entry = Self.store.receive(request), let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let response = HTTPURLResponse(
      url: url, statusCode: entry.status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: entry.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

final class YouTubeBrowseTests: XCTestCase {
  private func transport(status: Int = 200, body: String = "{}") -> (URLSession, String) {
    let id = BrowseURLProtocol.store.register(status: status, body: Data(body.utf8))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BrowseURLProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Home-Test": id]
    return (URLSession(configuration: configuration), id)
  }
  private func payload(_ request: URLRequest) throws -> [String: Any] {
    let data: Data
    if let body = request.httpBody {
      data = body
    } else if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var result = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(contentsOf: buffer.prefix(count))
      }
      data = result
    } else {
      throw URLError(.cannotParseResponse)
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func testLikeWritesUseAuthenticatedAccountAndCorrectEndpoints() async throws {
    let (transport, id) = transport(body: "{\"status\":\"STATUS_SUCCEEDED\"}")
    defer { BrowseURLProtocol.store.remove(id) }
    let session = YouTubeSession(
      cookies: "SAPISID=test", accountIndex: "2", delegatedID: "brand",
      identity: "test", clientVersion: "test-version")
    let browse = YouTubeBrowse(session: session, transport: transport)
    try await browse.setLiked(videoID: "song", liked: true)
    try await browse.setLiked(videoID: "song", liked: false)
    let requests = BrowseURLProtocol.store.requests(id)
    XCTAssertEqual(
      requests.map { $0.url!.path }, ["/youtubei/v1/like/like", "/youtubei/v1/like/removelike"])
    for request in requests {
      XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-AuthUser"), "2")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-PageId"), "brand")
      let json = try payload(request)
      XCTAssertEqual((json["target"] as? [String: String])?["videoId"], "song")
    }
  }

  func testAnonymousLikeNeverReachesNetwork() async {
    let (transport, id) = transport()
    defer { BrowseURLProtocol.store.remove(id) }
    do {
      try await YouTubeBrowse(session: nil, transport: transport).setLiked(
        videoID: "s", liked: true)
      XCTFail("Anonymous mutation allowed")
    } catch {}
    XCTAssertTrue(BrowseURLProtocol.store.requests(id).isEmpty)
  }

  func testFailedLikeResponsesAreRejectedEvenWithHTTP200() async {
    for body in ["{\"error\":{\"code\":403}}", "{\"status\":\"STATUS_FAILED\"}"] {
      let (transport, id) = transport(body: body)
      defer { BrowseURLProtocol.store.remove(id) }
      let account = YouTubeSession(cookies: "SAPISID=test", identity: "test", clientVersion: "test")
      do {
        try await YouTubeBrowse(session: account, transport: transport).setLiked(
          videoID: "s", liked: true)
        XCTFail("Rejected write was reported as success")
      } catch {}
    }
  }

  func testPlaylistCreationIsPrivateAndEditsPreserveOccurrenceIDs() async throws {
    let (transport, id) = transport(
      body: "{\"status\":\"STATUS_SUCCEEDED\",\"playlistId\":\"PLnew\"}")
    defer { BrowseURLProtocol.store.remove(id) }
    let session = YouTubeSession(cookies: "SAPISID=test", identity: "A", clientVersion: "test")
    let browse = YouTubeBrowse(session: session, transport: transport)
    let created = try await browse.createPlaylist(title: "My playlist", videoIDs: ["song"])
    XCTAssertEqual(created, "PLnew")
    try await browse.editPlaylist(
      id: "VLPLnew", action: .remove(videoID: "song", setID: "occurrence"))
    try await browse.editPlaylist(id: "VLPLnew", action: .move(setID: "occurrence", before: "next"))
    try await browse.deletePlaylist(id: "VLPLnew")
    let requests = BrowseURLProtocol.store.requests(id)
    let create = try payload(requests[0])
    XCTAssertEqual(create["privacyStatus"] as? String, "PRIVATE")
    XCTAssertEqual(create["videoIds"] as? [String], ["song"])
    let remove = try payload(requests[1])
    XCTAssertEqual(remove["playlistId"] as? String, "PLnew")
    let action = try XCTUnwrap((remove["actions"] as? [[String: String]])?.first)
    XCTAssertEqual(action["setVideoId"], "occurrence")
    XCTAssertEqual(action["removedVideoId"], "song")
    XCTAssertEqual(requests[3].url?.path, "/youtubei/v1/playlist/delete")
  }

  func testTypedSearchSendsQueryAndServerFilterOnSearchEndpoint() async throws {
    let (transport, id) = transport()
    defer { BrowseURLProtocol.store.remove(id) }
    let browse = YouTubeBrowse(session: nil, transport: transport)
    for filter in MusicSearchFilter.allCases {
      _ = try await browse.search(query: "Fleetwood Mac", filter: filter)
    }
    let requests = BrowseURLProtocol.store.requests(id)
    XCTAssertEqual(requests.count, MusicSearchFilter.allCases.count)
    var params = Set<String>()
    for request in requests {
      XCTAssertEqual(request.url?.path, "/youtubei/v1/search")
      let json = try payload(request)
      XCTAssertEqual(json["query"] as? String, "Fleetwood Mac")
      XCTAssertNil(json["browseId"])
      params.insert(try XCTUnwrap(json["params"] as? String))
    }
    XCTAssertEqual(params.count, MusicSearchFilter.allCases.count)
  }

  func testSearchContinuationKeepsAccountVisitorAndUsesSearchNotBrowse() async throws {
    let (transport, id) = transport(body: "{\"responseContext\":{\"visitorData\":\"visitor\"}}")
    defer { BrowseURLProtocol.store.remove(id) }
    let session = YouTubeSession(
      cookies: "SAPISID=fixture", accountIndex: "2", delegatedID: "brand", identity: "test",
      clientVersion: "version")
    let browse = YouTubeBrowse(session: session, transport: transport)
    _ = try await browse.search(query: "Rock", filter: .communityPlaylists)
    _ = try await browse.search(
      query: "Rock", filter: .communityPlaylists, continuation: "next+token/=")
    let requests = BrowseURLProtocol.store.requests(id)
    let initial = try payload(requests[0])
    XCTAssertEqual(initial["params"] as? String, MusicSearchFilter.communityPlaylists.params)
    let request = requests[1]
    XCTAssertEqual(request.url?.path, "/youtubei/v1/search")
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertTrue(request.url!.absoluteString.contains("next%2Btoken"))
    XCTAssertEqual(query.first { $0.name == "ctoken" }?.value, "next+token/=")
    XCTAssertEqual(query.first { $0.name == "continuation" }?.value, "next+token/=")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-AuthUser"), "2")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-PageId"), "brand")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id"), "visitor")
    XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
    let next = try payload(request)
    XCTAssertEqual(next["continuation"] as? String, "next+token/=")
    XCTAssertNil(next["query"])
    XCTAssertNil(next["params"])
    XCTAssertNil(next["browseId"])
  }

  func testPlayerReusesTheConfirmedAccountAndExistingSDKParser() async throws {
    let body = #"""
      {"videoDetails":{"videoId":"fixture-video","title":"Fixture","viewCount":"1","author":"Artist","channelId":"artist","lengthSeconds":"180"},
       "streamingData":{"adaptiveFormats":[{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"https://media.googlevideo.com/audio"}]}}
      """#
    let (transport, id) = transport(body: body)
    defer { BrowseURLProtocol.store.remove(id) }
    let session = YouTubeSession(
      cookies: "SAPISID=fixture", accountIndex: "2",
      delegatedID: "brand-account", identity: "test", clientVersion: "fixture-version")
    let player = try await YouTubeBrowse(session: session, transport: transport).player(
      videoID: "fixture-video")
    XCTAssertEqual(player.id, "fixture-video")
    XCTAssertEqual(YouTubeAudio.candidates(player).first?.host, "media.googlevideo.com")
    let request = try XCTUnwrap(BrowseURLProtocol.store.requests(id).first)
    XCTAssertEqual(
      request.url?.absoluteString, "https://music.youtube.com/youtubei/v1/player?prettyPrint=false")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SAPISID=fixture")
    XCTAssertTrue(
      request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-AuthUser"), "2")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-PageId"), "brand-account")
    let json = try payload(request)
    XCTAssertEqual(json["videoId"] as? String, "fixture-video")
    XCTAssertNil(json["browseId"])
    XCTAssertNil(json["continuation"])
    let context = try XCTUnwrap(json["context"] as? [String: Any])
    let client = try XCTUnwrap(context["client"] as? [String: Any])
    XCTAssertEqual(client["clientName"] as? String, "WEB_REMIX")
    XCTAssertEqual(client["clientVersion"] as? String, "fixture-version")
  }

  func testAuthenticationAccountParamsAndVisitorSurviveContinuation() async throws {
    let (transport, id) = transport(
      body: "{\"responseContext\":{\"visitorData\":\"fixture-visitor\"}}")
    defer { BrowseURLProtocol.store.remove(id) }
    let session = YouTubeSession(
      cookies: "SAPISID=fixture", accountIndex: "2", delegatedID: "brand-account", identity: "test",
      clientVersion: "test-version")
    let browse = YouTubeBrowse(session: session, transport: transport)
    _ = try await browse.request(browseId: "FEmusic_home", params: "relax")
    _ = try await browse.request(browseId: "FEmusic_home", token: "next")
    let requests = BrowseURLProtocol.store.requests(id)
    XCTAssertEqual(requests.count, 2)
    let first = try XCTUnwrap(requests.first)
    XCTAssertEqual(first.url?.host, "music.youtube.com")
    XCTAssertEqual(first.httpMethod, "POST")
    XCTAssertTrue(
      first.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
    XCTAssertEqual(first.value(forHTTPHeaderField: "Cookie"), session.cookies)
    XCTAssertEqual(first.value(forHTTPHeaderField: "X-Goog-AuthUser"), "2")
    XCTAssertEqual(first.value(forHTTPHeaderField: "X-Goog-PageId"), "brand-account")
    let initial = try payload(first)
    XCTAssertEqual(initial["browseId"] as? String, "FEmusic_home")
    XCTAssertEqual(initial["params"] as? String, "relax")
    let config = try XCTUnwrap(initial["context"] as? [String: Any])
    let client = try XCTUnwrap(config["client"] as? [String: Any])
    XCTAssertEqual(client["clientName"] as? String, "WEB_REMIX")
    XCTAssertEqual(client["clientVersion"] as? String, "test-version")
    XCTAssertEqual(client["hl"] as? String, "it")
    XCTAssertEqual(client["gl"] as? String, "IT")
    XCTAssertEqual(
      (config["user"] as? [String: Any])?["onBehalfOfUser"] as? String, "brand-account")
    let second = requests[1]
    XCTAssertEqual(second.value(forHTTPHeaderField: "X-Goog-Visitor-Id"), "fixture-visitor")
    let continued = try payload(second)
    XCTAssertEqual(continued["continuation"] as? String, "next")
    XCTAssertNil(continued["browseId"])
    XCTAssertNil(continued["params"])
    let continuedClient = (continued["context"] as? [String: Any])?["client"] as? [String: Any]
    XCTAssertEqual(continuedClient?["visitorData"] as? String, "fixture-visitor")
  }

  func testRadioNextKeepsWatchContextAndAuthenticatedDelegatedAccount() async throws {
    let (transport, id) = transport()
    defer { BrowseURLProtocol.store.remove(id) }
    let session = YouTubeSession(
      cookies: "SAPISID=test", accountIndex: "2", delegatedID: "brand", identity: "fixture",
      clientVersion: "version")
    let browse = YouTubeBrowse(session: session, transport: transport)
    let endpoint = RadioEndpoint(
      videoID: "seed", playlistID: "RDradio", params: "server-params", index: 3,
      playlistSetVideoID: "occurrence")
    _ = try await browse.next(endpoint: endpoint, continuation: "next-token")
    let request = try XCTUnwrap(BrowseURLProtocol.store.requests(id).first)
    XCTAssertEqual(request.url?.path, "/youtubei/v1/next")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-AuthUser"), "2")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-PageId"), "brand")
    XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
    let json = try payload(request)
    XCTAssertEqual(json["videoId"] as? String, "seed")
    XCTAssertEqual(json["playlistId"] as? String, "RDradio")
    XCTAssertEqual(json["playlistSetVideoId"] as? String, "occurrence")
    XCTAssertEqual(json["index"] as? Int, 3)
    XCTAssertEqual(json["params"] as? String, "server-params")
    XCTAssertEqual(json["continuation"] as? String, "next-token")
    XCTAssertNil(json["browseId"])
  }

  func testAnonymousHomeHasNoAuthenticationHeaders() async throws {
    let (transport, id) = transport()
    defer { BrowseURLProtocol.store.remove(id) }
    _ = try await YouTubeBrowse(session: nil, transport: transport).request(
      browseId: "FEmusic_home")
    let request = try XCTUnwrap(BrowseURLProtocol.store.requests(id).first)
    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(request.value(forHTTPHeaderField: "X-Goog-AuthUser"))
  }

  func testHTTPAndExpiredAuthenticationErrors() async throws {
    let session = YouTubeSession(
      cookies: "SAPISID=fixture", identity: "test", clientVersion: "version")
    for status in [401, 403, 302, 500] {
      let (transport, id) = transport(status: status)
      defer { BrowseURLProtocol.store.remove(id) }
      do {
        _ = try await YouTubeBrowse(session: session, transport: transport).request(
          browseId: "FEmusic_home")
        XCTFail("HTTP failure must propagate")
      } catch LibraryError.authentication {
        XCTAssertNotEqual(status, 500)
      } catch LibraryError.http(let code) { XCTAssertEqual(code, 500) }
    }
    let body =
      "{\"responseContext\":{\"serviceTrackingParams\":[{\"params\":[{\"key\":\"logged_in\",\"value\":\"0\"}]}]}}"
    let (transport, id) = transport(body: body)
    defer { BrowseURLProtocol.store.remove(id) }
    do {
      _ = try await YouTubeBrowse(session: session, transport: transport).request(
        browseId: "FEmusic_home")
      XCTFail("Expired session must not show anonymous data as personal")
    } catch LibraryError.authentication {}
  }
}

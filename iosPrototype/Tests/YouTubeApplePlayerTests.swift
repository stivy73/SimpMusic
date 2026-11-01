import Foundation
import XCTest

@testable import PrototypeCore

private final class ApplePlayerProtocolStore: @unchecked Sendable {
  struct Captured {
    let request: URLRequest
    let body: Data
  }
  struct Response {
    let status: Int
    let body: Data
  }
  private struct Entry {
    let pages: [Data]
    let player: Response
    var requests: [Captured] = []
    var pageCount = 0
  }
  private let lock = NSLock()
  private var entries: [String: Entry] = [:]

  func register(pages: [String], player: Data, playerStatus: Int = 200) -> String {
    lock.withLock {
      let id = UUID().uuidString
      entries[id] = Entry(pages: pages.map { Data($0.utf8) },
        player: Response(status: playerStatus, body: player))
      return id
    }
  }
  func receive(_ request: URLRequest) -> Response? {
    let captured = Captured(request: request, body: Self.body(request))
    return lock.withLock {
      guard let id = request.value(forHTTPHeaderField: "X-Apple-Player-Test"),
        var entry = entries[id], request.url?.host == "www.youtube.com"
      else { return nil }
      entry.requests.append(captured)
      let response: Response?
      switch request.url?.path {
      case "/":
        response = entry.pages.indices.contains(entry.pageCount)
          ? Response(status: 200, body: entry.pages[entry.pageCount]) : nil
        entry.pageCount += 1
      case "/youtubei/v1/player": response = entry.player
      default: response = nil
      }
      entries[id] = entry
      return response
    }
  }
  func requests(_ id: String) -> [Captured] { lock.withLock { entries[id]?.requests ?? [] } }
  func remove(_ id: String) { _ = lock.withLock { entries.removeValue(forKey: id) } }

  private static func body(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var bytes = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&bytes, maxLength: bytes.count)
      guard count > 0 else { break }
      data.append(contentsOf: bytes.prefix(count))
    }
    return data
  }
}

private final class ApplePlayerURLProtocol: URLProtocol, @unchecked Sendable {
  static let store = ApplePlayerProtocolStore()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let response = Self.store.receive(request), let url = request.url,
      let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

final class YouTubeApplePlayerTests: XCTestCase {
  private let videoID = "KUZ77IZxTME"

  func testBootstrapVisitorAndAnonymousIdentityMatchPlayerRequest() async throws {
    let (transport, id) = try fixture(pages: [page(visitor: "visitor%2Bfixture=")])
    defer { transport.invalidateAndCancel(); ApplePlayerURLProtocol.store.remove(id) }
    let video = try await YouTubeApplePlayer(transport: transport).video(id: videoID)
    XCTAssertEqual(video.id, videoID)
    let requests = ApplePlayerURLProtocol.store.requests(id)
    XCTAssertEqual(requests.map { $0.request.url!.path }, ["/", "/youtubei/v1/player"])
    XCTAssertEqual(requests.map { $0.request.httpMethod }, ["GET", "POST"])
    let request = requests[1].request
    let body = try payload(requests[1])
    let context = try XCTUnwrap(body["context"] as? [String: Any])
    let client = try XCTUnwrap(context["client"] as? [String: Any])
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id"), "visitor%2Bfixture=")
    XCTAssertEqual(client["visitorData"] as? String, "visitor%2Bfixture=")
    XCTAssertEqual(client["clientName"] as? String, "VISIONOS")
    XCTAssertEqual(client["clientVersion"] as? String,
      request.value(forHTTPHeaderField: "X-YouTube-Client-Version"))
    XCTAssertEqual(client["userAgent"] as? String,
      request.value(forHTTPHeaderField: "User-Agent"))
    XCTAssertEqual(body["videoId"] as? String, videoID)
    XCTAssertNil(context["user"])
    for captured in requests {
      XCTAssertEqual(captured.request.value(forHTTPHeaderField: "User-Agent"),
        YouTubeApplePlayer.userAgent)
      for header in ["Cookie", "Authorization", "X-Goog-AuthUser", "X-Goog-PageId"] {
        XCTAssertNil(captured.request.value(forHTTPHeaderField: header))
      }
    }
  }

  func testSubsequentResolutionBootstrapsANewVisitorInsteadOfReusingOldIdentity() async throws {
    let (transport, id) = try fixture(pages: [page(visitor: "visitor-one"), page(visitor: "visitor-two")])
    defer { transport.invalidateAndCancel(); ApplePlayerURLProtocol.store.remove(id) }
    let player = YouTubeApplePlayer(transport: transport)
    _ = try await player.video(id: videoID)
    _ = try await player.video(id: videoID)
    let requests = ApplePlayerURLProtocol.store.requests(id)
    XCTAssertEqual(requests.map { $0.request.url!.path },
      ["/", "/youtubei/v1/player", "/", "/youtubei/v1/player"])
    let playerRequests = requests.filter { $0.request.httpMethod == "POST" }
    XCTAssertEqual(playerRequests.map { $0.request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") },
      ["visitor-one", "visitor-two"])
    for (captured, expected) in zip(playerRequests, ["visitor-one", "visitor-two"]) {
      let body = try payload(captured)
      XCTAssertEqual((body["context"] as? [String: [String: Any]])?["client"]?["visitorData"]
        as? String, expected)
    }
  }

  func testMissingVisitorStopsBeforePlayerRequest() async throws {
    let (transport, id) = try fixture(pages: ["<html>Consent required</html>"])
    defer { transport.invalidateAndCancel(); ApplePlayerURLProtocol.store.remove(id) }
    do {
      _ = try await YouTubeApplePlayer(transport: transport).video(id: videoID)
      XCTFail("A player request without a bound visitor must not be sent")
    } catch {}
    XCTAssertEqual(ApplePlayerURLProtocol.store.requests(id).map { $0.request.url!.path }, ["/"])
  }

  func testNonPlayableResponseIsRejectedEvenWhenDetailsAndStreamArePresent() async throws {
    let (transport, id) = try fixture(pages: [page(visitor: "visitor-one")], status: "LOGIN_REQUIRED")
    defer { transport.invalidateAndCancel(); ApplePlayerURLProtocol.store.remove(id) }
    do {
      _ = try await YouTubeApplePlayer(transport: transport).video(id: videoID)
      XCTFail("A blocked player response must not become a playable source")
    } catch {}
    XCTAssertEqual(ApplePlayerURLProtocol.store.requests(id).count, 2)
  }

  func testDiagnosticDoesNotExposeVisitorTrackOrSignedMediaAddress() async throws {
    let (transport, id) = try fixture(pages: [page(visitor: "private-visitor-token")])
    defer { transport.invalidateAndCancel(); ApplePlayerURLProtocol.store.remove(id) }
    let trace = AudioResolutionTrace()
    _ = try await YouTubeApplePlayer(transport: transport).video(id: videoID,
      diagnostic: { trace.record($0) })
    XCTAssertTrue(trace.report.contains("client=VISIONOS"))
    XCTAssertTrue(trace.report.contains("HTTP 200"))
    for secret in ["private-visitor-token", videoID, "private-title", "private-signature",
      "private-provider-reason", "googlevideo.com", "https://"] {
      XCTAssertFalse(trace.report.contains(secret))
    }
  }

  private func page(visitor: String) -> String { #"<script>ytcfg.set({"VISITOR_DATA":"\#(visitor)"});</script>"# }

  private func fixture(pages: [String], status: String = "OK") throws -> (URLSession, String) {
    let player = try JSONSerialization.data(withJSONObject: [
      "playabilityStatus": ["status": status, "reason": "private-provider-reason"],
      "videoDetails": ["videoId": videoID, "title": "private-title", "author": "Fixture",
        "viewCount": "0", "channelId": "fixture", "lengthSeconds": "275"],
      "streamingData": ["adaptiveFormats": [["itag": 140, "bitrate": 128000,
        "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "contentLength": "4440476",
        "url": "https://fixture.googlevideo.com/audio?sig=private-signature"]]],
    ])
    let id = ApplePlayerURLProtocol.store.register(pages: pages, player: player)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ApplePlayerURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Apple-Player-Test": id]
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    return (URLSession(configuration: config), id)
  }
  private func payload(_ request: ApplePlayerProtocolStore.Captured) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
  }
}

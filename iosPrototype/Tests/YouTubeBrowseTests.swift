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

import Foundation
import XCTest
import YouTubeSDK
@testable import PrototypeCore

final class HLSBodyReaderTests: XCTestCase {
  private static func resolve(_ path: String, session: URLSession) async throws -> YouTubeAudio.Source {
    let video = try JSONDecoder().decode(YouTubeVideo.self, from: JSONSerialization.data(withJSONObject: [
      "videoDetails": ["videoId": "fixture", "title": "Fixture", "author": "Test",
        "channelId": "artist", "viewCount": "1", "lengthSeconds": "3600"],
      "streamingData": ["adaptiveFormats": [], "hlsManifestUrl": "https://fixture.googlevideo.com/" + path],
    ]))
    return try await YouTubeAudio(transport: session).source(
      video: video, userAgent: "Test", authenticated: false, quality: .high)
  }

  private func transport() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [HLSChunkProtocol.self]
    return URLSession(configuration: config)
  }

  func testRejectsOversizedChunkedManifestEvenWithIncorrectContentLength() async throws {
    let session = transport()
    defer { session.invalidateAndCancel() }
    do {
      _ = try await Self.resolve("oversized.m3u8", session: session)
      XCTFail("Reader accepted an unfinished oversized manifest")
    } catch is AudioPlaybackError {}
  }

  func testSegmentProbeFinishesAfterSampleWhenServerIgnoresRange() async throws {
    let session = transport()
    defer { session.invalidateAndCancel() }
    let source = try await Self.resolve("sample.m3u8", session: session)
    XCTAssertTrue(source.isHLS)
  }

  func testCancelledManifestRequestTerminatesWithoutEndOfBody() async throws {
    let headersSent = XCTestExpectation(description: "Stalled response sent its headers")
    HLSChunkProtocol.headersSent = headersSent
    let session = transport()
    defer { session.invalidateAndCancel(); HLSChunkProtocol.headersSent = nil }
    let loading = Task { try await Self.resolve("stalled.m3u8", session: session) }
    await fulfillment(of: [headersSent], timeout: 3)
    loading.cancel()
    do {
      _ = try await loading.value
      XCTFail("Cancelled request returned a source")
    } catch is CancellationError {}
  }
}

private final class HLSChunkProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var headersSent: XCTestExpectation?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!
    let headers = url.lastPathComponent == "oversized.m3u8" ? ["Content-Length": "64"] : [:]
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    switch url.lastPathComponent {
    case "oversized.m3u8":
      for _ in 0..<64 {
        client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 65_536))
      }
    case "sample.m3u8":
      client?.urlProtocol(self, didLoad: Data("#EXTM3U\n#EXTINF:3600,\n".utf8))
      client?.urlProtocol(self, didLoad: Data("segment.ts\n#EXT-X-ENDLIST\n".utf8))
      client?.urlProtocolDidFinishLoading(self)
    case "segment.ts":
      XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-1023")
      client?.urlProtocol(self, didLoad: Data(repeating: 2, count: 512))
      client?.urlProtocol(self, didLoad: Data(repeating: 3, count: 8192))
    case "stalled.m3u8":
      Self.headersSent?.fulfill()
    default:
      XCTFail("Unexpected URL path")
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    // Except for sample.m3u8, the peer leaves the request open.
  }

  override func stopLoading() {}
}

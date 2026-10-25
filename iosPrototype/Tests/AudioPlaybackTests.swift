import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

final class AudioPlaybackTests: XCTestCase {
  func testRangeRequestPreservesSignatureAndUsesOneAbsoluteRange() throws {
    let source = YouTubeAudio.Source(
      url: URL(string: "https://a.googlevideo.com/audio?signature=test%2Btoken&range=0-1")!,
      duration: 10, userAgent: "Client", byteCount: 10_000, isHLS: false)
    let request = try AudioRangeLoader.rangeRequest(source: source, offset: 100, last: 499)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=100-499")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Client")
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.filter { $0.name == "range" }.count, 0)
    XCTAssertEqual(query?.first { $0.name == "signature" }?.value, "test+token")
    XCTAssertThrowsError(try AudioRangeLoader.rangeRequest(source: source, offset: -1, last: 0))
    XCTAssertThrowsError(try AudioRangeLoader.rangeRequest(source: source, offset: 100, last: 99))
  }
  func testNativeAudioPrefersAACThenHLSAndDeduplicates() throws {
    let payload = #"""
      {"videoDetails":{"videoId":"track","title":"Song","viewCount":"1","author":"Artist","channelId":"artist"},
      "streamingData":{"adaptiveFormats":[
        {"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":256000,"url":"https://a.googlevideo.com/opus"},
        {"itag":139,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":48000,"url":"https://a.googlevideo.com/low"},
        {"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"https://a.googlevideo.com/high"},
        {"itag":141,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"https://a.googlevideo.com/high"}
      ],"hlsManifestUrl":"https://manifest.googlevideo.com/hls"}}
      """#
    let video = try JSONDecoder().decode(YouTubeVideo.self, from: Data(payload.utf8))
    XCTAssertEqual(YouTubeAudio.candidates(video).map(\.lastPathComponent), ["high", "low", "hls"])
    XCTAssertEqual(
      YouTubeAudio.candidates(video, quality: .saver).map(\.lastPathComponent),
      ["low", "high", "hls"])
    XCTAssertEqual(
      YouTubeAudio.candidates(video, quality: .normal).first?.lastPathComponent, "high")
  }

  func testRejectsMissingEncryptedInsecureAndForeignStreams() throws {
    let payload = #"""
      {"videoDetails":{"videoId":"track","title":"Song","viewCount":"1","author":"Artist","channelId":"artist"},
      "streamingData":{"adaptiveFormats":[
        {"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"signatureCipher":"cipher"},
        {"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"http://a.googlevideo.com/insecure"},
        {"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":128000,"url":"https://googlevideo.com.example.org/foreign"}
      ]}}
      """#
    let video = try JSONDecoder().decode(YouTubeVideo.self, from: Data(payload.utf8))
    XCTAssertTrue(YouTubeAudio.candidates(video).isEmpty)
  }

  func testPauseDuringLoadAndInterruptionDoesNotResume() {
    var state = PlaybackIntent()
    let old = state.load()
    state.pause()
    XCTAssertFalse(state.wantsPlayback)
    state.interruptionBegan()
    XCTAssertFalse(state.interruptionEnded(shouldResume: true))
    let new = state.load()
    XCTAssertNotEqual(old, new)
    state.interruptionBegan()
    state.pause()
    XCTAssertFalse(state.interruptionEnded(shouldResume: true))
  }
  func testOnlySameTrackAndAllowedInterruptionResumes() {
    var state = PlaybackIntent()
    state.load()
    state.interruptionBegan()
    XCTAssertTrue(state.interruptionEnded(shouldResume: true))
    state.interruptionBegan()
    XCTAssertFalse(state.interruptionEnded(shouldResume: false))
    state.play()
    state.interruptionBegan()
    state.load()
    XCTAssertFalse(state.interruptionEnded(shouldResume: true))
    XCTAssertTrue(state.wantsPlayback)
  }
}

private final class RangeStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, headers, bytes) = try Self.handler!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: bytes)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

private final class RangeCalls: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Int64: Int] = [:]
  func add(_ offset: Int64) -> Int {
    lock.withLock {
      values[offset, default: 0] += 1
      return values[offset]!
    }
  }
  func count(_ offset: Int64) -> Int { lock.withLock { values[offset, default: 0] } }
}

final class AudioRangeBufferTests: XCTestCase {
  private func buffer(
    blocks: Int = 12, handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)
  ) -> AudioRangeBuffer {
    RangeStub.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RangeStub.self]
    return AudioRangeBuffer(
      source: YouTubeAudio.Source(
        url: URL(string: "https://test.googlevideo.com/audio")!, duration: 200,
        userAgent: "Test", byteCount: Int64(blocks) * AudioRangeBuffer.blockSize, isHLS: false),
      session: URLSession(configuration: config))
  }
  private func response(_ request: URLRequest, blocks: Int = 12) throws -> (
    Int, [String: String], Data
  ) {
    let values = try XCTUnwrap(request.value(forHTTPHeaderField: "Range")).dropFirst(6).split(
      separator: "-")
    let first = try XCTUnwrap(Int64(values[0]))
    let last = try XCTUnwrap(Int64(values[1]))
    return (
      206,
      ["Content-Range": "bytes \(first)-\(last)/\(Int64(blocks) * AudioRangeBuffer.blockSize)"],
      Data(repeating: UInt8(first / AudioRangeBuffer.blockSize), count: Int(last - first + 1))
    )
  }
  func testConcurrentReadAndReadAheadShareTheSameRequest() async throws {
    let calls = RangeCalls()
    let buffer = buffer { request in
      let offset = Int64(
        request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")[0])!
      _ = calls.add(offset)
      return try self.response(request)
    }
    _ = try await buffer.block(at: 0)
    await buffer.prefetch(after: 0)
    async let first = buffer.block(at: AudioRangeBuffer.blockSize)
    async let second = buffer.block(at: AudioRangeBuffer.blockSize)
    let (a, b) = try await (first, second)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a.first, 1)
    XCTAssertEqual(calls.count(AudioRangeBuffer.blockSize), 1)
    await buffer.close()
  }
  func testCrossingManyBlocksPreservesBytesAndBoundsTheCache() async throws {
    let calls = RangeCalls()
    let buffer = buffer { request in
      let offset = Int64(
        request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")[0])!
      _ = calls.add(offset)
      return try self.response(request)
    }
    for index in 0..<12 {
      let bytes = try await buffer.block(at: Int64(index) * AudioRangeBuffer.blockSize)
      XCTAssertEqual(bytes.count, Int(AudioRangeBuffer.blockSize))
      XCTAssertTrue(bytes.allSatisfy { $0 == UInt8(index) })
    }
    _ = try await buffer.block(at: 0)
    XCTAssertEqual(
      calls.count(0), 2, "Old blocks must be evicted, not retained for the entire song")
    await buffer.close()
  }
  func testTemporary503IsRetriedWithoutDuplicatingAudio() async throws {
    let calls = RangeCalls()
    let buffer = buffer { request in
      if calls.add(0) == 1 { return (503, ["Retry-After": "0"], Data()) }
      return try self.response(request)
    }
    let bytes = try await buffer.block(at: 0)
    XCTAssertEqual(bytes.count, Int(AudioRangeBuffer.blockSize))
    XCTAssertEqual(calls.count(0), 2)
    await buffer.close()
  }
  func testLostConnectionIsRetried() async throws {
    let calls = RangeCalls()
    let buffer = buffer { request in
      if calls.add(0) == 1 { throw URLError(.networkConnectionLost) }
      return try self.response(request)
    }
    _ = try await buffer.block(at: 0)
    XCTAssertEqual(calls.count(0), 2)
    await buffer.close()
  }
  func testCorruptRangesAnd403FailWithoutRetry() async throws {
    for status in [403, 206] {
      let calls = RangeCalls()
      let buffer = buffer { _ in
        _ = calls.add(0)
        return (status, ["Content-Range": "bytes 1-4/10"], Data([1, 2, 3, 4]))
      }
      do {
        _ = try await buffer.block(at: 0)
        XCTFail("Invalid audio must not reach AVPlayer")
      } catch { XCTAssertEqual(calls.count(0), 1) }
      await buffer.close()
    }
  }
  func testClosingTrackRejectsNewReads() async throws {
    let buffer = buffer { try self.response($0) }
    await buffer.close()
    do {
      _ = try await buffer.block(at: 0)
      XCTFail()
    } catch {}
  }
}

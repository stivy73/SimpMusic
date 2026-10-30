import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

final class AudioPlaybackTests: XCTestCase {
  func testEachRangeLoaderHasAPrivateDistinctAssetIdentity() {
    let source = YouTubeAudio.Source(
      url: URL(string: "https://test.googlevideo.com/audio?sig=private")!, duration: 258,
      userAgent: "Test", byteCount: 4_000_000, isHLS: false)
    let first = AudioRangeLoader(source: source)
    let second = AudioRangeLoader(source: source)
    XCTAssertEqual(first.asset().url, first.asset().url)
    XCTAssertNotEqual(first.asset().url, second.asset().url)
    XCTAssertFalse(first.asset().url.absoluteString.contains("private"))
  }
  func testResolutionDiagnosticsIdentifyBoundaryWithoutLeakingProviderError() {
    XCTAssertEqual(
      AudioResolutionFailure.detail(
        AudioPlaybackError.rejectedRange(offset: 1_048_576, status: 403)),
      "CDN offset 1048576: HTTP 403, intervallo non valido")
    let privateError = NSError(
      domain: "https://private.invalid/?cookie=secret", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "signedURL secret token"])
    XCTAssertEqual(AudioResolutionFailure.detail(privateError), "nessuno stream completo validato")
    XCTAssertEqual(
      AudioResolutionFailure.detail(PlayerCipherError.script),
      "decodifica indirizzo audio non disponibile")
  }

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
    XCTAssertEqual(
      request.url?.absoluteString, "https://a.googlevideo.com/audio?signature=test%2Btoken")
    XCTAssertThrowsError(try AudioRangeLoader.rangeRequest(source: source, offset: -1, last: 0))
    XCTAssertThrowsError(try AudioRangeLoader.rangeRequest(source: source, offset: 100, last: 99))
  }

  func testRangeRequestPreservesExactSignedQueryBytesAndOrdering() throws {
    let encoded =
      "n=token%2B%2f%3D&%72ange=0-1&sig=hashed%2f%2F%2B%3d&empty=&flag&dup=one&range=2-3&dup=two&tail=literal+plus"
    let source = YouTubeAudio.Source(
      url: URL(string: "https://a.googlevideo.com/audio?" + encoded)!, duration: 120,
      userAgent: "Client", byteCount: 4_000_000, isHLS: false)
    let request = try AudioRangeLoader.rangeRequest(
      source: source, offset: 1_048_576, last: 1_049_599)
    XCTAssertEqual(
      URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
      "n=token%2B%2f%3D&sig=hashed%2f%2F%2B%3d&empty=&flag&dup=one&dup=two&tail=literal+plus")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=1048576-1049599")
    // Multiple ordinary fields, including empty/bare values, must not be normalized.
    let values = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(values?.filter { $0.name == "dup" }.map(\.value), ["one", "two"])
    XCTAssertEqual(values?.filter { $0.name == "range" }.count, 0)
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

  private func validationVideo(hls: Bool = false) throws -> YouTubeVideo {
    var streaming: [String: Any] = [
      "adaptiveFormats": [
        [
          "itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 128000,
          "url": "https://test.googlevideo.com/high",
        ],
        [
          "itag": 139, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 48000,
          "url": "https://test.googlevideo.com/low",
        ],
      ]
    ]
    if hls { streaming["hlsManifestUrl"] = "https://test.googlevideo.com/master.m3u8" }
    return try JSONDecoder().decode(
      YouTubeVideo.self,
      from: JSONSerialization.data(withJSONObject: [
        "videoDetails": [
          "videoId": "track", "title": "Song", "author": "Artist",
          "channelId": "artist", "viewCount": "1", "lengthSeconds": "180",
        ],
        "streamingData": streaming,
      ]))
  }
  private func validationTransport() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RangeStub.self]
    return URLSession(configuration: config)
  }
  private func validProbe(_ request: URLRequest) throws -> (Int, [String: String], Data) {
    let range = try XCTUnwrap(request.value(forHTTPHeaderField: "Range"))
    let parts = range.dropFirst(6).split(separator: "-")
    let first = try XCTUnwrap(Int64(parts[0]))
    let last = try XCTUnwrap(Int64(parts[1]))
    return (
      206, ["Content-Range": "bytes \(first)-\(last)/4000000"],
      Data(repeating: 1, count: Int(last - first + 1))
    )
  }
  func testBoundaryAndTailAreCheckedConcurrentlyBeforeSourceIsAccepted() async throws {
    ValidationConcurrencyStub.reset()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ValidationConcurrencyStub.self]
    let transport = URLSession(configuration: config)
    defer { transport.invalidateAndCancel() }
    let source = try await YouTubeAudio(transport: transport).source(
      video: validationVideo(), userAgent: "Test", authenticated: true, quality: .high)
    XCTAssertEqual(source.byteCount, 4_000_000)
    XCTAssertEqual(ValidationConcurrencyStub.maximum, 2,
      "Tail and post-minute safety checks must overlap, rather than add round trips")
  }

  func testPublicPrefixOnlyStreamFallsBackBeforePlayback() async throws {
    let calls = RangeCalls()
    RangeStub.handler = { request in
      if request.url?.lastPathComponent == "high",
        request.value(forHTTPHeaderField: "Range") == "bytes=1048576-1049599"
      {
        _ = calls.add(1_048_576)
        return (403, [:], Data())
      }
      return try self.validProbe(request)
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    let result = try await YouTubeAudio(transport: transport).source(
      video: validationVideo(), userAgent: "Test", authenticated: false, quality: .high)
    XCTAssertEqual(result.url.lastPathComponent, "low")
    XCTAssertEqual(calls.count(1_048_576), 1)
    XCTAssertFalse(result.authenticated)
  }
  func testPublicAndAccountStreamsMustPassTailAndBoundary() async throws {
    for authenticated in [false, true] {
      RangeStub.handler = { request in
        if request.value(forHTTPHeaderField: "Range") == "bytes=3998976-3999999" {
          return (403, [:], Data())
        }
        return try self.validProbe(request)
      }
      let transport = validationTransport()
      defer { transport.invalidateAndCancel() }
      do {
        _ = try await YouTubeAudio(transport: transport).source(
          video: validationVideo(), userAgent: "Test", authenticated: authenticated, quality: .high)
        XCTFail("A source that fails at its tail must not be accepted")
      } catch is AudioPlaybackError {}
    }
  }
  func testExcludedStreamIsNotRequestedDuringRecovery() async throws {
    RangeStub.handler = { request in
      XCTAssertNotEqual(request.url?.lastPathComponent, "high")
      return try self.validProbe(request)
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    let result = try await YouTubeAudio(transport: transport).source(
      video: validationVideo(), userAgent: "Test", authenticated: true, quality: .high,
      excluding: [URL(string: "https://test.googlevideo.com/high")!])
    XCTAssertEqual(result.url.lastPathComponent, "low")
    XCTAssertTrue(result.authenticated)
  }
  func testIncorrectPrefixRangeIsNotMistakenForPlayableFile() async throws {
    RangeStub.handler = { _ in
      (206, ["Content-Range": "bytes 12-1035/4000000"], Data(repeating: 0, count: 1024))
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    do {
      _ = try await YouTubeAudio(transport: transport).source(
        video: validationVideo(), userAgent: "Test", authenticated: false, quality: .high)
      XCTFail("Wrong offset would corrupt the media stream")
    } catch is AudioPlaybackError {}
  }
  func testHLSFallbackRequiresSegmentsBeyondOneMinute() async throws {
    let calls = RangeCalls()
    RangeStub.handler = { request in
      switch request.url!.lastPathComponent {
      case "master.m3u8":
        return (200, [:], Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=128000\nmedia.m3u8\n".utf8))
      case "media.m3u8":
        return (
          200, [:],
          Data(
            "#EXTM3U\n#EXTINF:60,\nstart.ts\n#EXTINF:60,\nafter.ts\n#EXTINF:60,\nend.ts\n#EXT-X-ENDLIST\n"
              .utf8)
        )
      case "start.ts", "after.ts", "end.ts":
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-1023")
        if request.url!.lastPathComponent == "after.ts" { _ = calls.add(60) }
        return (206, [:], Data(repeating: 1, count: 1024))
      default: return (403, [:], Data())
      }
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    let result = try await YouTubeAudio(transport: transport).source(
      video: validationVideo(hls: true), userAgent: "Test", authenticated: false, quality: .high)
    XCTAssertTrue(result.isHLS)
    XCTAssertEqual(result.url.lastPathComponent, "media.m3u8")
    XCTAssertEqual(calls.count(60), 1)
  }
  func testManifestSuccessDoesNotHideSegment403() async throws {
    RangeStub.handler = { request in
      switch request.url!.lastPathComponent {
      case "master.m3u8":
        return (
          200, [:],
          Data("#EXTM3U\n#EXTINF:60,\nstart.ts\n#EXTINF:60,\nblocked.ts\n#EXT-X-ENDLIST\n".utf8)
        )
      case "start.ts": return (206, [:], Data(repeating: 1, count: 1024))
      default: return (403, [:], Data())
      }
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    do {
      _ = try await YouTubeAudio(transport: transport).source(
        video: validationVideo(hls: true), userAgent: "Test", authenticated: false, quality: .high)
      XCTFail("Playlist HTTP200 is not sufficient when segments return403")
    } catch is AudioPlaybackError {}
  }

  func testHLSUsesDefaultAudioRenditionOfSelectedGroupWithQuotedCommas() async throws {
    let calls = RangeCalls()
    RangeStub.handler = { request in
      switch request.url!.lastPathComponent {
      case "master.m3u8":
        return (
          200, [:],
          Data(
            """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="unrelated",DEFAULT=YES,URI="wrong.m3u8"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio,main",NAME="Alternative",DEFAULT=NO,URI="alternative.m3u8"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio,main",NAME="Original, studio",DEFAULT=YES,URI="audio.m3u8?token=left,right"
            #EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio,main"
            video-only.m3u8
            """.utf8)
        )
      case "audio.m3u8":
        XCTAssertEqual(request.url!.query, "token=left,right")
        _ = calls.add(1)
        return (
          200, [:],
          Data("#EXTM3U\n#EXTINF:60,\nstart.ts\n#EXTINF:60,\nafter.ts\n#EXT-X-ENDLIST\n".utf8)
        )
      case "start.ts", "after.ts": return (206, [:], Data(repeating: 1, count: 1024))
      case "high", "low": return (403, [:], Data())
      default:
        XCTFail("Must use the selected group's default audio, never an isolated video rendition")
        return (403, [:], Data())
      }
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    let result = try await YouTubeAudio(transport: transport).source(
      video: validationVideo(hls: true), userAgent: "Test", authenticated: false, quality: .high)
    XCTAssertTrue(result.isHLS)
    XCTAssertEqual(result.url.lastPathComponent, "audio.m3u8")
    XCTAssertEqual(calls.count(1), 1)
  }

  func testHLSRejectsMissingOrForeignAudioGroupWithoutRequestingVideo() async throws {
    for rendition in [
      "",
      "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",DEFAULT=YES,URI=\"https://foreign.example/audio.m3u8\"",
    ] {
      RangeStub.handler = { request in
        XCTAssertEqual(request.url?.host, "test.googlevideo.com")
        switch request.url!.lastPathComponent {
        case "master.m3u8":
          return (
            200, [:],
            Data(
              "#EXTM3U\n\(rendition)\n#EXT-X-STREAM-INF:BANDWIDTH=800000,AUDIO=\"audio\"\nvideo-only.m3u8\n"
                .utf8)
          )
        case "high", "low": return (403, [:], Data())
        default:
          XCTFail(
            "An invalid external audio rendition must not silently become video-only playback")
          return (403, [:], Data())
        }
      }
      let transport = validationTransport()
      defer { transport.invalidateAndCancel() }
      do {
        _ = try await YouTubeAudio(transport: transport).source(
          video: validationVideo(hls: true), userAgent: "Test", authenticated: false, quality: .high
        )
        XCTFail("Missing/foreign audio group must fail validation")
      } catch is AudioPlaybackError {}
    }
  }

  func testHLSMalformedSegmentDurationFailsWithoutCrashing() async throws {
    RangeStub.handler = { request in
      if request.url!.lastPathComponent == "master.m3u8" {
        return (200, [:], Data("#EXTM3U\n#EXTINF:\nstart.ts\n#EXT-X-ENDLIST\n".utf8))
      }
      return (403, [:], Data())
    }
    let transport = validationTransport()
    defer { transport.invalidateAndCancel() }
    do {
      _ = try await YouTubeAudio(transport: transport).source(
        video: validationVideo(hls: true), userAgent: "Test", authenticated: false, quality: .high)
      XCTFail("A malformed playlist must fail without crashing")
    } catch is AudioPlaybackError {}
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
    let buffer = buffer(blocks: 40) { request in
      let offset = Int64(
        request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")[0])!
      _ = calls.add(offset)
      return try self.response(request, blocks: 40)
    }
    for index in 0..<40 {
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

private final class ValidationConcurrencyStub: URLProtocol, @unchecked Sendable {
  static let lock = NSLock()
  nonisolated(unsafe) private static var active = 0
  nonisolated(unsafe) private static var peak = 0
  static var maximum: Int { lock.withLock { peak } }
  static func reset() { lock.withLock { active = 0; peak = 0 } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6)
    let parts = range.split(separator: "-")
    let first = Int(parts[0])!, last = Int(parts[1])!
    let delayed = first != 0
    if delayed { Self.lock.withLock { Self.active += 1; Self.peak = max(Self.peak, Self.active) } }
    DispatchQueue.global().asyncAfter(deadline: .now() + (delayed ? 0.15 : 0)) { [self] in
      let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil,
        headerFields: ["Content-Range": "bytes \(first)-\(last)/4000000"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(repeating: 1, count: last - first + 1))
      if delayed { Self.lock.withLock { Self.active -= 1 } }
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {}
}

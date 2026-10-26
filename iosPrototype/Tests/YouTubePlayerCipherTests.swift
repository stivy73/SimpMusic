import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

final class YouTubePlayerCipherTests: XCTestCase {
  private let registry =
    #"{"schemaVersion":1,"players":{"1234abcd":{"sig":"Fn(17,1452,INPUT)","nClass":"Fl","sts":20746,"aliases":["cbcfbf2f"]}}}"#

  func testCurrentPlayerAliasAndTimestampUseTheSameEntry() throws {
    let config = try CipherPlayerConfig.parse(Data(registry.utf8), playerID: "cbcfbf2f")
    XCTAssertEqual(config.timestamp, 20746)
    XCTAssertEqual(config.signatureExpression, "Fn(17,1452,INPUT)")
    XCTAssertEqual(config.nClass, "Fl")
  }

  func testRejectsUnknownSchemaMalformedAliasesAndExecutableRegistryValues() {
    let invalid = [
      registry.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":true"),
      registry.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":1.5"),
      registry.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
      registry.replacingOccurrences(
        of: "Fn(17,1452,INPUT)", with: "Fn(17,1452,INPUT);fetch('remote')"),
      registry.replacingOccurrences(of: "\"nClass\":\"Fl\"", with: "\"nClass\":\"Fl);evil(\""),
      registry.replacingOccurrences(of: "20746", with: "true"),
      registry.replacingOccurrences(of: "20746", with: "20746.5"),
      registry.replacingOccurrences(of: "[\"cbcfbf2f\"]", with: "[\"cbcfbf2f\",\"cbcfbf2f\"]"),
    ]
    for value in invalid {
      XCTAssertThrowsError(try CipherPlayerConfig.parse(Data(value.utf8), playerID: "cbcfbf2f"))
    }
    XCTAssertThrowsError(try CipherPlayerConfig.parse(Data(registry.utf8), playerID: "missing"))
  }

  func testExportsAreInsertedInsideExactlyOnePlayerClosure() throws {
    let config = try CipherPlayerConfig.parse(Data(registry.utf8), playerID: "cbcfbf2f")
    let source = "(function(g){function Fn(a,b,s){return s;} })(_yt_player);"
    let script = try config.exporting(source)
    XCTAssertTrue(script.contains("return Fn(17,1452,sig)"))
    XCTAssertTrue(script.contains("new g.Fl("))
    XCTAssertTrue(script.hasSuffix("})(_yt_player);"))
    XCTAssertThrowsError(try config.exporting("no closure"))
    XCTAssertThrowsError(try config.exporting(source + source))
  }

  func testCipherTransformPreservesSignedQueryEscapesAndLiteralPlus() throws {
    let original = "https://a.googlevideo.com/videoplayback?keep=%2B+%20%2f&n=original-n&order=last"
    var encoded = URLComponents()
    encoded.queryItems = [
      URLQueryItem(name: "url", value: original),
      URLQueryItem(name: "s", value: "encrypted+signature"),
      URLQueryItem(name: "sp", value: "sig"),
    ]
    let request = try CipherStreamRequest(url: nil, cipher: encoded.percentEncodedQuery)
    XCTAssertEqual(request.signature, "encrypted+signature")
    let result = try request.resolved(
      using: CipherAnswers(
        signatures: ["encrypted+signature": "decoded.signature"], nValues: ["original-n": "fixed-n"]
      ))
    XCTAssertEqual(
      result.absoluteString,
      "https://a.googlevideo.com/videoplayback?keep=%2B+%20%2f&n=fixed-n&order=last&sig=decoded.signature"
    )
  }

  func testDirectURLsStillTransformNAndRejectUnsolvedValues() throws {
    let request = try CipherStreamRequest(
      url: "https://a.googlevideo.com/videoplayback?n=old", cipher: nil)
    XCTAssertThrowsError(try request.resolved(using: CipherAnswers(signatures: [:], nValues: [:])))
    XCTAssertThrowsError(
      try request.resolved(using: CipherAnswers(signatures: [:], nValues: ["old": "old"])))
    XCTAssertThrowsError(
      try request.resolved(using: CipherAnswers(signatures: [:], nValues: ["old": "unsafe&value"])))
    XCTAssertEqual(
      try request.resolved(using: CipherAnswers(signatures: [:], nValues: ["old": "new"])).query,
      "n=new")
    for url in [
      "http://a.googlevideo.com/audio", "https://googlevideo.com.evil.example/audio",
      "https://user@a.googlevideo.com/audio", "https://a.googlevideo.com/audio?n=one&n=two",
    ] {
      XCTAssertThrowsError(try CipherStreamRequest(url: url, cipher: nil))
    }
    XCTAssertThrowsError(try CipherStreamRequest(url: nil, cipher: "url=bad%ZZ&s=token"))
  }

  func testBase64SignaturePaddingAndPlusAreEncodedWithoutChangingSignedURL() throws {
    var parameters = URLComponents()
    parameters.queryItems = [
      URLQueryItem(name: "url", value: "https://a.googlevideo.com/audio?keep=%2B+%20%2f"),
      URLQueryItem(name: "s", value: "encrypted"), URLQueryItem(name: "sp", value: "sig"),
    ]
    let request = try CipherStreamRequest(url: nil, cipher: parameters.percentEncodedQuery)
    let result = try request.resolved(
      using: CipherAnswers(signatures: ["encrypted": "base+64/value=="], nValues: [:]))
    XCTAssertEqual(
      result.absoluteString,
      "https://a.googlevideo.com/audio?keep=%2B+%20%2f&sig=base%2B64%2Fvalue%3D%3D")
  }

  func testAuthenticatedCipherStreamsBecomeUsableAndMetadataIsCached() async throws {
    let calls = CipherCallLog()
    let registry = Data(registry.utf8)
    let cipher = YouTubePlayerCipher(
      download: { url, _ in
        await calls.record(url)
        if url.path == "/iframe_api" { return Data(#"var path="/s/player/cbcfbf2f/";"#.utf8) }
        if url.host == "raw.githubusercontent.com" { return registry }
        return Data("(function(g){ function Fn(a,b,s){return s;} })(_yt_player);".utf8)
      },
      execute: { script, signatures, nValues in
        XCTAssertTrue(script.contains("_cipherSigFunc"))
        XCTAssertEqual(signatures, ["encrypted"])
        XCTAssertEqual(nValues, ["old-n"])
        return CipherAnswers(signatures: ["encrypted": "decoded"], nValues: ["old-n": "fixed-n"])
      })
    let info = try await cipher.playerInfo()
    XCTAssertEqual(info.id, "cbcfbf2f")
    XCTAssertEqual(info.signatureTimestamp, 20746)
    let cachedInfo = try await cipher.playerInfo()
    XCTAssertEqual(info, cachedInfo)
    var parameters = URLComponents()
    parameters.queryItems = [
      URLQueryItem(name: "url", value: "https://a.googlevideo.com/audio?n=old-n&keep=%2B"),
      URLQueryItem(name: "s", value: "encrypted"), URLQueryItem(name: "sp", value: "sig"),
    ]
    let video = try fixture(cipher: parameters.percentEncodedQuery!)
    XCTAssertTrue(YouTubeAudio.candidates(video).isEmpty)
    let decoded = try await cipher.decipher(video: video, player: info)
    XCTAssertEqual(
      YouTubeAudio.candidates(decoded).first?.absoluteString,
      "https://a.googlevideo.com/audio?n=fixed-n&keep=%2B&sig=decoded")
    XCTAssertNil(decoded.streamingData?.adaptiveFormats.first?.signatureCipher)
    let requests = await calls.urls
    XCTAssertEqual(requests.count, 3)
    XCTAssertTrue(
      requests.allSatisfy { $0.query == nil },
      "Registry/script requests never carry account data or challenges")
    await cipher.invalidate()
    _ = try await cipher.playerInfo()
    let afterInvalidate = await calls.urls
    XCTAssertEqual(afterInvalidate.count, 5)
  }

  func testFailedChallengeDoesNotReturnAnUnusablePartiallyDecodedStream() async throws {
    let registry = Data(registry.utf8)
    let cipher = YouTubePlayerCipher(
      download: { url, _ in
        if url.path == "/iframe_api" { return Data(#"player\/cbcfbf2f\/"#.utf8) }
        if url.host == "raw.githubusercontent.com" { return registry }
        return Data("(function(g){})(_yt_player);".utf8)
      }, execute: { _, _, _ in CipherAnswers(signatures: [:], nValues: [:]) })
    let info = try await cipher.playerInfo()
    let video = try fixture(
      cipher: "url=https%3A%2F%2Fa.googlevideo.com%2Faudio&s=encrypted&sp=sig")
    do {
      _ = try await cipher.decipher(video: video, player: info)
      XCTFail("An unresolved signature cannot reach playback")
    } catch {}
  }

  func testMalformedAACDoesNotHideAValidAlternative() async throws {
    let registry = Data(registry.utf8)
    let cipher = YouTubePlayerCipher(download: { url, _ in
      if url.path == "/iframe_api" { return Data(#"player/cbcfbf2f/"#.utf8) }
      return registry
    })
    let info = try await cipher.playerInfo()
    let object: [String: Any] = [
      "videoDetails": [
        "videoId": "song", "title": "Song", "author": "Artist", "channelId": "artist",
        "viewCount": "1",
      ],
      "streamingData": [
        "adaptiveFormats": [
          [
            "itag": 139, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 48000,
            "signatureCipher": "malformed",
          ],
          [
            "itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 128000,
            "url": "https://a.googlevideo.com/valid?keep=%2B+%20",
          ],
        ]
      ],
    ]
    let video = try JSONDecoder().decode(
      YouTubeVideo.self, from: JSONSerialization.data(withJSONObject: object))
    let result = try await cipher.decipher(video: video, player: info)
    XCTAssertEqual(YouTubeAudio.candidates(result).count, 1)
    XCTAssertEqual(
      YouTubeAudio.candidates(result).first?.absoluteString,
      "https://a.googlevideo.com/valid?keep=%2B+%20")
  }

  @MainActor func testWebWorkerRunsLocalTransformWithoutAUserSession() async throws {
    let result = try await CipherWebWorker.run(
      script:
        "window._cipherSigFunc = s => 'solved-' + s; window._nTransformFunc = n => 'solved-' + n;",
      signatures: ["sig"], nValues: ["token"])
    XCTAssertEqual(result.signatures["sig"], "solved-sig")
    XCTAssertEqual(result.nValues["token"], "solved-token")
  }

  func testConcurrentPlayerMetadataRetainsBothConfigurationSnapshots() async throws {
    let variants = CipherMetadataVariants()
    let cipher = YouTubePlayerCipher(download: { url, _ in
      if url.path == "/iframe_api" { return try await variants.iframe() }
      return Data(
        #"{"schemaVersion":1,"players":{"1234abcd":{"sig":"Fn(17,1452,INPUT)","nClass":"Fl","sts":20746},"cbcfbf2f":{"sig":"Fn(17,1452,INPUT)","nClass":"Fl","sts":20746}}}"#
          .utf8)
    })
    async let first = cipher.playerInfo()
    async let second = cipher.playerInfo()
    let snapshots = try await [first, second]
    XCTAssertEqual(Set(snapshots.map(\.id)), Set(["1234abcd", "cbcfbf2f"]))
    var video = try fixture(cipher: "unused")
    video.streamingData?.adaptiveFormats[0].signatureCipher = nil
    video.streamingData?.adaptiveFormats[0].url = "https://a.googlevideo.com/audio"
    for info in snapshots {
      let result = try await cipher.decipher(video: video, player: info)
      XCTAssertEqual(YouTubeAudio.candidates(result).count, 1)
    }
  }

  @MainActor func testWebWorkerDeadlineReturnsAndFollowingWorkerRemainsUsable() async throws {
    let start = Date()
    do {
      _ = try await CipherWebWorker.run(
        script: "while (true) {}", signatures: [], nValues: [], timeoutSeconds: 0.5)
      XCTFail("A non-returning script must not hold the audio resolver")
    } catch PlayerCipherError.timedOut {
      XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    let result = try await CipherWebWorker.run(
      script: "window._cipherSigFunc = s => 'done';", signatures: ["sig"], nValues: [])
    XCTAssertEqual(result.signatures["sig"], "done")
  }

  private func fixture(cipher: String) throws -> YouTubeVideo {
    let object: [String: Any] = [
      "videoDetails": [
        "videoId": "song", "title": "Song", "author": "Artist", "channelId": "artist",
        "viewCount": "1",
      ],
      "streamingData": [
        "adaptiveFormats": [
          [
            "itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 128000,
            "signatureCipher": cipher,
          ]
        ]
      ],
    ]
    return try JSONDecoder().decode(
      YouTubeVideo.self, from: JSONSerialization.data(withJSONObject: object))
  }
}

private actor CipherCallLog {
  var urls: [URL] = []
  func record(_ url: URL) { urls.append(url) }
}

private actor CipherMetadataVariants {
  private var request = 0
  func iframe() async throws -> Data {
    request += 1
    let id = request == 1 ? "1234abcd" : "cbcfbf2f"
    try await Task.sleep(for: .milliseconds(50))
    return Data("player/\(id)/".utf8)
  }
}

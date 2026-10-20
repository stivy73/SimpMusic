import Foundation
import XCTest
import YouTubeSDK

@testable import PrototypeCore

final class AudioPlaybackTests: XCTestCase {
  func testRangeRequestPreservesSignatureAndReplacesOnlyRange() throws {
    let source = YouTubeAudio.Source(
      url: URL(string: "https://a.googlevideo.com/audio?signature=test%2Btoken&range=0-1")!,
      duration: 10, userAgent: "Client", byteCount: 10_000, isHLS: false)
    let request = try AudioRangeLoader.rangeRequest(source: source, offset: 100, last: 499)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=100-499")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Client")
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(query?.filter { $0.name == "range" }.map(\.value), ["100-499"])
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

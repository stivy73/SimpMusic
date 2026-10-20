import Foundation
import XCTest

@testable import PrototypeCore

final class SpeechStreamTests: XCTestCase {
  private func event(
    _ data: Data?, finish: String? = nil, mime: String = "audio/l16; rate=24000; channels=1"
  ) throws -> String {
    var candidate: [String: Any] = [:]
    if let data {
      candidate["content"] = [
        "parts": [["inlineData": ["mimeType": mime, "data": data.base64EncodedString()]]]
      ]
    }
    if let finish { candidate["finishReason"] = finish }
    return "data: " + String(
      data: try JSONSerialization.data(withJSONObject: ["candidates": [candidate]]), encoding: .utf8
    )!
  }
  func testStreamsAllChunksAndRequiresCompletion() throws {
    var decoder = GeminiSpeechDecoder()
    let first = Data([0, 1, 255, 255])
    let second = Data([0, 0])
    XCTAssertEqual(try decoder.consume(": heartbeat"), [])
    XCTAssertEqual(try decoder.consume(try event(first)), [first])
    XCTAssertThrowsError(try decoder.validateCompletion())
    XCTAssertEqual(try decoder.consume(try event(second, finish: "STOP")), [second])
    XCTAssertNoThrow(try decoder.validateCompletion())
    XCTAssertEqual(try decoder.consume("data: [DONE]"), [])
    XCTAssertThrowsError(try decoder.consume(try event(first)))
  }
  func testRejectsEmptyTruncatedBlockedAndMalformedStreams() throws {
    for line in [
      try event(nil, finish: "STOP"), try event(Data([0, 1]), finish: "MAX_TOKENS"),
      "data: {\"error\":{\"code\":429}}", "data: not JSON", "data: [DONE]", try event(Data([1])),
      try event(Data([0, 1]), mime: "audio/wav"),
      try event(Data([0, 1]), mime: "audio/L16;rate=48000"),
    ] {
      var decoder = GeminiSpeechDecoder()
      XCTAssertThrowsError(
        try {
          _ = try decoder.consume(line)
          try decoder.validateCompletion()
        }())
    }
  }
  func testCacheKeyIncludesWholeTextVoiceAndStyle() {
    let key = SpeechAudioCache.key(text: "testo", voice: "Kore", style: .dj)
    XCTAssertEqual(key.count, 64)
    XCTAssertEqual(key, SpeechAudioCache.key(text: "testo", voice: "Kore", style: .dj))
    XCTAssertNotEqual(key, SpeechAudioCache.key(text: "Testo", voice: "Kore", style: .dj))
    XCTAssertNotEqual(key, SpeechAudioCache.key(text: "testo", voice: "Puck", style: .dj))
    XCTAssertNotEqual(key, SpeechAudioCache.key(text: "testo", voice: "Kore", style: .professional))
  }
  func testCachePersistsValidAudioAndRejectsCorruption() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = SpeechAudioCache.key(text: "testo", voice: "Kore", style: .dj)
    let pcm = Data([0, 1, 2, 3])
    let cache = SpeechAudioCache(directory: directory)
    await cache.store(pcm, key: key)
    let reloaded = SpeechAudioCache(directory: directory)
    let hit = await reloaded.read(key)
    XCTAssertEqual(hit, pcm)
    let file = directory.appendingPathComponent(key).appendingPathExtension("pcm")
    var corrupt = try Data(contentsOf: file)
    corrupt[corrupt.count - 1] ^= 1
    try corrupt.write(to: file)
    let miss = await reloaded.read(key)
    XCTAssertNil(miss)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    await cache.store(Data([1]), key: key)
    let invalid = await cache.read(key)
    XCTAssertNil(invalid)
  }
  func testCacheEvictsLeastRecentlyUsedAndRejectsPathTraversal() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = SpeechAudioCache(directory: directory, maximumBytes: 72)
    let keys = (0..<3).map { SpeechAudioCache.key(text: "\($0)", voice: "Kore", style: .dj) }
    await cache.store(Data([1, 2, 3, 4]), key: keys[0])
    await cache.store(Data([1, 2, 3, 4]), key: keys[1])
    let old = directory.appendingPathComponent(keys[0]).appendingPathExtension("pcm")
    try FileManager.default.setAttributes(
      [.modificationDate: Date.distantPast], ofItemAtPath: old.path)
    await cache.store(Data([1, 2, 3, 4]), key: keys[2])
    let evicted = await cache.read(keys[0])
    let recent = await cache.read(keys[2])
    XCTAssertNil(evicted)
    XCTAssertNotNil(recent)
    await cache.store(Data([1, 2]), key: "../escape")
    let traversal = await cache.read("../escape")
    XCTAssertNil(traversal)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
  }
}

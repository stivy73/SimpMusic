import XCTest

@testable import PrototypeCore

final class InterpretationTests: XCTestCase {
  func testMissingLyricsPreventsGuessing() {
    XCTAssertThrowsError(
      try Interpretation.context(title: "Dreams", artist: "Fleetwood Mac", lyrics: " \n"))
  }
  func testContextContainsActualLyricsAndCapsInput() throws {
    let context = try Interpretation.context(
      title: "Dreams", artist: "Fleetwood Mac", lyrics: String(repeating: "a", count: 7000))
    XCTAssertTrue(context.contains("Artista: Fleetwood Mac"))
    XCTAssertTrue(context.hasSuffix(String(repeating: "a", count: 6000)))
    XCTAssertFalse(context.contains(String(repeating: "a", count: 6001)))
  }
  func testLengthBounds() {
    XCTAssertFalse(Interpretation.isExpectedLength(String(repeating: "a", count: 854)))
    XCTAssertTrue(Interpretation.isExpectedLength(String(repeating: "a", count: 855)))
    XCTAssertTrue(Interpretation.isExpectedLength(String(repeating: "a", count: 945)))
    XCTAssertFalse(Interpretation.isExpectedLength(String(repeating: "a", count: 946)))
  }
  func testDecodesDocumentedInteractionsWAVWithoutTruncation() throws {
    // A short valid PCM WAV: mono, 24 kHz, 16-bit, two silent samples.
    let wav = Data([
      82, 73, 70, 70, 40, 0, 0, 0, 87, 65, 86, 69,
      102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
      192, 93, 0, 0, 128, 187, 0, 0, 2, 0, 16, 0,
      100, 97, 116, 97, 4, 0, 0, 0, 0, 0, 0, 0,
    ])
    let response: [String: Any] = [
      "steps": [
        [
          "type": "model_output",
          "content": [["type": "audio", "data": wav.base64EncodedString()]],
        ]
      ]
    ]
    XCTAssertEqual(try GeminiService.decodeSpeech(response), wav)
  }
  func testRejectsMalformedAudio() {
    XCTAssertThrowsError(try GeminiService.decodeSpeech(["steps": []]))
    let truncated: [String: Any] = [
      "steps": [
        [
          "type": "model_output",
          "content": [["type": "audio", "data": Data("RIFFbroken".utf8).base64EncodedString()]],
        ]
      ]
    ]
    XCTAssertThrowsError(try GeminiService.decodeSpeech(truncated))
  }
}

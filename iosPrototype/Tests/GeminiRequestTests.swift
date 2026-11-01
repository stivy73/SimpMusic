import Foundation
import XCTest

@testable import PrototypeCore

private final class GeminiStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, data) = try Self.handler!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

final class GeminiRequestTests: XCTestCase {
  func testMusicSuggestionsUseSeparatePromptAndStructuredOutputWithOnlyChosenSeed() async throws {
    let service = service { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
      let body = try self.body(request)
      let instruction = String(describing: body["systemInstruction"]!)
      XCTAssertTrue(instruction.contains("consigliere musicale"))
      XCTAssertFalse(instruction.contains("900 caratteri"))
      XCTAssertEqual(
        (body["generationConfig"] as? [String: String])?["responseMimeType"], "application/json")
      let contents = String(describing: body["contents"]!)
      XCTAssertTrue(contents.contains("Reference"))
      XCTAssertFalse(contents.contains("cookies"))
      let response = #"{"songs":[{"title":"Real","artist":"Artist","reason":"Un motivo"}]}"#
      return (
        200,
        try JSONSerialization.data(withJSONObject: [
          "candidates": [["content": ["parts": [["text": response]]]]]
        ])
      )
    }
    let values = try await service.suggestMusic(
      key: "fixture-key", model: "gemini-3.8-flash", request: "Rock",
      seeds: [PlaybackTrack(id: "seed", title: "Reference", artist: "Artist", artwork: nil)])
    XCTAssertEqual(values.count, 1)
  }
  func testRadioRequestIncludesExclusionsAndUniqueRequestIdentifierAsData() async throws {
    let service = service { request in
      let body = try self.body(request)
      let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
      let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
      let text = try XCTUnwrap(parts.first?["text"] as? String)
      let context = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
      let instruction = try XCTUnwrap(body["systemInstruction"] as? [String: Any])
      XCTAssertTrue(String(describing: instruction).contains("50 canzoni"))
      XCTAssertEqual(context["richiesta_radio"] as? String, "fresh-request-id")
      let excluded = try XCTUnwrap(context["esclusi"] as? [[String: String]])
      XCTAssertEqual(excluded, [["title": "Already played", "artist": "Artist"]])
      XCTAssertFalse(text.contains("private-video-id"))
      let response = #"{"songs":[{"title":"New","artist":"Artist","reason":"Affinity"}]}"#
      return (200, try JSONSerialization.data(withJSONObject: [
        "candidates": [["content": ["parts": [["text": response]]]]]
      ]))
    }
    _ = try await service.suggestMusic(key: "fixture", model: "gemini-3.8-flash", request: "Radio",
      seeds: [], excluding: [PlaybackTrack(id: "private-video-id", title: "Already played", artist: "Artist", artwork: nil)],
      requestID: "fresh-request-id", count: 50)
  }
  private func service(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> GeminiService {
    GeminiStub.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GeminiStub.self]
    return GeminiService(session: URLSession(configuration: configuration))
  }
  private func body(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
    }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  func testLyricsAndItalianPromptSentToGoogle() async throws {
    let response = String(repeating: "a", count: 900)
    let service = service { request in
      XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
      XCTAssertTrue(request.url!.path.hasSuffix("gemini-3.8-flash:generateContent"))
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "dummy-test-key")
      let body = try self.body(request)
      let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
      let thinking = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
      XCTAssertEqual(thinking["thinkingLevel"] as? String, "low")
      let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
      let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
      XCTAssertTrue(
        (parts.first?["text"] as? String)?.contains("Testo fittizio per il test") == true)
      let instruction = try XCTUnwrap(body["systemInstruction"] as? [String: Any])
      XCTAssertTrue(String(describing: instruction).contains("italiano"))
      return (
        200,
        try JSONSerialization.data(withJSONObject: [
          "candidates": [["content": ["parts": [["text": response]]]]]
        ])
      )
    }
    let text = try await service.explain(
      key: "dummy-test-key", model: "gemini-3.8-flash", title: "Titolo", artist: "Artista",
      lyrics: "Testo fittizio per il test")
    XCTAssertEqual(text, response)
  }
  func testMissingLyricsOrKeyMakesNoRequest() async {
    let service = service { _ in
      XCTFail("Must not call Google")
      return (500, Data())
    }
    do {
      _ = try await service.explain(
        key: "dummy", model: "model", title: "T", artist: "A", lyrics: " ")
      XCTFail()
    } catch PrototypeError.missingLyrics {} catch { XCTFail() }
    do {
      _ = try await service.explain(
        key: "", model: "model", title: "T", artist: "A", lyrics: "lyrics")
      XCTFail()
    } catch PrototypeError.missingKey {} catch { XCTFail() }
  }
  func testHTTPErrorPropagates() async {
    let service = service { _ in (429, Data()) }
    do {
      _ = try await service.explain(
        key: "dummy", model: "model", title: "T", artist: "A", lyrics: "lyrics")
      XCTFail()
    } catch let error as GeminiAPIError {
      XCTAssertEqual(error.status, 429)
    } catch { XCTFail() }
  }
  func testCustomModelKeepsItsOwnConfigurationAndLengthRetry() async throws {
    var calls = 0
    let service = service { request in
      calls += 1
      let body = try self.body(request)
      XCTAssertNil(body["generationConfig"])
      let text = calls == 1 ? "Too short" : String(repeating: "a", count: 900)
      return (
        200,
        try JSONSerialization.data(withJSONObject: [
          "candidates": [["content": ["parts": [["text": text]]]]]
        ])
      )
    }
    let result = try await service.explain(
      key: "dummy", model: "custom-model", title: "t", artist: "a", lyrics: "source")
    XCTAssertEqual(calls, 2)
    XCTAssertTrue(Interpretation.isExpectedLength(result))
  }

  func testNarrationDoesNotDelayVoiceForALengthOnlyRewrite() async throws {
    var calls = 0
    let service = service { request in
      calls += 1
      XCTAssertEqual(request.timeoutInterval, 90)
      return (
        200,
        try JSONSerialization.data(withJSONObject: [
          "candidates": [["content": ["parts": [["text": "Risposta completa ma breve."]]]]]
        ])
      )
    }
    let result = try await service.explain(
      key: "dummy", model: "gemini-3.8-flash",
      title: "T", artist: "A", lyrics: "Testo sorgente", retryLength: false)
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(result, "Risposta completa ma breve.")
  }

  private func textSSE(_ text: String, finish: String? = "STOP") throws -> Data {
    var candidate: [String: Any] = ["content": ["parts": [["text": text]]]]
    if let finish { candidate["finishReason"] = finish }
    let data = try JSONSerialization.data(withJSONObject: ["candidates": [candidate]])
    return Data(("data: " + String(decoding: data, as: UTF8.self) + "\n\n").utf8)
  }

  func testStreamingInterpretationUsesActualLyricsAndOnlyCompleteFinalText() async throws {
    let service = service { request in
      XCTAssertTrue(request.url!.absoluteString.hasSuffix("gemini-3.8-flash:streamGenerateContent?alt=sse"))
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
      XCTAssertEqual(request.timeoutInterval, 45, accuracy: 0.1)
      let body = try self.body(request)
      XCTAssertTrue(String(describing: body["contents"]!).contains("Testo sorgente"))
      let thought = Data("data: {\"candidates\":[{\"content\":{\"parts\":[{\"thought\":true,\"text\":\"Never read this reasoning\"}]}}]}\n\n".utf8)
      let first = try self.textSSE("La canzone ", finish: nil)
      let last = try self.textSSE("parla di amicizia.")
      return (200, thought + first + last)
    }
    let text = try await service.explain(key: "fixture-key", model: "gemini-3.8-flash",
      title: "T", artist: "A", lyrics: "Testo sorgente", retryLength: false, streaming: true)
    XCTAssertEqual(text, "La canzone parla di amicizia.")
  }

  func testTimeoutRetriesOnceAndDoesNotRewriteACompleteShortInterpretation() async throws {
    var calls = 0
    let service = service { _ in
      calls += 1
      if calls == 1 {
        throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "secret-key-private-url"])
      }
      return (200, try self.textSSE("Risposta completa."))
    }
    let text = try await service.explain(key: "fixture-key", model: "gemini-3.8-flash",
      title: "T", artist: "A", lyrics: "Testo", retryLength: false, streaming: true)
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(text, "Risposta completa.")
  }

  func testTemporaryServerErrorRetriesAndDiscardsTheFailedAttempt() async throws {
    var calls = 0
    let service = service { _ in
      calls += 1
      if calls == 1 { return (503, Data("private diagnostic message".utf8)) }
      return (200, try self.textSSE("Testo nuovo completo."))
    }
    let text = try await service.explain(key: "fixture-key", model: "gemini-3.8-flash",
      title: "T", artist: "A", lyrics: "Testo", retryLength: false, streaming: true)
    XCTAssertEqual(calls, 2)
    XCTAssertEqual(text, "Testo nuovo completo.")
  }

  func testSecondTimeoutStopsAndCancellationIsNeverRetried() async throws {
    for code in [URLError.timedOut, .cancelled] {
      var calls = 0
      let service = service { _ in calls += 1; throw URLError(code) }
      do {
        _ = try await service.explain(key: "fixture-key", model: "gemini-3.8-flash",
          title: "T", artist: "A", lyrics: "Testo", retryLength: false, streaming: true)
        XCTFail("Network error swallowed")
      } catch let error as URLError { XCTAssertEqual(error.code, code) }
      XCTAssertEqual(calls, code == .timedOut ? 2 : 1)
    }
  }

  func testStreamingQuotaAndAuthorizationAreNotRetriedAndDoNotLeakProviderMessages() async throws {
    for status in [429, 403] {
      var calls = 0
      let errorData = Data(#"{"error":{"message":"secret-key-private-url","status":"RESOURCE_EXHAUSTED","details":[{"reason":"QUOTA_EXCEEDED","violations":[{"quotaId":"GenerateRequestsPerDayPerProjectPerModel-FreeTier","quotaDimensions":{"project":"private-project"}}]}]}}"#.utf8)
      let service = service { _ in calls += 1; return (status, errorData) }
      do {
        _ = try await service.explain(key: "fixture-key", model: "gemini-3.8-flash",
          title: "T", artist: "A", lyrics: "Testo", retryLength: false, streaming: true)
        XCTFail("API error swallowed")
      } catch let error as GeminiAPIError {
        XCTAssertEqual(error.status, status)
        XCTAssertTrue(error.freeQuota)
        XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        XCTAssertFalse(error.diagnostic.contains("private-project"))
        XCTAssertTrue(error.diagnostic.contains("RESOURCE_EXHAUSTED"))
      }
      XCTAssertEqual(calls, 1)
    }
    XCTAssertEqual(GeminiAPIError.safeDiagnostic(URLError(.timedOut,
      userInfo: [NSLocalizedDescriptionKey: "private-url-key"])), "rete -1001")
    XCTAssertEqual(GeminiAPIError.diagnosticModel("AIza-private-key"), "personalizzato")
  }

  func testIncompleteOrBlockedInterpretationNeverReachesSpeech() throws {
    for finish in [nil, "MAX_TOKENS", "SAFETY"] as [String?] {
      var decoder = GeminiTextStreamDecoder()
      let data = try textSSE("Testo interrotto", finish: finish)
      XCTAssertThrowsError(try {
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
          try decoder.consume(line)
        }
        return try decoder.completedText()
      }())
    }
    var decoder = GeminiTextStreamDecoder()
    XCTAssertThrowsError(try decoder.consume("data: {\"promptFeedback\":{\"blockReason\":\"SAFETY\"}}"))
  }

  func testSpeechRequestPreservesWholeTextAndStyle() async throws {
    let transcript = String(repeating: "Significato. ", count: 80)
    let wav = Data([
      82, 73, 70, 70, 40, 0, 0, 0, 87, 65, 86, 69, 102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0, 192,
      93, 0, 0, 128, 187, 0, 0, 2, 0, 16, 0, 100, 97, 116, 97, 4, 0, 0, 0, 0, 0, 0, 0,
    ])
    let service = service { request in
      let body = try self.body(request)
      XCTAssertEqual(body["model"] as? String, "gemini-3.8-flash-tts")
      let input = try XCTUnwrap(body["input"] as? [[String: Any]])
      let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
      XCTAssertEqual(content.first?["text"] as? String, transcript)
      let annotations = try XCTUnwrap(content.first?["annotations"] as? [[String: Any]])
      XCTAssertEqual(annotations.first?["style"] as? String, VoiceStyle.empathetic.instruction)
      return (
        200,
        try JSONSerialization.data(withJSONObject: [
          "steps": [
            [
              "type": "model_output",
              "content": [["type": "audio", "data": wav.base64EncodedString()]],
            ]
          ]
        ])
      )
    }
    let result = try await service.speech(
      key: "dummy", text: transcript, voice: "Kore", style: .empathetic)
    XCTAssertEqual(result, wav)
  }
  func testSpeechStreamingRequestAndCompleteResponse() async throws {
    let pcm = Data([0, 1, 2, 3])
    let service = service { request in
      XCTAssertTrue(request.url!.absoluteString.hasSuffix(":streamGenerateContent?alt=sse"))
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
      let body = try self.body(request)
      let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
      let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
      XCTAssertEqual(parts.first?["text"] as? String, "Testo intero")
      let metadata = try XCTUnwrap(parts.first?["speech_metadata"] as? [String: Any])
      XCTAssertEqual(metadata["style"] as? String, VoiceStyle.dj.instruction)
      let audio = try JSONSerialization.data(withJSONObject: [
        "candidates": [
          [
            "content": [
              "parts": [
                [
                  "inlineData": [
                    "mimeType": "audio/L16;rate=24000", "data": pcm.base64EncodedString(),
                  ]
                ]
              ]
            ]
          ]
        ]
      ])
      let sse =
        "data: " + String(data: audio, encoding: .utf8)!
        + "\n\ndata: {\"candidates\":[{\"finishReason\":\"STOP\"}]}\n\n"
      return (200, Data(sse.utf8))
    }
    let recording = SpeechRecording()
    try await service.streamSpeech(key: "dummy", text: "Testo intero", voice: "Kore", style: .dj) {
      chunk in
      try await recording.append(chunk)
    }
    let result = await recording.contents()
    XCTAssertEqual(result, pcm)
  }

  func testSpeechStreamingHTTPError() async {
    let service = service { _ in (403, Data()) }
    do {
      try await service.streamSpeech(key: "dummy", text: "T", voice: "Kore", style: .dj) { _ in
        XCTFail()
      }
      XCTFail()
    } catch let error as GeminiAPIError {
      XCTAssertEqual(error.status, 403)
    } catch { XCTFail("Unexpected error") }
  }

  func testTranslationKeepsOriginalLineCountAndUsesExistingKey() async throws {
    let service = service { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "dummy-test-key")
      let body = try self.body(request)
      let config = body["generationConfig"] as? [String: Any]
      XCTAssertEqual(config?["responseMimeType"] as? String, "application/json")
      return (
        200,
        try JSONSerialization.data(withJSONObject: [
          "candidates": [["content": ["parts": [["text": "[\"Ciao\",\"\",\"Mondo\"]"]]]]]
        ])
      )
    }
    let rows = try await service.translateLyrics(
      key: "dummy-test-key", model: "gemini-3.8-flash", lines: ["Hello", "", "World"],
      language: "Italiano")
    XCTAssertEqual(rows, ["Ciao", "", "Mondo"])
  }
  func testTranslationRejectsMissingOrExtraLines() async {
    let service = service { _ in
      (
        200,
        try JSONSerialization.data(withJSONObject: [
          "candidates": [["content": ["parts": [["text": "[\"Invented extra row\"]"]]]]]
        ])
      )
    }
    do {
      _ = try await service.translateLyrics(
        key: "dummy-test-key", model: "gemini-3.8-flash", lines: ["A", "B"], language: "Italiano")
      XCTFail("Mismatched translation accepted")
    } catch {}
  }

}

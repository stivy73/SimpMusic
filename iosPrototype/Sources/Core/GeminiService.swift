import Foundation

public struct GeminiService: Sendable {
  let session: URLSession
  public init(session: URLSession = .shared) { self.session = session }

  public func explain(
    key: String, model: String, title: String, artist: String, lyrics: String,
    optimizeForLatency: Bool = true, retryLength: Bool = true
  )
    async throws -> String
  {
    let context = try Interpretation.context(title: title, artist: artist, lyrics: lyrics)
    guard model.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil else {
      throw PrototypeError.invalidModel
    }
    let url = URL(
      string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    var text = ""
    for attempt in 0..<(retryLength ? 2 : 1) {
      try Task.checkCancellation()
      let instruction =
        Interpretation.systemPrompt
        + (attempt == 0
          ? ""
          : "\nLa risposta precedente aveva \(text.count) caratteri. Riscrivila nell'intervallo richiesto.")
      var body: [String: Any] = [
        "systemInstruction": ["parts": [["text": instruction]]],
        "contents": [["role": "user", "parts": [["text": context]]]],
      ]
      // Only configure the verified default model; custom model capabilities may differ.
      if optimizeForLatency && model == "gemini-3.8-flash" {
        body["generationConfig"] = ["thinkingConfig": ["thinkingLevel": "low"]]
      }
      let json = try await post(url: url, key: key, body: body, timeout: retryLength ? 90 : 25)
      guard let candidates = json["candidates"] as? [[String: Any]],
        let content = candidates.first?["content"] as? [String: Any],
        let parts = content["parts"] as? [[String: Any]]
      else { throw PrototypeError.invalidResponse }
      text = parts.filter { ($0["thought"] as? Bool) != true }
        .compactMap { $0["text"] as? String }.joined().trimmingCharacters(
          in: .whitespacesAndNewlines)
      guard !text.isEmpty else { throw PrototypeError.invalidResponse }
      if Interpretation.isExpectedLength(text) { return text }
    }
    // Preserve whole sentences if the model ignores the requested length; don't truncate TTS.
    return text
  }

  public func speech(key: String, text: String, voice: String, style: VoiceStyle) async throws
    -> Data
  {
    let body: [String: Any] = [
      "model": "gemini-3.8-flash-tts",
      "input": [
        [
          "type": "user_input",
          "content": [
            [
              "type": "text", "text": text,
              "annotations": [["type": "speech_metadata", "style": style.instruction]],
            ]
          ],
        ]
      ],
      "response_format": ["type": "audio"],
      "generation_config": ["speech_config": [["voice": voice]]],
    ]
    let json = try await post(
      url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!,
      key: key, body: body
    )
    return try Self.decodeSpeech(json)
  }

  public static func decodeSpeech(_ json: [String: Any]) throws -> Data {
    let steps = json["steps"] as? [[String: Any]] ?? []
    let audio = steps.filter { ($0["type"] as? String) == "model_output" }
      .flatMap { $0["content"] as? [[String: Any]] ?? [] }
      .filter { ($0["type"] as? String) == "audio" }
    guard let encoded = audio.last?["data"] as? String,
      let data = Data(base64Encoded: encoded), data.count >= 44,
      String(data: data.prefix(4), encoding: .ascii) == "RIFF",
      String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WAVE"
    else {
      throw PrototypeError.invalidResponse
    }
    // A valid header alone does not prove that the audio body arrived completely.
    let bytes = [UInt8](data)
    let declared = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
    guard declared + 8 <= data.count else { throw PrototypeError.invalidResponse }
    return data
  }

  private func post(url: URL, key: String, body: [String: Any], timeout: TimeInterval = 90)
    async throws -> [String: Any]
  {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PrototypeError.missingKey
    }
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await session.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode else {
      throw PrototypeError.invalidResponse
    }
    guard (200..<300).contains(status) else { throw PrototypeError.http(status) }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw PrototypeError.invalidResponse
    }
    return json
  }
}

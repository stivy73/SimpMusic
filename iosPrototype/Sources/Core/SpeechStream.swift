import Foundation

/// Gemini sends signed 16-bit little-endian, mono PCM at 24 kHz.
public struct GeminiSpeechDecoder: Sendable {
  public private(set) var finished = false
  private var receivedAudio = false
  public init() {}

  public mutating func consume(_ line: String) throws -> [Data] {
    guard line.hasPrefix("data:") else { return [] }
    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if payload == "[DONE]" {
      try validateCompletion()
      return []
    }
    guard let json = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
      json["error"] == nil
    else { throw SpeechStreamError.invalidEvent }
    guard let candidates = json["candidates"] as? [[String: Any]], let candidate = candidates.first
    else {
      if json["usageMetadata"] != nil { return [] }
      throw SpeechStreamError.missingCandidate
    }
    if let reason = candidate["finishReason"] as? String, reason != "STOP" {
      throw SpeechStreamError.unfinished
    }
    let content = candidate["content"] as? [String: Any]
    let parts = content?["parts"] as? [[String: Any]] ?? []
    var chunks: [Data] = []
    for part in parts {
      guard let inline = part["inlineData"] as? [String: Any] else { continue }
      guard !finished,
        let mime = inline["mimeType"] as? String,
        Self.supports(mime),
        let encoded = inline["data"] as? String, let data = Data(base64Encoded: encoded),
        !data.isEmpty, data.count.isMultiple(of: 2)
      else { throw SpeechStreamError.invalidAudioFormat }
      receivedAudio = true
      chunks.append(data)
    }
    if candidate["finishReason"] as? String == "STOP" { finished = true }
    return chunks
  }

  private static func supports(_ mime: String) -> Bool {
    let fields = mime.lowercased().split(separator: ";").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    guard fields.first == "audio/l16" else { return false }
    var parameters: [String: String] = [:]
    for field in fields.dropFirst() {
      let pair = field.split(separator: "=", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard pair.count == 2, parameters[pair[0]] == nil else { return false }
      parameters[pair[0]] = pair[1]
    }
    return parameters["rate"] == "24000"
      && (parameters["channels"] ?? "1") == "1"
      && (parameters["codec"] ?? "pcm") == "pcm"
      && Set(parameters.keys).isSubset(of: ["rate", "channels", "codec"])
  }

  public func validateCompletion() throws {
    guard receivedAudio else { throw SpeechStreamError.emptyAudio }
    guard finished else { throw SpeechStreamError.unfinished }
  }
}

extension GeminiService {
  public static let speechModel = "gemini-3.8-flash-tts"

  /// Backpressure is controlled by the receiver. Cancelling the caller cancels the HTTP task too.
  public func streamSpeech(
    key: String, text: String, voice: String, style: VoiceStyle,
    receive: @Sendable (Data) async throws -> Void
  ) async throws {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PrototypeError.missingKey
    }
    let url = URL(
      string:
        "https://generativelanguage.googleapis.com/v1beta/models/\(Self.speechModel):streamGenerateContent?alt=sse"
    )!
    var request = URLRequest(url: url, timeoutInterval: 90)
    request.httpMethod = "POST"
    request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "contents": [
        [
          "role": "user",
          "parts": [
            [
              "text": text, "speech_metadata": ["style": style.instruction],
            ]
          ],
        ]
      ],
      "generationConfig": [
        "responseModalities": ["AUDIO"],
        "speechConfig": ["voiceConfig": ["voice": voice]],
      ],
    ])
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let response = response as? HTTPURLResponse else { throw PrototypeError.invalidResponse }
    guard (200..<300).contains(response.statusCode) else {
      throw PrototypeError.http(response.statusCode)
    }
    var decoder = GeminiSpeechDecoder()
    for try await line in bytes.lines {
      try Task.checkCancellation()
      for chunk in try decoder.consume(line) { try await receive(chunk) }
    }
    try Task.checkCancellation()
    try decoder.validateCompletion()
  }
}

public enum SpeechStreamError: LocalizedError {
  case invalidEvent, missingCandidate, invalidAudioFormat, emptyAudio, unfinished, playbackStopped
  public var errorDescription: String? {
    switch self {
    case .invalidEvent: "Il servizio vocale ha restituito un evento non valido. Riprova."
    case .missingCandidate: "La risposta vocale non contiene un risultato. Riprova."
    case .invalidAudioFormat: "Il formato audio ricevuto non è supportato."
    case .emptyAudio: "Il servizio vocale non ha inviato audio. Riprova."
    case .playbackStopped: "La riproduzione della voce si è interrotta. Puoi riprovarla."
    case .unfinished: "La generazione della voce non è stata completata. Riprova."
    }
  }
}

import CryptoKit
import Foundation

public enum PrototypeError: LocalizedError {
  case missingLyrics, missingKey, invalidResponse
  case http(Int)
  case playbackHTTP(Int)
  case invalidModel
  public var errorDescription: String? {
    switch self {
    case .missingLyrics:
      "Testo non trovato neanche nelle fonti online. Puoi inserirlo manualmente: non genero un'interpretazione basata solo sul titolo."
    case .missingKey: "Inserisci la chiave Gemini nelle impostazioni."
    case .invalidResponse: "La risposta del servizio non contiene il contenuto richiesto."
    case .http(let code):
      "Il servizio ha risposto con HTTP \(code). Controlla chiave, modello e quota."
    case .playbackHTTP(let code):
      "YouTube ha rifiutato lo stream audio (HTTP \(code)). Prova un altro risultato."
    case .invalidModel: "Nome del modello non valido."
    }
  }
}

public enum Interpretation {
  // Keep identical to Android AiService.explainSong; checked by CheckAndroidPrompt.py.
  public static let systemPrompt =
    "Analizza la canzone scrivendo esclusivamente in italiano, anche se il titolo o il testo sono in un'altra lingua. Organizza la risposta in due parti, nell'ordine seguente. Prima racconta in modo chiaro la storia o la situazione descritta dal testo: chi parla, cosa accade e come evolve il racconto. Poi fornisci l'interpretazione, spiegando temi, emozioni, immagini, simboli e possibili letture. Distingui le interpretazioni dai fatti documentati sull'artista. Non inventare retroscena, non riprodurre versi e segnala quando il testo non basta per una conclusione affidabile. La risposta completa deve essere di circa 900 caratteri, spazi compresi, con una tolleranza del 5%: deve quindi contenere tra 855 e 945 caratteri. Dedica spazio a entrambe le parti."

  public static func context(title: String, artist: String, lyrics: String) throws -> String {
    guard !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PrototypeError.missingLyrics
    }
    return
      "Canzone: \(title)\nArtista: \(artist)\nTesto della canzone, solo come contesto:\n\(lyrics.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000))"
  }

  public static func isExpectedLength(_ text: String) -> Bool { (855...945).contains(text.count) }
}

public enum VoiceStyle: String, CaseIterable, Identifiable, Codable, Sendable {
  case professional = "Professionale"
  case dj = "DJ"
  case empathetic = "Empatico"
  public var id: String { rawValue }
  public var instruction: String {
    switch self {
    case .professional: "Voce italiana chiara, naturale e professionale, ritmo tranquillo."
    case .dj: "Voce italiana da DJ radiofonico, energica e coinvolgente, senza cantare."
    case .empathetic:
      "Voce italiana calda ed empatica, pause naturali e leggere esitazioni vocali, senza aggiungere o cambiare parole."
    }
  }
}

/// Reuse the exact interpretation so that the corresponding speech cache can also hit.
/// Keyed by the actual source text, model and prompt, never by title alone.
public actor InterpretationCache {
  public static let shared = InterpretationCache()
  private let directory: URL
  private let capacity: Int
  private let lifetime: TimeInterval
  public init(directory: URL? = nil, capacity: Int = 50, lifetime: TimeInterval = 7 * 86400) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeaningText-v1", isDirectory: true)
    self.capacity = max(1, capacity)
    self.lifetime = lifetime
  }
  public nonisolated static func key(model: String, title: String, artist: String, lyrics: String)
    throws -> String
  {
    let context = try Interpretation.context(title: title, artist: artist, lyrics: lyrics)
    let fields = ["low-thinking-v1", model, Interpretation.systemPrompt, context]
    return SHA256.hash(data: Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
  private func file(_ key: String) -> URL? {
    guard key.count == 64, key.allSatisfy({ $0.isHexDigit }) else { return nil }
    return directory.appendingPathComponent(key).appendingPathExtension("txt")
  }
  public func read(_ key: String) -> String? {
    guard let url = file(key),
      let info = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
      let size = info.fileSize, (1...16000).contains(size),
      let date = info.contentModificationDate, Date().timeIntervalSince(date) < lifetime,
      let text = try? String(contentsOf: url, encoding: .utf8),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return text
  }
  public func store(_ text: String, key: String) {
    guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.utf8.count <= 16000, let url = file(key)
    else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var excluded = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excluded.setResourceValues(values)
      try text.write(to: url, atomically: true, encoding: .utf8)
      let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey]
      )
      .filter { $0.pathExtension == "txt" }
      .sorted { a, b in
        let left = try? a.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
        let right = try? b.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
        return (left ?? .distantPast) > (right ?? .distantPast)
      }
      for old in files.dropFirst(capacity) { try? FileManager.default.removeItem(at: old) }
    } catch {
      // An optional cache must not prevent narration.
    }
  }
}

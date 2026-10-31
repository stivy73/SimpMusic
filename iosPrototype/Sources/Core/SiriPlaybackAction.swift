import Foundation

/// Preconditions shared by Siri actions; a failed command must not alter playback.
public enum SiriPlaybackAction: String, Sendable {
  case resume, pause, explain, radio, next

  public func validate(
    hasSong: Bool, loading: Bool = false,
    narrating: Bool = false, hasGeminiKey: Bool = false
  ) throws {
    guard hasSong else { throw SiriPlaybackError.noSong }
    if self == .explain {
      guard !narrating else { throw SiriPlaybackError.narrationInProgress }
      guard !loading else { throw SiriPlaybackError.loading }
    }
    if self == .explain || self == .radio {
      guard hasGeminiKey else { throw SiriPlaybackError.missingGeminiKey }
    }
  }
}

public enum SiriPlaybackError: Error, LocalizedError, Equatable {
  case noSong, loading, narrationInProgress, missingGeminiKey
  public var errorDescription: String? {
    switch self {
    case .noSong: "Seleziona prima un brano in NoteNarrate."
    case .loading: "Il brano si sta preparando. Riprova tra poco."
    case .narrationInProgress: "L’interpretazione è già in preparazione o in lettura."
    case .missingGeminiKey: "Configura la chiave Gemini nelle impostazioni di NoteNarrate."
    }
  }
}

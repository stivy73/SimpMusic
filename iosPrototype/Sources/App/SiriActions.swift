#if os(iOS)
  import AppIntents
  import Foundation

  @MainActor
  enum SiriPlaybackCommands {
    static func perform(_ action: SiriPlaybackAction) throws {
      let app = AppleAppSession.shared
      let music = app.music
      try action.validate(
        hasSong: music.current != nil, loading: music.player.isLoading,
        narrating: music.busyMeaning || music.reading,
        hasGeminiKey: !music.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      switch action {
      case .resume:
        music.stopMeaning(resume: false)
        music.player.play()
      case .pause:
        music.stopMeaning(resume: false)
        music.player.pause()
      case .explain:
        // Keep music alive during preparation, just like the CarPlay narration button.
        guard music.explain(presentOnPhone: false) else { throw SiriPlaybackError.loading }
        music.narrationDiagnostic = "Siri: preparo interpretazione narrata"
      case .radio:
        music.stopMeaning(resume: true)
        music.startRadio(song: music.current)
      case .next:
        music.stopMeaning(resume: false)
        music.nextSong()
      }
      app.widgets.publish()
    }
  }

  struct ExplainCurrentSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Spiega la canzone corrente"
    static let description = IntentDescription(
      "Prepara e legge il significato del brano corrente con Gemini.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
      try await SiriPlaybackCommands.perform(.explain)
      return .result(dialog: "Preparo l’interpretazione narrata della canzone.")
    }
  }

  struct CreateSongRadioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Crea una radio dal brano corrente"
    static let description = IntentDescription(
      "Genera una nuova radio Gemini fino a 50 brani, completandola in background.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
      try await SiriPlaybackCommands.perform(.radio)
      return .result(dialog: "Preparo una nuova radio dal brano corrente.")
    }
  }

  struct ResumeNoteNarrateIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Riprendi la musica"
    static let description = IntentDescription(
      "Interrompe l’eventuale interpretazione e riprende il brano.")
    func perform() async throws -> some IntentResult {
      try await SiriPlaybackCommands.perform(.resume)
      return .result()
    }
  }

  struct PauseNoteNarrateIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Metti in pausa la musica"
    func perform() async throws -> some IntentResult {
      try await SiriPlaybackCommands.perform(.pause)
      return .result()
    }
  }

  struct NextNoteNarrateSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Passa al brano successivo"
    func perform() async throws -> some IntentResult {
      try await SiriPlaybackCommands.perform(.next)
      return .result()
    }
  }

  struct NoteNarrateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
      AppShortcut(
        intent: ExplainCurrentSongIntent(),
        phrases: [
          "Spiegami questa canzone con \(.applicationName)",
          "Leggi il significato della canzone con \(.applicationName)",
        ], shortTitle: "Spiega la canzone", systemImageName: "lightbulb")
      AppShortcut(
        intent: CreateSongRadioIntent(),
        phrases: [
          "Crea una radio da questo brano con \(.applicationName)",
          "Avvia la radio del brano con \(.applicationName)",
        ], shortTitle: "Radio del brano", systemImageName: "dot.radiowaves.left.and.right")
      AppShortcut(
        intent: ResumeNoteNarrateIntent(),
        phrases: [
          "Riprendi la musica con \(.applicationName)", "Riprendi \(.applicationName)",
        ], shortTitle: "Riprendi musica", systemImageName: "play.fill")
      AppShortcut(
        intent: PauseNoteNarrateIntent(),
        phrases: [
          "Metti in pausa \(.applicationName)"
        ], shortTitle: "Pausa", systemImageName: "pause.fill")
      AppShortcut(
        intent: NextNoteNarrateSongIntent(),
        phrases: [
          "Prossimo brano con \(.applicationName)"
        ], shortTitle: "Brano successivo", systemImageName: "forward.end.fill")
    }
  }
#endif

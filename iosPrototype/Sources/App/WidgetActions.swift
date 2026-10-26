#if os(iOS)
  import AppIntents
  import WidgetKit

  struct WidgetPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Riproduci o metti in pausa NoteNarrate"
    static let description = IntentDescription("Controlla il brano corrente, anche dal widget.")
    func perform() async throws -> some IntentResult {
      #if !NOTENARRATE_WIDGET
        await MainActor.run {
          let music = AppleAppSession.shared.music
          if music.reading || music.busyMeaning {
            music.stopMeaning(resume: true)
          } else if music.player.wantsPlayback {
            music.player.pause()
          } else {
            music.player.play()
          }
          AppleAppSession.shared.widgets.publish()
        }
      #else
        try requireWidgetHostApp()
      #endif
      return .result()
    }
  }
  struct WidgetNextIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Brano successivo in NoteNarrate"
    func perform() async throws -> some IntentResult {
      #if !NOTENARRATE_WIDGET
        await MainActor.run {
          let app = AppleAppSession.shared
          app.music.nextSong()
          app.widgets.publish()
        }
      #else
        try requireWidgetHostApp()
      #endif
      return .result()
    }
  }
  private enum WidgetActionError: Error { case appRequired }
  private func requireWidgetHostApp() throws { throw WidgetActionError.appRequired }
#endif

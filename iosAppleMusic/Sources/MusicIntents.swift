import AppIntents
@preconcurrency import MusicKit

struct ResumeMusicIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Riprendi musica"
  static let openAppWhenRun = false
  @MainActor func perform() async throws -> some IntentResult {
    await MusicAppState.shared.music.resume();return .result()
  }
}
struct PauseMusicIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Pausa musica"
  static let openAppWhenRun = false
  @MainActor func perform() async throws -> some IntentResult {
    MusicAppState.shared.music.player.pause();MusicAppState.shared.narration.stop();return .result()
  }
}
struct NextMusicIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Brano successivo"
  static let openAppWhenRun = false
  @MainActor func perform() async throws -> some IntentResult {
    try await MusicAppState.shared.music.player.skipToNextEntry();return .result()
  }
}
struct MusicShortcuts: AppShortcutsProvider {
  static var appShortcuts:[AppShortcut] {
    AppShortcut(intent:ResumeMusicIntent(),phrases:["Riprendi la musica con \(.applicationName)"],shortTitle:"Riprendi",systemImageName:"play.fill")
    AppShortcut(intent:PauseMusicIntent(),phrases:["Metti in pausa \(.applicationName)"],shortTitle:"Pausa",systemImageName:"pause.fill")
    AppShortcut(intent:NextMusicIntent(),phrases:["Brano successivo con \(.applicationName)"],shortTitle:"Successivo",systemImageName:"forward.end.fill")
  }
}

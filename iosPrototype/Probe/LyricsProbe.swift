import Foundation
import PrototypeCore

func probeLyricsIfRequested(_ args: [String]) async throws -> Bool {
  guard args.first == "--lyrics-fallback" else { return false }
  guard args.count == 3 else {
    throw NSError(
      domain: "LyricsProbe", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Use --lyrics-fallback 'title' 'artist'"])
  }
  let resolver = LyricsResolver(primary: { _ in nil })
  let start = Date()
  let result = try await resolver.resolve(
    LyricsQuery(videoID: "probe", title: args[1], artist: args[2]))
  print(
    "Fallback source: \(result?.source.rawValue ?? "none"); characters: \(result?.text.count ?? 0); seconds: \(String(format: "%.2f", Date().timeIntervalSince(start)))"
  )
  guard let result else { throw PrototypeError.missingLyrics }
  let context = try Interpretation.context(title: args[1], artist: args[2], lyrics: result.text)
  print(
    "Interpretation context contains recovered lyrics: \(context.contains(String(result.text.prefix(100))))"
  )
  print(
    "No API key, lyrics content or interpretation is printed. This probe does not verify TTS or playback."
  )
  return true
}

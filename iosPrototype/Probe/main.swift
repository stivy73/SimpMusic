import AVFoundation
import Foundation
import PrototypeCore
import YouTubeSDK

// Diagnostic timings only: never print request headers, bodies, or API keys.
final class ProbeTimings: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    let phase = task.originalRequest?.url?.lastPathComponent ?? "request"
    print("API \(phase): \(String(format: "%.2f", metrics.taskInterval.duration)) seconds")
  }
}

do {
  let args = Array(CommandLine.arguments.dropFirst())
  if try await probeAudioIfRequested(args) { exit(0) }
  if try await probeLyricsIfRequested(args) { exit(0) }
  if try await probeHomeIfRequested(args) { exit(0) }
  if try await probeStreamingIfRequested(args) { exit(0) }
  let live = args.first == "--gemini-key-file"
  let query =
    live
    ? "Old and Wise The Alan Parsons Project"
    : (args.first ?? "Old and Wise The Alan Parsons Project")
  let music = YouTubeMusicClient()
  let songs = try await music.search(query)
  print("Search: \(songs.count) results")
  for song in songs.prefix(3) { print("\(song.title) — \(song.artistsDisplay) [\(song.videoId)]") }
  guard let song = songs.first else { throw NSError(domain: "Probe", code: 1) }
  let lyricsStart = Date()
  let resolved = try await LyricsResolver().resolve(
    LyricsQuery(videoID: song.videoId, title: song.title, artist: song.artistsDisplay)
  ) {
    print("YouTube lyrics unavailable; searching LRCLIB by title and artist")
  }
  let lyrics = resolved?.text
  print(
    "Lyrics retrieval: \(String(format: "%.2f", Date().timeIntervalSince(lyricsStart))) seconds")
  print("Lyrics available: \(lyrics?.count ?? 0) characters (contents not logged)")
  print("Lyrics source: \(resolved?.source.rawValue ?? "none")")
  if live {
    guard args.count == 2, let lyrics, !lyrics.isEmpty else {
      throw PrototypeError.missingLyrics
    }
    // Read only the explicitly labelled Gemini key; never log credentials or API bodies.
    let source = try String(contentsOfFile: args[1], encoding: .utf8)
    let lines = source.components(separatedBy: .newlines)
    guard
      let label = lines.firstIndex(where: {
        $0.trimmingCharacters(in: .whitespaces) == "Gemini key"
      }),
      label + 1 < lines.count
    else { throw PrototypeError.missingKey }
    let key = lines[label + 1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard key.range(of: #"^AIza[A-Za-z0-9_-]{35}$"#, options: .regularExpression) != nil else {
      throw PrototypeError.missingKey
    }
    let session = URLSession(configuration: .default, delegate: ProbeTimings(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let service = GeminiService(session: session)
    let start = Date()
    let text = try await service.explain(
      key: key, model: "gemini-3.8-flash", title: song.title,
      artist: song.artistsDisplay, lyrics: lyrics)
    print(
      "Gemini interpretation OK: \(text.count) characters; expected length: \(Interpretation.isExpectedLength(text)); seconds: \(Int(Date().timeIntervalSince(start)))"
    )
    let speechStart = Date()
    let wav = try await service.speech(key: key, text: text, voice: "Kore", style: .professional)
    let audio = try AVAudioPlayer(data: wav)
    guard audio.duration > 0, audio.prepareToPlay() else { throw PrototypeError.invalidResponse }
    print(
      "Gemini TTS OK: \(wav.count) bytes; decoded duration: \(Int(audio.duration)) seconds; generation: \(Int(Date().timeIntervalSince(speechStart))) seconds"
    )
    print(
      "Live API and audio decoding verified. App playback, voice quality and automatic music resume not verified by this probe."
    )
  } else {
    print("This probe verifies search and lyrics, not audiovisual playback.")
  }
} catch {
  print("Probe failed: \(error.localizedDescription)")
  exit(1)
}

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
  if args.first == "--lyrics-catalog" {
    let items = try await HomeDiscovery(session: nil).search(
      query: "Tracy Chapman Baby Can I Hold You", filter: .songs)
    guard let song = items.first else { throw LyricsLookupError.unavailable }
    let query = LyricsQuery(
      videoID: song.mediaId, title: song.title, artist: song.subtitle,
      durationSeconds: song.durationSeconds)
    for provider in [LyricsProviderChoice.simpMusic, .better] {
      do {
        let result = try await ExtraLyrics().fetch(query, provider: provider)
        print(
          "Provider \(provider.rawValue): text \(result != nil), synchronized lines \(LyricsTimeline(lrc: result?.syncedText ?? "").lines.count)"
        )
      } catch { print("Provider \(provider.rawValue): unavailable (\(type(of: error)))") }
    }
    let entries = try await AutoEqCatalog().entries()
    print("AutoEq: \(entries.count) profiles")
    if let entry = entries.first(where: { $0.name == "Sennheiser HD 650" }) {
      let profile = try await AutoEqCatalog().profile(entry)
      print("AutoEq profile: \(profile.gains.count) bands, valid \(profile.valid)")
    }
    exit(0)
  } else if args.first == "--radio" {
    let service = MusicRadio(session: nil)
    let endpoint = RadioEndpoint.song(args.count > 1 ? args[1] : "ZmzqqdVFw8g")
    let page = try await service.page(endpoint: endpoint)
    print("Radio: \(page.items.count) tracks; continuation: \(page.continuation != nil)")
    guard !page.items.isEmpty else { throw RadioError.unavailable }
    if let token = page.continuation {
      let next = try await service.page(endpoint: page.endpoint, continuation: token)
      print("Radio continuation: \(next.items.count) tracks")
      guard !next.items.isEmpty else { throw RadioError.unavailable }
    }
    let search = try await HomeDiscovery(session: nil).search(
      query: "The Alan Parsons Project", filter: .artists)
    if let artist = search.first {
      let artistEndpoint = try await service.artistEndpoint(id: artist.mediaId)
      let artistPage = try await service.page(endpoint: artistEndpoint)
      print("Artist radio: \(artistPage.items.count) tracks")
      guard !artistPage.items.isEmpty else { throw RadioError.unavailable }
    } else {
      throw RadioError.unavailable
    }
    exit(0)
  }
  if args.first == "--full-search" {
    let discovery = HomeDiscovery(session: nil)
    for filter in MusicSearchFilter.allCases {
      let query =
        filter == .podcasts
        ? "Daily" : filter == .playlists || filter == .communityPlaylists ? "Rock" : "Fleetwood Mac"
      let start = Date()
      let page = try await discovery.searchPage(query: query, filter: filter)
      print(
        "Search \(filter.identifier): \(page.items.count) items; continuation \(page.continuation != nil); seconds \(String(format: "%.2f", Date().timeIntervalSince(start)))"
      )
      guard !page.items.isEmpty else { throw URLError(.cannotParseResponse) }
      if let token = page.continuation {
        let next = try await discovery.searchPage(query: query, filter: filter, continuation: token)
        print("Search next \(filter.identifier): \(next.items.count) items")
        guard !next.items.isEmpty else { throw URLError(.cannotParseResponse) }
      }
    }
    exit(0)
  }
  if args.first == "--typed-search" {
    let discovery = HomeDiscovery(session: nil)
    for filter in MusicSearchFilter.carPlay {
      let items = try await discovery.search(
        query: args.count > 1 ? args[1] : "Fleetwood Mac", filter: filter)
      print(
        "Typed search \(filter.rawValue): \(items.count) results; types \(Set(items.map { $0.kind.rawValue }).sorted())"
      )
      guard !items.isEmpty else { throw URLError(.cannotParseResponse) }
    }
    exit(0)
  }
  if try await probeAudioIfRequested(args) { exit(0) }
  if try await probeLyricsIfRequested(args) { exit(0) }
  if try await probeHomeIfRequested(args) { exit(0) }
  if try await probeStreamingIfRequested(args) { exit(0) }
  let streamMeaning = args.first == "--meaning-stream-key-file"
  let live = args.first == "--gemini-key-file" || streamMeaning
  let query =
    live
    ? (args.count > 2 ? args[2] : "Old and Wise The Alan Parsons Project")
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
    guard args.count >= 2, let lyrics, !lyrics.isEmpty else {
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
      artist: song.artistsDisplay, lyrics: lyrics, retryLength: false)
    print(
      "Gemini interpretation OK: \(text.count) characters; expected length: \(Interpretation.isExpectedLength(text)); seconds: \(Int(Date().timeIntervalSince(start)))"
    )
    let speechStart = Date()
    if streamMeaning {
      let recording = SpeechRecording()
      try await service.streamSpeech(key: key, text: text, voice: "Kore", style: .professional) {
        bytes in
        try await recording.append(bytes)
      }
      let pcm = await recording.contents()
      print(
        "Live interpretation-to-stream OK: \(pcm.count) PCM bytes, \(String(format: "%.2f", Double(pcm.count) / 48_000)) audio seconds"
      )
      print(
        "Audio output and CarPlay routing require a separate device test; no lyrics, key or interpretation were logged."
      )
      exit(0)
    }
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

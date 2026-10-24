import AVFoundation
import Combine
import SwiftUI
import WebKit
import YouTubeSDK

/// One embedded playback session is retained when switching artwork, lyrics and video.
#if os(macOS)
  @MainActor
  final class PlaybackPlayer: ObservableObject {
    @Published var isLoading = false
    @Published var playbackError: String?
    @Published var videoId = ""
    @Published var loadID = UUID()
    @Published var elapsed = 0.0
    @Published var durationSeconds = 0.0
    @Published var playing = false
    @Published var volume = 100.0
    var onEnded: (() -> Void)?
    var wantsPlayback = false
    weak var webView: WKWebView?
    var rate: Float { playing ? 1 : 0 }
    var timeControlStatus: AVPlayer.TimeControlStatus { playing ? .playing : .paused }

    func load(videoId: String) {
      pause()
      webView?.stopLoading()
      self.videoId = videoId
      isLoading = true
      playbackError = nil
      elapsed = 0
      durationSeconds = 0
      playing = false
      wantsPlayback = true
      loadID = UUID()
    }
    func play() {
      wantsPlayback = true
      webView?.evaluateJavaScript("player.playVideo()", completionHandler: nil)
    }
    func pause() {
      wantsPlayback = false
      webView?.evaluateJavaScript("player.pauseVideo()", completionHandler: nil)
      playing = false
    }
    func seek(to time: CMTime) {
      guard time.seconds.isFinite else { return }
      webView?.evaluateJavaScript(
        "player.seekTo(\(max(0, time.seconds)), true)", completionHandler: nil)
    }
    func setVolume(_ value: Double) {
      volume = min(100, max(0, value))
      webView?.evaluateJavaScript("player.setVolume(\(Int(volume)))", completionHandler: nil)
    }
    func currentTime() -> CMTime { CMTime(seconds: elapsed, preferredTimescale: 600) }
  }
#endif

struct Song: Identifiable, Codable, Hashable {
  let id: String
  let title: String
  let artist: String
  let artwork: URL?
  let durationSeconds: Double?
  var albumBrowseID: String? = nil
  var albumTitle: String? = nil
  var artistBrowseID: String? = nil
  init(id: String, title: String, artist: String, artwork: URL?, durationSeconds: Double? = nil) {
    self.id = id
    self.title = title
    self.artist = artist
    self.artwork = artwork
    self.durationSeconds = durationSeconds
  }
  init(_ item: DiscoveryItem) {
    albumBrowseID = item.albumBrowseID
    artistBrowseID = item.artistBrowseID
    albumTitle = item.albumTitle
    id = item.mediaId
    title = item.title
    artist = item.subtitle
    artwork = item.artwork
    durationSeconds = item.durationSeconds
  }
  func withAlbumArtwork(
    _ albumArtwork: URL?, artist albumArtist: String? = nil, albumID: String? = nil
  ) -> Song {
    var result = Song(
      id: id, title: title,
      artist: artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? albumArtist ?? artist : artist,
      artwork: albumArtwork ?? artwork,
      durationSeconds: durationSeconds)
    result.artistBrowseID = artistBrowseID
    result.albumTitle = albumTitle
    result.albumBrowseID = albumID ?? albumBrowseID
    return result
  }
  init(_ song: YouTubeMusicSong, albumArtwork: URL? = nil) {
    id = song.videoId
    title = song.title
    artist = song.artistsDisplay
    artwork = albumArtwork ?? song.thumbnailURL
    durationSeconds = song.duration
    albumTitle = song.album
    albumBrowseID = song.albumBrowseID
    artistBrowseID = song.artistBrowseID
  }
}

@MainActor
final class MusicModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  let player = PlaybackPlayer()
  private let music = YouTubeMusicClient()
  private let lyricsResolver = LyricsResolver()
  private let synthesizer = AVSpeechSynthesizer()
  private var streamingAudio: PCMStreamPlayer?
  private var activeUtterance: AVSpeechUtterance?
  private var explanationTask: Task<Void, Never>?
  private var preparationTimeout: Task<Void, Never>?
  private var voiceStartTimeout: Task<Void, Never>?
  var meaningRequestID: UUID { generation }
  @Published var narrationDiagnostic =
    UserDefaults.standard.string(forKey: "lastNarrationDiagnostic") ?? "Nessuna richiesta"
  {
    didSet { UserDefaults.standard.set(narrationDiagnostic, forKey: "lastNarrationDiagnostic") }
  }
  private var searchTask: Task<Void, Never>?
  private var generation = UUID()
  private var resumeSongID: String?
  #if os(iOS)
    private var meaningBackgroundTask = UIBackgroundTaskIdentifier.invalid
  #endif
  @Published var query = ""
  @Published var songs: [Song] = []
  @Published var lastSearchQuery = ""
  @Published var searching = false
  @Published var searchError: String?
  @Published var queue: [Song] = []
  @Published var lyrics = ""
  @Published var loadingLyrics = false
  @Published var lyricsError: String?
  @Published var lyricsProgress = "Recupero il testo…"
  @Published var lyricsSource: ResolvedLyrics.Source?
  @Published var lyricsSourceURL: URL?
  private var lyricsTask: Task<ResolvedLyrics?, Error>?
  private var lyricsGeneration = UUID()
  @Published var current: Song?
  @Published var showPlayer = false
  @Published var showMeaning = false
  private(set) var meaningPresentationOnPhone = true
  @Published var busyMeaning = false
  @Published var meaningProgress = "Recupero il testo…"
  @Published var reading = false
  #if DEBUG
    @Published var narrationStarts = 0
    @Published var narrationFinishes = 0
    @Published var systemArtworkAvailable = false
    @Published var systemNarrationActive = false
    var preparingNarrationInBackground: Bool {
      #if os(iOS)
        meaningBackgroundTask != .invalid
      #else
        false
      #endif
    }
  #endif
  @Published var meaning = ""
  @Published var meaningError: String?
  @Published var manualLyrics = ""
  @Published var favorites: [Song] = []
  @Published var settingsError: String?
  @Published var apiKey = SecureStore.read("gemini")
  @Published var textModel = UserDefaults.standard.string(forKey: "textModel") ?? "gemini-3.8-flash"
  @Published var useGeminiVoice =
    UserDefaults.standard.object(forKey: "geminiVoice") as? Bool ?? MusicModel.defaultGeminiVoice
  @Published var style =
    VoiceStyle(rawValue: UserDefaults.standard.string(forKey: "voiceStyle") ?? "")
    ?? MusicModel.defaultVoiceStyle
  @Published var voice = UserDefaults.standard.string(forKey: "voice") ?? MusicModel.defaultVoice

  private static var defaultGeminiVoice: Bool {
    #if os(macOS)
      true
    #else
      false
    #endif
  }
  private static var defaultVoiceStyle: VoiceStyle {
    #if os(macOS)
      .empathetic
    #else
      .professional
    #endif
  }
  private static var defaultVoice: String {
    #if os(macOS)
      "Aoede"
    #else
      "Kore"
    #endif
  }

  override init() {
    super.init()
    synthesizer.delegate = self
    #if os(iOS)
      synthesizer.usesApplicationAudioSession = true
    #endif
    player.onEnded = { [weak self] in self?.nextSong() }
    if let data = UserDefaults.standard.data(forKey: "favorites"),
      let stored = try? JSONDecoder().decode([Song].self, from: data)
    {
      favorites = stored
    }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-native-audio") {
        Task {
          play(
            Song(
              id: "ZmzqqdVFw8g", title: "Old and Wise", artist: "The Alan Parsons Project",
              artwork: URL(string: "https://i.ytimg.com/vi/ZmzqqdVFw8g/hqdefault.jpg")))
        }
      }
    #endif
  }

  func saveSettings() {
    do {
      try SecureStore.save(apiKey, as: "gemini")
      UserDefaults.standard.set(textModel, forKey: "textModel")
      UserDefaults.standard.set(useGeminiVoice, forKey: "geminiVoice")
      UserDefaults.standard.set(style.rawValue, forKey: "voiceStyle")
      UserDefaults.standard.set(voice, forKey: "voice")
      settingsError = nil
    } catch { settingsError = "Impossibile salvare la chiave nel Portachiavi." }
  }

  func search(_ suggested: String? = nil) {
    if let suggested { query = suggested }
    let requested = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requested.isEmpty else { return }
    lastSearchQuery = requested
    searchTask?.cancel()
    searching = true
    searchError = nil
    searchTask = Task {
      do {
        let results = try await music.search(requested)
        try Task.checkCancellation()
        var seen = Set<String>()
        songs = results.map { Song($0) }.filter { seen.insert($0.id).inserted }
        searching = false
      } catch is CancellationError {} catch {
        if !Task.isCancelled {
          searching = false
          searchError = error.localizedDescription
        }
      }
    }
  }

  var queueIndex: Int? { queue.firstIndex { $0.id == current?.id } }
  var hasPrevious: Bool { (queueIndex ?? 0) > 0 }
  var hasNext: Bool { queueIndex.map { $0 + 1 < queue.count } ?? false }
  func previousSong() {
    if player.elapsed > 3 {
      player.seek(to: .zero)
    } else if let index = queueIndex, index > 0 {
      play(queue[index - 1])
    }
  }
  func nextSong() {
    if let index = queueIndex, index + 1 < queue.count { play(queue[index + 1]) }
  }

  func loadLyrics(force: Bool = false) {
    guard let song = current else { return }
    if !force && (loadingLyrics || !lyrics.isEmpty) { return }
    lyricsTask?.cancel()
    let token = UUID()
    lyricsGeneration = token
    loadingLyrics = true
    lyricsError = nil
    lyricsProgress = "Recupero il testo…"
    let query = LyricsQuery(
      videoID: song.id, title: song.title, artist: song.artist,
      durationSeconds: player.durationSeconds > 0 ? player.durationSeconds : song.durationSeconds)
    let task = Task {
      try await lyricsResolver.resolve(query, force: force) { [weak self] in
        await self?.lyricsFallbackStarted(token: token)
      }
    }
    lyricsTask = task
    Task {
      do {
        let result = try await task.value
        guard !task.isCancelled, lyricsGeneration == token, current?.id == song.id else { return }
        lyrics = result?.text ?? ""
        lyricsSource = result?.source
        lyricsSourceURL = result?.sourceURL
        lyricsError = lyrics.isEmpty ? "Testo non disponibile per questo brano." : nil
        loadingLyrics = false
      } catch {
        guard !task.isCancelled, lyricsGeneration == token, current?.id == song.id else { return }
        lyricsError = error.localizedDescription
        loadingLyrics = false
      }
    }
  }

  private func lyricsFallbackStarted(token: UUID) {
    guard token == lyricsGeneration else { return }
    lyricsProgress = "Cerco il testo online…"
    if busyMeaning { meaningProgress = lyricsProgress }
  }

  func play(_ song: Song, queue newQueue: [Song]? = nil) {
    if let newQueue {
      queue = newQueue
    } else if !queue.contains(where: { $0.id == song.id }) {
      queue = [song]
    }
    lyricsTask?.cancel()
    lyricsTask = nil
    lyricsGeneration = UUID()
    lyrics = ""
    lyricsSource = nil
    lyricsSourceURL = nil
    loadingLyrics = false
    lyricsError = nil
    stopMeaning(resume: false)
    current = song
    manualLyrics = ""
    meaning = ""
    showPlayer = true
    player.load(videoId: song.id)
    loadLyrics()  // Fetch alongside playback, before the user asks for the interpretation.
  }

  func minimizePlayer() {
    // Presentation changes must not stop the retained playback session.
    showPlayer = false
  }

  func toggleFavorite(_ song: Song) {
    if favorites.contains(where: { $0.id == song.id }) {
      favorites.removeAll { $0.id == song.id }
    } else {
      favorites.append(song)
    }
    if let data = try? JSONEncoder().encode(favorites) {
      UserDefaults.standard.set(data, forKey: "favorites")
    }
  }

  @discardableResult
  func explain(force: Bool = false, presentOnPhone: Bool = true) -> Bool {
    guard let song = current, !player.isLoading, !busyMeaning else { return false }
    meaningPresentationOnPhone = presentOnPhone
    stopMeaning(resume: false)
    resumeSongID = player.wantsPlayback ? song.id : nil
    // CarPlay is often the only active scene. Pausing before network preparation
    // removes background audio execution before Google has returned the voice.
    // Keep music until the first audio chunk is ready, then pause for narration.
    if presentOnPhone { player.pause() }
    showMeaning = presentOnPhone
    busyMeaning = true
    meaningProgress = loadingLyrics ? lyricsProgress : "Recupero il testo…"
    meaningError = nil
    meaning = ""
    let token = UUID()
    generation = token
    narrationDiagnostic = presentOnPhone ? "Richiesta dal player" : "Richiesta da CarPlay"
    beginMeaningPreparation(token: token)
    explanationTask = Task {
      do {
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--test-carplay-meaning") {
            let delay =
              ProcessInfo.processInfo.arguments.contains("--test-carplay-delayed-preparation")
              ? 20 : 4
            try await Task.sleep(for: .seconds(delay))
          }
          if ProcessInfo.processInfo.arguments.contains("--test-stream-meaning") {
            meaning = "Interpretazione di prova streaming " + UUID().uuidString
            try await speak(meaning, token: token)
            return
          }
          if ProcessInfo.processInfo.arguments.contains("--test-meaning") {
            meaning =
              "La canzone racconta un ricordo. L'interpretazione parla di amicizia e speranza."
            try await speak(meaning, token: token)
            return
          }
        #endif
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw PrototypeError.missingKey
        }
        let lyrics: String
        if !manualLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          lyrics = manualLyrics
        } else {
          if self.lyrics.isEmpty && !loadingLyrics { loadLyrics() }
          if self.lyrics.isEmpty {
            let fetched = try await lyricsTask?.value
            try Task.checkCancellation()
            guard token == generation else { return }
            guard let fetched else { throw PrototypeError.missingLyrics }
            self.lyrics = fetched.text
            lyricsSource = fetched.source
            lyricsSourceURL = fetched.sourceURL
          }
          loadingLyrics = false
          lyrics = self.lyrics
        }
        meaningProgress = "Preparo l'interpretazione…"
        narrationDiagnostic = "Testo recuperato; preparo interpretazione"
        let cacheKey = try InterpretationCache.key(
          model: textModel, title: song.title, artist: song.artist, lyrics: lyrics)
        let cached = force ? nil : await InterpretationCache.shared.read(cacheKey)
        let interpretationStarted = Date()
        let result: String
        if let cached {
          result = cached
        } else {
          result = try await GeminiService().explain(
            key: apiKey, model: textModel, title: song.title, artist: song.artist, lyrics: lyrics,
            retryLength: false)
          try Task.checkCancellation()
          await InterpretationCache.shared.store(result, key: cacheKey)
        }
        try Task.checkCancellation()
        guard token == generation else { return }
        narrationDiagnostic =
          "Interpretazione pronta in \(Int(Date().timeIntervalSince(interpretationStarted))) s; preparo voce"
        meaning = result
        try await speak(result, token: token)
      } catch is CancellationError {} catch {
        guard token == generation else { return }
        busyMeaning = false
        reading = false
        meaningError = error.localizedDescription
        narrationDiagnostic = "Errore: " + error.localizedDescription
        endMeaningPreparation()
        resumeMusic()
      }
    }
    return true
  }

  func readAgain() {
    guard let song = current, !meaning.isEmpty else { return }
    stopMeaning(resume: false)
    resumeSongID = player.wantsPlayback ? song.id : nil
    player.pause()
    let token = UUID()
    generation = token
    beginMeaningPreparation(token: token)
    busyMeaning = true
    meaningError = nil
    explanationTask = Task {
      do {
        try await speak(meaning, token: token)
      } catch {
        guard generation == token else { return }
        busyMeaning = false
        reading = false
        meaningError = error.localizedDescription
        endMeaningPreparation()
        resumeMusic()
      }
    }
  }

  private func speak(_ text: String, token: UUID) async throws {
    meaningProgress = "Preparo la voce…"
    #if !os(macOS)
      try AppleAudioSession.activate()
    #endif
    try Task.checkCancellation()
    guard generation == token else { return }
    var cloudVoice = useGeminiVoice
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-meaning") { cloudVoice = false }
      if ProcessInfo.processInfo.arguments.contains("--test-stream-meaning") { cloudVoice = true }
    #endif
    narrationDiagnostic =
      cloudVoice ? "Gemini TTS: attendo audio" : "Voce di sistema: attendo avvio"
    if cloudVoice {
      let output = PCMStreamPlayer()
      streamingAudio = output
      let cache = SpeechAudioCache.shared
      let cacheKey = SpeechAudioCache.key(text: text, voice: voice, style: style)
      let started: @MainActor @Sendable () -> Void = { [weak self] in
        guard let self, self.generation == token else { return }
        self.narrationDiagnostic = "Gemini TTS: lettura avviata"
        self.reading = true
        self.busyMeaning = false
        self.endMeaningPreparation()
        #if DEBUG
          self.narrationStarts += 1
        #endif
      }
      do {
        if let cached = await cache.read(cacheKey) {
          try pauseForNarration(token: token)
          try await output.enqueue(cached, onStart: started)
        } else {
          let recording = SpeechRecording()
          let receive: @Sendable (Data) async throws -> Void = { chunk in
            try await recording.append(chunk)
            try await self.pauseForNarration(token: token)
            try await output.enqueue(chunk, onStart: started)
          }
          #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-stream-meaning") {
              // Deterministic PCM transport fixture; exercises the real player and disk cache.
              for _ in 0..<10 {
                try await receive(Data(repeating: 0, count: 48_000))
                try await Task.sleep(for: .milliseconds(100))
              }
            } else {
              try await GeminiService().streamSpeech(
                key: apiKey, text: text, voice: voice, style: style, receive: receive)
            }
          #else
            try await GeminiService().streamSpeech(
              key: apiKey, text: text, voice: voice, style: style, receive: receive)
          #endif
          try Task.checkCancellation()
          await cache.store(await recording.contents(), key: cacheKey)
        }
        try await output.finish()
      } catch {
        output.stop()
        if generation == token { streamingAudio = nil }
        throw error
      }
      guard generation == token else { return }
      streamingAudio = nil
      narrationDiagnostic = "Gemini TTS: lettura completata"
      reading = false
      busyMeaning = false
      #if DEBUG
        narrationFinishes += 1
      #endif
      resumeMusic()
      return
    } else {
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      activeUtterance = utterance
      try pauseForNarration(token: token)
      synthesizer.speak(utterance)
      voiceStartTimeout?.cancel()
      voiceStartTimeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(8)) } catch { return }
        guard let self, self.generation == token, self.activeUtterance === utterance,
          !self.reading
        else { return }
        self.stopMeaning(resume: true)
        self.meaningError =
          "La voce di sistema non è partita. Riprova o scegli Gemini TTS nelle impostazioni."
        self.narrationDiagnostic = "Voce di sistema: nessun avvio entro 8 secondi"
      }
    }
  }

  private func pauseForNarration(token: UUID) throws {
    try Task.checkCancellation()
    guard generation == token else { throw CancellationError() }
    player.pause()
  }

  func stopMeaning(resume: Bool = true, reason: String? = nil) {
    if let reason, busyMeaning || reading { narrationDiagnostic = reason }

    generation = UUID()
    explanationTask?.cancel()
    explanationTask = nil
    voiceStartTimeout?.cancel()
    voiceStartTimeout = nil
    endMeaningPreparation()
    streamingAudio?.stop()
    streamingAudio = nil
    activeUtterance = nil
    synthesizer.stopSpeaking(at: .immediate)
    reading = false
    busyMeaning = false
    if resume { resumeMusic() } else { resumeSongID = nil }
  }

  private func resumeMusic() {
    if let id = resumeSongID, current?.id == id { player.play() }
    resumeSongID = nil
  }

  private func beginMeaningPreparation(token: UUID) {
    endMeaningPreparation()
    preparationTimeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(45)) } catch { return }
      guard let self, self.generation == token, self.busyMeaning else { return }
      self.stopMeaning(resume: true)
      self.meaningError =
        "Preparazione della lettura troppo lunga. Controlla la connessione e riprova."
      self.narrationDiagnostic = "Preparazione: timeout prima dell'audio"
    }
    #if os(iOS)
      meaningBackgroundTask = UIApplication.shared.beginBackgroundTask(
        withName: "Prepare narration"
      ) {
        [weak self] in
        Task { @MainActor [weak self] in
          guard let self, self.generation == token, self.meaningBackgroundTask != .invalid else {
            return
          }
          self.stopMeaning(resume: true)
          self.meaningError = "Preparazione interrotta dal sistema. Riprova."
          self.narrationDiagnostic = "Preparazione: tempo in background esaurito"
        }
      }
    #endif
  }

  private func endMeaningPreparation() {
    preparationTimeout?.cancel()
    preparationTimeout = nil
    #if os(iOS)
      guard meaningBackgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(meaningBackgroundTask)
      meaningBackgroundTask = .invalid
    #endif
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
  ) {
    let startedID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      guard let self, self.activeUtterance.map(ObjectIdentifier.init) == startedID else { return }
      self.voiceStartTimeout?.cancel()
      self.voiceStartTimeout = nil
      self.reading = true
      self.busyMeaning = false
      self.narrationDiagnostic = "Voce di sistema: lettura avviata"
      self.endMeaningPreparation()
      #if DEBUG
        self.narrationStarts += 1
      #endif
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    let finishedID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      guard let self, self.reading, self.activeUtterance.map(ObjectIdentifier.init) == finishedID
      else { return }
      self.activeUtterance = nil
      self.narrationDiagnostic = "Voce di sistema: lettura completata"
      self.reading = false
      #if DEBUG
        self.narrationFinishes += 1
      #endif
      self.resumeMusic()
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    let cancelledID = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in
      guard let self, self.activeUtterance.map(ObjectIdentifier.init) == cancelledID else { return }
      self.activeUtterance = nil
      self.reading = false
      self.busyMeaning = false
      self.endMeaningPreparation()
      self.meaningError = "Lettura interrotta dal sistema. Riprova."
      self.narrationDiagnostic = "Voce di sistema: lettura annullata dal sistema"
      self.resumeMusic()
    }
  }

}

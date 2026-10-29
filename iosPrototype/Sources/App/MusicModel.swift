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
    var localFileProvider: @MainActor (String) -> URL? = { _ in nil }
    var wantsPlayback = false
    private(set) var controlRevision = UUID()
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
    func prepareTransition(videoID: String) {}
    func cancelTransition() {}
    func transition(to videoID: String, seconds: Double, dj: Bool) -> Bool { false }
    var crossfadeStarts = 0
    var beforePlay: (() -> Bool)?
    func restore(videoID: String, position: Double, duration: Double) {
      clear()
      videoId = videoID
      elapsed = position
      durationSeconds = duration
    }
    func clear() {
      pause()
      webView?.stopLoading()
      videoId = ""
      loadID = UUID()
      elapsed = 0
      durationSeconds = 0
      isLoading = false
      playbackError = nil
    }
    func play() {
      guard beforePlay?() ?? true else { return }
      controlRevision = UUID()
      wantsPlayback = true
      webView?.evaluateJavaScript("player.playVideo()", completionHandler: nil)
    }
    func pause() {
      controlRevision = UUID()
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

typealias Song = PlaybackTrack

struct QueueRow: Identifiable {
  let id: UUID
  let index: Int
  let song: Song
}

@MainActor
final class MusicModel: NSObject, ObservableObject {
  let player = PlaybackPlayer()
  let downloads = MusicDownloads()
  let listening = ListeningHistory(
    url: LocalFiles.directory(
      ProcessInfo.processInfo.arguments.contains("--test-local-playback")
        ? "QAListening" : "Listening"
    ).appendingPathComponent("history.json"))
  @Published var lyricsProvider =
    LyricsProviderChoice(rawValue: UserDefaults.standard.string(forKey: "lyricsProvider") ?? "")
    ?? .automatic
  {
    didSet { UserDefaults.standard.set(lyricsProvider.rawValue, forKey: "lyricsProvider") }
  }
  @Published var spotifyLyricsToken = SecureStore.read("spotify-lyrics-token")
  @Published var spotifyClientToken = SecureStore.read("spotify-client-token")

  private var downloadSubscription: AnyCancellable?
  private var featureSubscriptions = Set<AnyCancellable>()
  private let sessionStore = PlaybackSessionStore(
    url: LocalFiles.directory(
      ProcessInfo.processInfo.arguments.contains("--test-session") ? "QASession" : "Playback"
    ).appendingPathComponent("session.json"))
  private var sessionEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains("--test-session")
      || !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--test-") }
  }
  private var sleepTask: Task<Void, Never>?
  @Published var sleepTimer: SleepTimer?
  @Published var timeline = LyricsTimeline(lrc: "")
  @Published var timelineSource: ResolvedLyrics.Source?
  @Published var lyricsDelay = 0.0
  private var timedTask: Task<Void, Never>?
  private var lastSessionSave = Date.distantPast
  func saveSession() {
    guard sessionEnabled else { return }
    listening.save()
    do {
      try sessionStore.save(
        PlaybackSnapshot(
          tracks: queue, occurrenceIDs: queueIDs, sequence: sequence,
          repeatMode: repeatMode, position: player.elapsed, duration: player.durationSeconds,
          timer: sleepTimer))
    } catch { settingsError = "Impossibile salvare la sessione di ascolto." }
  }
  private func updateCrossfade() {
    let seconds = AudioPreferences.shared.crossfade
    guard seconds > 0, player.playing, !reading, !busyMeaning, sleepTimer != .endOfTrack,
      player.durationSeconds > seconds * 2,
      let index = sequence.next(repeatMode: repeatMode, automatic: true), index != sequence.current,
      queue.indices.contains(index)
    else { return }
    let remaining = player.durationSeconds - player.elapsed
    if remaining > 0 && remaining <= seconds + 15 {
      player.prepareTransition(videoID: queue[index].id)
    }
    if remaining > 0 && remaining <= seconds,
      player.transition(to: queue[index].id, seconds: remaining, dj: AudioPreferences.shared.djMode)
    {
      sequence.select(index)
      play(queue[index], reusePlayback: true)
    }
  }

  func setSleepTimer(_ timer: SleepTimer?) {
    sleepTask?.cancel()
    sleepTimer = timer
    if case .deadline(let date) = timer {
      sleepTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
        guard !Task.isCancelled else { return }
        _ = self?.checkSleepTimer()
      }
    }
    saveSession()
  }
  @discardableResult func checkSleepTimer(trackEnded: Bool = false) -> Bool {
    guard let sleepTimer, sleepTimer.expired(trackEnded: trackEnded) else { return false }
    self.sleepTimer = nil
    sleepTask?.cancel()
    invalidateRadioRequest()
    stopMeaning(resume: false)
    player.pause()
    saveSession()
    return true
  }
  func loadTimedLyrics() {
    guard let song = current, timeline.lines.isEmpty, manualLyrics.isEmpty else { return }
    timedTask?.cancel()
    timedTask = Task {
      do {
        let result = try await lyricsResolver.synchronized(
          LyricsQuery(
            videoID: song.id, title: song.title,
            artist: song.artist, durationSeconds: song.durationSeconds))
        guard !Task.isCancelled, current?.id == song.id else { return }
        if let lrc = result?.syncedText {
          timeline = LyricsTimeline(lrc: lrc)
          timelineSource = result?.source
        }
      } catch {
        // Static lyrics remain available if synchronized lookup fails.
      }
    }
  }
  var savedManualLyrics: String {
    guard let id = current?.id else { return "" }
    return LocalFiles.read(
      String.self,
      from: LocalFiles.directory("ManualLyrics").appendingPathComponent(
        LocalFiles.key(id) + ".json")) ?? ""
  }
  func useProviderLyrics() {
    if let id = current?.id {
      UserDefaults.standard.set(false, forKey: "useManualLyrics." + LocalFiles.key(id))
    }
    manualLyrics = ""
    timeline = LyricsTimeline(lrc: "")
    timelineSource = nil
    loadLyrics(force: true)
  }
  func importLyrics(_ text: String) {
    manualLyrics = text
    if let id = current?.id {
      UserDefaults.standard.set(!text.isEmpty, forKey: "useManualLyrics." + LocalFiles.key(id))
      try? LocalFiles.write(
        text,
        to: LocalFiles.directory("ManualLyrics").appendingPathComponent(
          LocalFiles.key(id) + ".json"))
    }
    timeline = LyricsTimeline(lrc: text)
    timelineSource = nil
    lyricsDelay = 0
  }

  private let lyricsResolver = LyricsResolver()
  private var systemSpeech: SystemSpeechStream?
  @Published private(set) var migratingFavorites = false
  private var streamingAudio: PCMStreamPlayer?
  private var explanationTask: Task<Void, Never>?
  private var preparationTimeout: Task<Void, Never>?
  var meaningRequestID: UUID { generation }
  @Published var narrationDiagnostic =
    UserDefaults.standard.string(forKey: "lastNarrationDiagnostic") ?? "Nessuna richiesta"
  {
    didSet { UserDefaults.standard.set(narrationDiagnostic, forKey: "lastNarrationDiagnostic") }
  }
  private var generation = UUID()
  private var resumeSongID: String?
  #if os(iOS)
    private var meaningBackgroundTask = UIBackgroundTaskIdentifier.invalid
    private var radioBackgroundTask = UIBackgroundTaskIdentifier.invalid
  #endif
  let searchResults: MusicSearchModel = {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-full-search") {
        return MusicSearchModel(
          history: [], saveHistory: { _ in },
          fetch: { _, query, filter, token in
            try await Task.sleep(for: .milliseconds(120))
            if filter == .podcasts
              && ProcessInfo.processInfo.arguments.contains("--test-search-failure")
            {
              throw LibraryError.http(503)
            }
            let numbers = token == nil ? Array(1...7) : [7, 8]
            let items = numbers.map { n in
              DiscoveryItem(
                kind: filter.kind,
                mediaId: filter.kind == .album
                  ? "MPREsearch-\(n)"
                  : filter.kind == .artist
                    ? "UCsearch-\(n)"
                    : filter.kind == .playlist
                      ? "VLsearch-\(filter.identifier)-\(n)" : "search-\(filter.identifier)-\(n)",
                title: "\(query) · \(filter.rawValue) \(n)", subtitle: "Artista di prova",
                artwork: nil)
            }
            return MusicSearchPage(items: items, continuation: token == nil ? "search-next" : nil)
          })
      }
    #endif
    return MusicSearchModel()
  }()
  @Published var carPlayVoiceQuery: CarPlayVoiceQuery?
  @Published private(set) var queue: [Song] = []
  private var queueIDs: [UUID] = []
  @Published private(set) var sequence = PlaybackSequence()
  @Published private(set) var shuffleEnabled = false
  @Published var repeatMode = PlaybackRepeatMode.off
  @Published var autoplayEnabled =
    UserDefaults.standard.object(forKey: "autoplayEnabled") as? Bool ?? true
  {
    didSet {
      UserDefaults.standard.set(autoplayEnabled, forKey: "autoplayEnabled")
      invalidateRadioRequest()
      if autoplayEnabled { prepareRadio() }
    }
  }
  @Published private(set) var loadingRadio = false
  @Published var radioError: String?
  @Published var radioActionError: String?
  @Published private(set) var radioTitle: String?
  private var radioRetryAction: (song: Song?, artistID: String?, title: String?)?
  private var radioAccount: YouTubeSession?
  private var radioTask: Task<Void, Never>?
  private var radioRevision = UUID()
  private var radioCursor: RadioCursor?
  private var radioBuffer: [DiscoveryItem] = []
  private var aiRadioSeed: Song?
  private var artistRadio = false
  private var radioHistory = UserDefaults.standard.data(forKey: "geminiRadioHistory")
    .flatMap { try? JSONDecoder().decode(SongRadioHistory.self, from: $0) } ?? SongRadioHistory()
  private var waitingForRadio: (load: UUID, control: UUID)?

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
  @Published var externalRoute: AppRoute?
  @Published var sharedRequest: SharedMusicRequest?
  func receiveSharedMusic() {
    guard sharedRequest == nil, externalRoute == nil, !showMeaning, !reading, !busyMeaning,
      let request = SharedMusicInbox.shared()?.pending().last
    else { return }
    externalRoute = nil
    showPlayer = false
    sharedRequest = request
  }
  let releases = MusicModel.makeArtistReleases()
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
    @Published var systemNowPlayingTimeline = ""
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
  @Published private(set) var favoriteAlbums: [LibraryAlbum] = []
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
    player.localFileProvider = { [weak downloads] id in downloads?.library.url(for: id) }
    downloadSubscription = downloads.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
    player.onEnded = { [weak self] in self?.nextSong(automatic: true) }
    player.beforePlay = { [weak self] in !(self?.checkSleepTimer() ?? false) }
    if sessionEnabled, let saved = sessionStore.load() {
      queue = saved.tracks
      queueIDs = saved.occurrenceIDs
      sequence = saved.sequence
      shuffleEnabled = sequence.shuffled
      repeatMode = saved.repeatMode
      current = sequence.current.flatMap { queue.indices.contains($0) ? queue[$0] : nil }
      if let current {
        player.restore(videoID: current.id, position: saved.position, duration: saved.duration)
      }
      if let timer = saved.timer, !timer.expired() { setSleepTimer(timer) }
    }
    player.$elapsed.sink { [weak self] seconds in
      guard let self else { return }
      if Date().timeIntervalSince(self.lastSessionSave) >= 10 {
        self.lastSessionSave = Date()
        self.saveSession()
      }
      _ = self.checkSleepTimer()
      if self.sessionEnabled {
        self.listening.sample(
          track: self.current, token: self.player.loadID, position: seconds,
          duration: self.player.durationSeconds, playing: self.player.playing && !self.reading)
      }
      self.updateCrossfade()
    }.store(in: &featureSubscriptions)
    player.$playing.dropFirst().sink { [weak self] playing in
      if !playing { self?.saveSession() }
    }.store(in: &featureSubscriptions)
    objectWillChange.debounce(for: .milliseconds(400), scheduler: RunLoop.main).sink {
      [weak self] _ in
      self?.saveSession()
    }.store(in: &featureSubscriptions)
    if let data = UserDefaults.standard.data(forKey: "favorites"),
      let stored = try? JSONDecoder().decode([Song].self, from: data)
    {
      favorites = stored
    }
    if let data = UserDefaults.standard.data(forKey: "favoriteAlbums"),
      let stored = try? JSONDecoder().decode([LibraryAlbum].self, from: data)
    {
      favoriteAlbums = stored
    }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-favorites-migration") {
        UserDefaults.standard.removeObject(forKey: "favoriteMigrationAccount")
        favorites = [Song(id: "legacy-song", title: "Vecchio preferito", artist: "Prova", artwork: nil)]
        favoriteAlbums = [LibraryAlbum(id: "MPRElegacy", title: "Vecchio album", artist: "Prova", artwork: nil)]
      }
      if ProcessInfo.processInfo.arguments.contains("--test-local-playback") {
        autoplayEnabled = false
        Task { await installLocalPlaybackFixture() }
      }
      if ProcessInfo.processInfo.arguments.contains("--test-full-search") {
        autoplayEnabled = false
      }
      if ProcessInfo.processInfo.arguments.contains("--test-playback-order") {
        queue = (1...3).map {
          Song(id: "order-\($0)", title: "Brano \($0)", artist: "Prova ordine", artwork: nil)
        }
        queueIDs = queue.map { _ in UUID() }
        sequence.reset(count: queue.count, selected: 0, shuffle: false)
        current = queue.first
        showPlayer = true
        autoplayEnabled = ProcessInfo.processInfo.arguments.contains("--test-radio")
      }
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

  #if DEBUG
    private func installLocalPlaybackFixture() async {
      do {
        let seconds =
          ProcessInfo.processInfo.arguments.contains("--test-long-local")
          ? 80.0 : (ProcessInfo.processInfo.arguments.contains("--test-crossfade") ? 10.0 : 30.0)
        let padded = ProcessInfo.processInfo.arguments.contains("--test-padded-audio-end")
        let tracks = (1...3).map {
          Song(
            id: "local-\($0)-\(padded && $0 == 1 ? "padded" : String(Int(seconds)))", title: "Brano locale \($0)", artist: "Prova offline",
            artwork: nil, durationSeconds: padded && $0 == 1 ? 126 : seconds,
            albumBrowseID: ProcessInfo.processInfo.arguments.contains("--test-album-player")
              ? "MPREfixture" : nil,
            albumTitle: "Album locale",
            artistBrowseID: ProcessInfo.processInfo.arguments.contains("--test-album-player")
              ? "UCfixture" : nil,
            artistReferences: ProcessInfo.processInfo.arguments.contains(
              "--test-album-multiple-artists")
              ? [
                TrackArtist(id: "UCfixture", name: "Prova offline"),
                TrackArtist(id: "UCguest", name: "Artista ospite"),
              ] : nil)
        }
        for track in tracks where downloads.library.url(for: track.id) == nil {
          let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".m4a")
          try LocalPlaybackFixture.audio(file, seconds: track.durationSeconds ?? seconds,
            audibleSeconds: padded && track.id.hasSuffix("-padded") ? 6 : nil)
          downloads.library.begin(track)
          try await downloads.library.finish(
            track.id, temporary: file, status: 200, contentRange: nil)
        }
        if ProcessInfo.processInfo.arguments.contains("--test-restore-session"), current != nil {
          showPlayer = true
        } else {
          AudioPreferences.shared.crossfade =
            ProcessInfo.processInfo.arguments.contains("--test-crossfade") ? 3 : 0
          var settings = AudioEffects()
          settings.enabled = true
          settings.gains[5] = 3
          AudioPreferences.shared.effects = settings
          play(tracks[0], queue: tracks)
          if ProcessInfo.processInfo.arguments.contains("--test-crossfade") { player.pause() }
        }
        timeline = LyricsTimeline(
          lrc:
            "[00:00.000]<00:00.000>Prima <00:01.000>riga\n[00:03.000]Seconda riga\n[00:06.000]Terza riga"
        )
        lyrics = "Prima riga\nSeconda riga\nTerza riga"
        if ProcessInfo.processInfo.arguments.contains("--test-karaoke") {
          let lrc = (0..<20).map { index in
            let second = index * 2
            return String(
              format: "[00:%02d]<00:%02d>Parole <00:%02d>sincronizzate %d", second,
              second, second + 1, index + 1)
          }.joined(separator: "\n")
          timeline = LyricsTimeline(lrc: lrc)
          lyrics = timeline.lines.map(\.text).joined(separator: "\n")
        }
      } catch { settingsError = "Fixture locale: " + error.localizedDescription }
    }
  #endif

  func download(_ song: Song) { downloads.start(song, account: radioAccount) }
  func removeDownload(_ id: String) {
    if current?.id == id, downloads.library.url(for: id) != nil {
      player.restore(videoID: id, position: player.elapsed, duration: player.durationSeconds)
    }
    downloads.remove(id)
  }

  func saveSettings() {
    do {
      try SecureStore.save(apiKey, as: "gemini")
      try SecureStore.save(spotifyLyricsToken, as: "spotify-lyrics-token")
      try SecureStore.save(spotifyClientToken, as: "spotify-client-token")
      UserDefaults.standard.set(textModel, forKey: "textModel")
      UserDefaults.standard.set(useGeminiVoice, forKey: "geminiVoice")
      UserDefaults.standard.set(style.rawValue, forKey: "voiceStyle")
      UserDefaults.standard.set(voice, forKey: "voice")
      settingsError = nil
    } catch { settingsError = "Impossibile salvare la chiave nel Portachiavi." }
  }

  var queueIndex: Int? { sequence.current }
  var hasPrevious: Bool { sequence.previous(repeatMode: repeatMode) != nil }
  var hasNext: Bool {
    sequence.next(repeatMode: repeatMode) != nil || (autoplayEnabled && current != nil)
  }
  var orderedQueueIndices: [Int] { sequence.order }
  var queueRows: [QueueRow] {
    sequence.order.compactMap { index in
      guard queue.indices.contains(index), queueIDs.indices.contains(index) else { return nil }
      return QueueRow(id: queueIDs[index], index: index, song: queue[index])
    }
  }

  func enqueue(_ song: Song, playNext: Bool = false) {
    player.cancelTransition()
    guard current != nil, !queue.isEmpty else {
      play(song, queue: [song])
      return
    }
    queue.append(song)
    queueIDs.append(UUID())
    sequence.append(playNext: playNext)
    if waitingForRadio != nil {
      waitingForRadio = nil
      nextSong()
    }
  }

  func moveQueuedSongs(from offsets: IndexSet, to destination: Int) {
    player.cancelTransition()
    sequence.move(from: offsets, to: destination)
  }

  func playQueuedSongNext(_ index: Int) {
    player.cancelTransition()
    sequence.playNext(index)
  }

  func removeQueuedSongs(at offsets: IndexSet) {
    player.cancelTransition()
    let indices = Set(
      offsets.compactMap { offset in
        sequence.order.indices.contains(offset) ? sequence.order[offset] : nil
      })
    let removedCurrent = sequence.current.map { indices.contains($0) } ?? false
    if removedCurrent { invalidateRadioRequest() }
    let wasPlaying = player.wantsPlayback
    let removed = sequence.remove(indices)
    guard !removed.isEmpty else { return }
    queue = queue.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
    queueIDs = queueIDs.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
    guard removedCurrent else { return }
    if let index = sequence.current {
      playQueuePosition(index)
      if !wasPlaying { player.pause() }
    } else {
      stopMeaning(resume: false)
      player.clear()
      lyricsTask?.cancel()
      lyricsGeneration = UUID()
      loadingLyrics = false
      lyrics = ""
      lyricsSource = nil
      lyricsSourceURL = nil
      lyricsError = nil
      meaning = ""
      meaningError = nil
      manualLyrics = ""
      showMeaning = false
      resetRadio()
      current = nil
      showPlayer = false
    }
  }
  func setShuffle(_ value: Bool) {
    player.cancelTransition()
    shuffleEnabled = value
    sequence.setShuffled(value)
  }
  func playQueuePosition(_ index: Int) {
    guard queue.indices.contains(index) else { return }
    sequence.select(index)
    play(queue[index])
  }
  func playQueueOccurrence(_ id: UUID) {
    if let index = queueIDs.firstIndex(of: id) { playQueuePosition(index) }
  }
  func playQueueOccurrenceNext(_ id: UUID) {
    if let index = queueIDs.firstIndex(of: id) { sequence.playNext(index) }
  }
  func removeQueueOccurrence(_ id: UUID) {
    guard let index = queueIDs.firstIndex(of: id), let offset = sequence.order.firstIndex(of: index)
    else { return }
    removeQueuedSongs(at: IndexSet(integer: offset))
  }
  func previousSong() {
    if player.elapsed > 3 {
      player.seek(to: .zero)
    } else if let index = sequence.previous(repeatMode: repeatMode) {
      playQueuePosition(index)
    }
  }
  func nextSong(automatic: Bool = false) {
    if automatic { listening.endSession() }
    if automatic && checkSleepTimer(trackEnded: true) { return }
    if automatic && (busyMeaning || reading) { return }
    if let index = sequence.next(repeatMode: repeatMode, automatic: automatic) {
      if automatic && index == sequence.current {
        player.seek(to: .zero)
        player.play()
      } else {
        playQueuePosition(index)
      }
    } else if autoplayEnabled, current != nil {
      waitingForRadio = (player.loadID, player.controlRevision)
      if !advanceRadio() { prepareRadio() }
    }
  }

  func configureRadio(session: YouTubeSession?) {
    player.cancelTransition()
    guard radioAccount != session else { return }
    radioAccount = session
    resetRadio()
    prepareRadio()
  }

  private func invalidateRadioRequest() {
    radioTask?.cancel()
    radioTask = nil
    radioRevision = UUID()
    waitingForRadio = nil
    loadingRadio = false
    endRadioBackgroundTask()
  }
  private func resetRadio() {
    invalidateRadioRequest()
    radioCursor = nil
    aiRadioSeed = nil
    artistRadio = false
    radioBuffer = []
    radioTitle = nil
    radioError = nil
    radioActionError = nil
    radioRetryAction = nil
  }

  /// Radio is resolved before replacing the user's queue; a failed request leaves it untouched.
  func startRadio(song: Song? = nil, artistID: String? = nil, title: String? = nil) {
    guard song != nil || artistID != nil else { return }
    invalidateRadioRequest()
    radioRetryAction = (song, artistID, title)
    radioActionError = nil
    let token = radioRevision
    let load = player.loadID
    let control = player.controlRevision
    let service = MusicRadio(session: radioAccount)
    loadingRadio = true
    radioError = nil
    beginRadioBackgroundTask()
    radioTask = Task {
      do {
        let endpoint: RadioEndpoint
        if let artistID {
          endpoint = try await service.artistEndpoint(id: artistID)
        } else {
          endpoint = .song(song!.id)
        }
        let page: RadioPage
        if let song, artistID == nil {
          page = try await fetchGeminiRadio(seed: song)
        } else {
          page = try await fetchRadio(service: service, endpoint: endpoint, continuation: nil)
        }
        try Task.checkCancellation()
        guard radioRevision == token, player.loadID == load, player.controlRevision == control
        else {
          if radioRevision == token { invalidateRadioRequest() }
          return
        }
        var cursor = RadioCursor(endpoint: endpoint)
        let items = try cursor.accept(page, excluding: [])
        guard !items.isEmpty else { throw RadioError.unavailable }
        let songs = artistID == nil
          ? Array(((song.map { [$0] } ?? []) + items.map(Song.init)).prefix(50))
          : items.map(Song.init)
        let selected = song.flatMap { seed in songs.firstIndex { $0.id == seed.id } } ?? 0
        play(songs[selected], queue: songs, selectedIndex: selected, preserveRadio: true)
        radioCursor = cursor
        artistRadio = artistID != nil
        aiRadioSeed = artistID == nil ? song : nil
        if aiRadioSeed != nil { rememberRadio(items) }
        radioBuffer = []
        radioTitle = "Radio · " + (title ?? song?.title ?? "Artista")
        radioRetryAction = nil
        loadingRadio = false
        radioTask = nil
        endRadioBackgroundTask()
        prepareRadio()
      } catch {
        guard radioRevision == token, !Task.isCancelled else { return }
        loadingRadio = false
        radioTask = nil
        endRadioBackgroundTask()
        radioError = error.localizedDescription
        radioActionError = error.localizedDescription
      }
    }
  }

  func retryRadio() {
    if let request = radioRetryAction {
      startRadio(song: request.song, artistID: request.artistID, title: request.title)
    } else {
      radioError = nil
      prepareRadio()
    }
  }

  private func beginRadioBackgroundTask() {
    #if os(iOS)
      endRadioBackgroundTask()
      radioBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare radio") {
        [weak self] in
        Task { @MainActor [weak self] in
          self?.invalidateRadioRequest()
          self?.radioError = "Preparazione radio interrotta. Riprova."
        }
      }
    #endif
  }
  private func endRadioBackgroundTask() {
    #if os(iOS)
      if radioBackgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(radioBackgroundTask)
        radioBackgroundTask = .invalid
      }
    #endif
  }

  private func fetchRadio(service: MusicRadio, endpoint: RadioEndpoint, continuation: String?)
    async throws -> RadioPage
  {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-radio") {
        try await Task.sleep(
          for: .milliseconds(
            ProcessInfo.processInfo.arguments.contains("--test-radio-slow") ? 6000 : 900))
        if ProcessInfo.processInfo.arguments.contains("--test-radio-failure") {
          throw RadioError.unavailable
        }
        let contents = (1...3).map { n in
          "{\"playlistPanelVideoRenderer\":{\"videoId\":\"radio-\(n)\",\"title\":{\"simpleText\":\"Suggerimento \(n)\"},\"longBylineText\":{\"simpleText\":\"Artista radio\"}}}"
        }.joined(separator: ",")
        return try RadioPage.decode(
          Data(
            "{\"continuationContents\":{\"playlistPanelContinuation\":{\"contents\":[\(contents)]}}}"
              .utf8), endpoint: endpoint)
      }
    #endif
    return try await service.page(endpoint: endpoint, continuation: continuation)
  }

  private func fetchGeminiRadio(seed: Song) async throws -> RadioPage {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-radio") {
        return try await fetchRadio(service: MusicRadio(session: radioAccount),
          endpoint: .song(seed.id), continuation: nil)
      }
    #endif
    let items = try await GeminiSongRadio().songs(seed: seed,
      excluding: radioHistory.tracks + queue, key: apiKey, model: textModel,
      session: radioAccount)
    return RadioPage(items: items, endpoint: .song(seed.id), continuation: nil, automix: nil)
  }
  private func rememberRadio(_ items: [DiscoveryItem]) {
    radioHistory.remember(items.map(Song.init))
    if let data = try? JSONEncoder().encode(radioHistory) {
      UserDefaults.standard.set(data, forKey: "geminiRadioHistory")
    }
  }

  /// Prefetch only at the tail. Suggestions stay buffered until the manual queue is consumed.
  private func prepareRadio() {
    guard autoplayEnabled, let current, sequence.next(repeatMode: .off) == nil,
      radioTask == nil, radioBuffer.isEmpty
    else { return }
    let token = radioRevision
    let service = MusicRadio(session: radioAccount)
    var cursor = radioCursor ?? RadioCursor(endpoint: .song(current.id))
    if cursor.exhausted { cursor = RadioCursor(endpoint: .song(current.id)) }
    let aiSeed = artistRadio ? nil : (aiRadioSeed ?? current)
    let excluded = Set(queue.map(\.id))
    loadingRadio = true
    radioError = nil
    beginRadioBackgroundTask()
    radioTask = Task {
      do {
        var items: [DiscoveryItem] = []
        // Skip repeated/removed/seed tracks without looping indefinitely on duplicate-only pages.
        for _ in 0..<4 {
          let page: RadioPage
          if let aiSeed { page = try await fetchGeminiRadio(seed: aiSeed) }
          else {
            page = try await fetchRadio(
              service: service, endpoint: cursor.endpoint, continuation: cursor.continuation)
          }
          try Task.checkCancellation()
          items = try cursor.accept(page, excluding: excluded)
          if !items.isEmpty || cursor.exhausted { break }
        }
        guard radioRevision == token else { return }
        guard !items.isEmpty else { throw RadioError.unavailable }
        radioCursor = cursor
        radioBuffer = items
        if aiSeed != nil { rememberRadio(items) }
        loadingRadio = false
        radioTask = nil
        endRadioBackgroundTask()
        _ = advanceRadio()
      } catch {
        guard radioRevision == token, !Task.isCancelled else { return }
        loadingRadio = false
        radioTask = nil
        endRadioBackgroundTask()
        waitingForRadio = nil
        radioError = error.localizedDescription
      }
    }
  }

  @discardableResult
  private func advanceRadio() -> Bool {
    guard let expected = waitingForRadio, !radioBuffer.isEmpty else { return false }
    guard autoplayEnabled, player.loadID == expected.load,
      player.controlRevision == expected.control,
      !reading, !busyMeaning
    else {
      waitingForRadio = nil
      return false
    }
    var seen = Set(queue.map(\.id))
    let songs = radioBuffer.filter { seen.insert($0.mediaId).inserted }.map(Song.init)
    radioBuffer = []
    guard !songs.isEmpty || sequence.next(repeatMode: .off) != nil else { return false }
    waitingForRadio = nil
    // A manual insertion made while waiting always takes precedence.
    for song in songs {
      queue.append(song)
      queueIDs.append(UUID())
      sequence.append()
    }
    guard let index = sequence.next(repeatMode: .off) else { return false }
    playQueuePosition(index)
    return true
  }

  func loadLyrics(force: Bool = false) {
    guard let song = current else { return }
    if !force && !manualLyrics.isEmpty { return }
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
      try await lyricsResolver.resolve(
        query, force: force, provider: lyricsProvider, providerToken: spotifyLyricsToken,
        clientToken: spotifyClientToken
      ) { [weak self] in
        await self?.lyricsFallbackStarted(token: token)
      }
    }
    lyricsTask = task
    Task {
      do {
        let result = try await task.value
        guard !task.isCancelled, lyricsGeneration == token, current?.id == song.id else { return }
        lyrics = result?.text ?? ""
        if let lrc = result?.syncedText {
          timeline = LyricsTimeline(lrc: lrc)
          timelineSource = result?.source
        }
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

  func play(
    _ song: Song, queue newQueue: [Song]? = nil, selectedIndex: Int? = nil,
    preserveRadio: Bool = false, reusePlayback: Bool = false
  ) {
    if !preserveRadio {
      if newQueue != nil || !queue.contains(where: { $0.id == song.id }) {
        resetRadio()
      } else {
        invalidateRadioRequest()
      }
    }
    if let newQueue {
      queue = newQueue
      queueIDs = queue.map { _ in UUID() }
      sequence.reset(
        count: queue.count, selected: selectedIndex ?? queue.firstIndex { $0.id == song.id } ?? 0,
        shuffle: shuffleEnabled)
    } else if !queue.contains(where: { $0.id == song.id }) {
      queue = [song]
      queueIDs = [UUID()]
      sequence.reset(count: 1, selected: 0, shuffle: shuffleEnabled)
    } else if let index = queue.firstIndex(where: { $0.id == song.id }),
      sequence.current.flatMap({ queue.indices.contains($0) ? queue[$0].id : nil }) != song.id
    {
      sequence.select(index)
    }
    timedTask?.cancel()
    timelineSource = nil
    timeline = LyricsTimeline(lrc: "")
    lyricsDelay = 0
    lyricsTask?.cancel()
    lyricsTask = nil
    lyricsGeneration = UUID()
    lyrics = ""
    lyricsSource = nil
    lyricsSourceURL = nil
    loadingLyrics = false
    lyricsError = nil
    stopMeaning(resume: false)
    listening.endSession()
    current = song
    manualLyrics =
      LocalFiles.read(
        String.self,
        from: LocalFiles.directory("ManualLyrics").appendingPathComponent(
          LocalFiles.key(song.id) + ".json")) ?? ""
    if UserDefaults.standard.object(forKey: "useManualLyrics." + LocalFiles.key(song.id)) as? Bool
      == false
    {
      manualLyrics = ""
    }
    if !manualLyrics.isEmpty { timeline = LyricsTimeline(lrc: manualLyrics) }
    meaning = ""
    showPlayer = true
    if !reusePlayback { player.load(videoId: song.id) }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-playback-order")
        || ProcessInfo.processInfo.arguments.contains("--test-full-search")
      {
        player.pause()
      } else if !ProcessInfo.processInfo.arguments.contains("--test-local-playback") {
        loadLyrics()
      }
    #else
      loadLyrics()  // Fetch alongside playback, before the user asks for the interpretation.
    #endif
    if !preserveRadio { prepareRadio() }
  }

  func minimizePlayer() {
    // Presentation changes must not stop the retained playback session.
    showPlayer = false
  }

  /// Old local selections are only a durable import queue, never a second favourite collection.
  func migrateFavorites(to library: LibraryModel, account: YouTubeSession) async {
    guard !migratingFavorites, library.session == account, !favorites.isEmpty || !favoriteAlbums.isEmpty else { return }
    migratingFavorites = true
    defer { migratingFavorites = false }
    let defaults = UserDefaults.standard
    let ownerKey = "favoriteMigrationAccount"
    if let owner = defaults.string(forKey: ownerKey), owner != account.identity {
      library.syncError = "I vecchi preferiti attendono la sincronizzazione con l’account YouTube Music usato per iniziare l’importazione."
      return
    }
    defaults.set(account.identity, forKey: ownerKey)
    await library.importLikes(favorites.map(\.discoveryItem)) { [weak self] item in
      guard let self else { return }
      self.favorites.removeAll { $0.id == item.mediaId }
      self.persistLegacyFavorites()
    }
    guard !Task.isCancelled, library.session == account, favorites.isEmpty else { return }
    for album in favoriteAlbums {
      do {
        let detail: AlbumDetail
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--test-favorites-migration") {
            detail = AlbumDetail(album: album, songs: (1...3).map {
              Song(id: "legacy-album-\($0)", title: "Traccia importata \($0)", artist: "Prova", artwork: nil)
            })
          } else { detail = try await AlbumDetail.load(album: album, session: account) }
        #else
          detail = try await AlbumDetail.load(album: album, session: account)
        #endif
        try Task.checkCancellation()
        guard library.session == account else { return }
        guard !detail.songs.isEmpty else { throw LibraryError.malformed }
        await library.importLikes(detail.songs.map(\.discoveryItem)) { _ in }
        guard !Task.isCancelled, library.session == account,
          detail.songs.allSatisfy({ library.isLiked($0.id) }) else { return }
        favoriteAlbums.removeAll { $0.id == album.id }
        persistLegacyFavorites()
      } catch is CancellationError { return } catch {
        library.syncError = "Importazione dei vecchi album preferiti non completata. Le selezioni sono conservate; riprova dalla Libreria."
        return
      }
    }
  }

  private func persistLegacyFavorites() {
    if let data = try? JSONEncoder().encode(favorites) {
      UserDefaults.standard.set(data, forKey: "favorites")
    }
    if let data = try? JSONEncoder().encode(favoriteAlbums) {
      UserDefaults.standard.set(data, forKey: "favoriteAlbums")
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
      let output = PCMStreamPlayer(gain: NarrationLevel.gain)
      streamingAudio = output
      let cache = SpeechAudioCache.shared
      let cacheKey = SpeechAudioCache.key(text: text, voice: voice, style: style)
      let started: @MainActor @Sendable () -> Void = { [weak self] in
        guard let self, self.generation == token else { return }
        self.narrationDiagnostic = "Gemini TTS: lettura avviata (+30%)"
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
      let output = PCMStreamPlayer(gain: NarrationLevel.gain)
      let speech = SystemSpeechStream()
      streamingAudio = output
      systemSpeech = speech
      defer { speech.stop(); output.stop() }
      for try await chunk in speech.audio(text) {
        try pauseForNarration(token: token)
        try await output.enqueue(chunk) { [weak self] in
          guard let self, self.generation == token else { return }
          self.reading = true
          self.busyMeaning = false
          self.endMeaningPreparation()
          self.narrationDiagnostic = "Voce di sistema: lettura avviata (+30%)"
          #if DEBUG
            self.narrationStarts += 1
          #endif
        }
      }
      try await output.finish()
      guard generation == token else { return }
      systemSpeech = nil
      streamingAudio = nil
      reading = false
      busyMeaning = false
      narrationDiagnostic = "Voce di sistema: lettura completata"
      #if DEBUG
        narrationFinishes += 1
      #endif
      resumeMusic()
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
    endMeaningPreparation()
    systemSpeech?.stop()
    systemSpeech = nil
    streamingAudio?.stop()
    streamingAudio = nil
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

}

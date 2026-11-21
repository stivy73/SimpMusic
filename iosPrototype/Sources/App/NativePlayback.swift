#if os(iOS)
  import AVFoundation
  import Combine
  import Foundation
  import UIKit

  /// Keep music and narration on the same media route, including USB/wireless CarPlay.
  enum AppleAudioSession {
    static func activate() throws {
      let session = AVAudioSession.sharedInstance()
      if session.category != .playback || session.mode != .default
        || session.routeSharingPolicy != .longFormAudio
      {
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
      }
      try session.setActive(true)
    }
  }

  /// Owned by MusicModel, independent of SwiftUI presentation and WebKit scheduling.
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
    @Published var castVolumeAtLimit = false
    @Published var castDiagnostic = "Chromecast non collegato"
    @Published var sourceDiagnostic =
      UserDefaults.standard.string(forKey: "lastAudioSourceDiagnostic") ?? "Flusso non verificato"
    { didSet { UserDefaults.standard.set(sourceDiagnostic, forKey: "lastAudioSourceDiagnostic") } }
    @Published var networkDiagnostic =
      UserDefaults.standard.string(forKey: "lastAudioNetworkDiagnostic")
      ?? "Nessun errore CDN registrato"
    {
      didSet { UserDefaults.standard.set(networkDiagnostic, forKey: "lastAudioNetworkDiagnostic") }
    }
    @Published private(set) var timingDiagnostic = "Durata non ancora verificata"
    @Published private(set) var audioResolutionReport =
      UserDefaults.standard.string(forKey: "lastAudioResolutionReport") ?? "Nessun report audio disponibile"
    {
      didSet { UserDefaults.standard.set(audioResolutionReport, forKey: "lastAudioResolutionReport") }
    }
    private var audioReportFinalized = false
    private var preparationBegan: TimeInterval?
    private func recordPreparation(_ stage: String) {
      guard let preparationBegan else { return }
      let ms = Int(max(0, ProcessInfo.processInfo.systemUptime - preparationBegan) * 1000)
      let lines = (audioResolutionReport + "\nPreparazione +\(ms)ms: " + stage)
        .components(separatedBy: .newlines)
      audioResolutionReport = lines.suffix(96).joined(separator: "\n")
    }
    #if DEBUG
      @Published var diagnostic = "idle"
    #endif
    @Published private(set) var crossfadeStarts = 0
    @Published private(set) var warmStarts = 0
    @Published private(set) var warmWaits = 0
    @Published private(set) var warmReadyID = ""
    @Published private(set) var warmStatus = "idle"
    private var activeRangeToken: UUID?
    private(set) var nativePlayer = AVPlayer()
    private let effectsTap = AudioEffectsTap()
    private var effectsSubscription: AnyCancellable?
    lazy var cast = CastPlayback(player: self)
    var castAccountOnly: Bool { requiresAccount }
    private struct PreparedDeck {
      let id: String
      let player: AVPlayer
      let loader: AudioRangeLoader?
      let tap: AudioEffectsTap
      let duration: Double
      let timingDiagnostic: String
      let sourceURL: URL?
      let source: YouTubeAudio.Source?
      let rangeToken: UUID?
      let context: AudioWarmupContext
      let accountOnly: Bool
      let preparedAt: Date
      let usedOriginalReader: Bool
      // nil while the muted player is seeking to the requested resume position.
      var startAt: Double?
    }
    private var prepared: PreparedDeck?
    private var preparingID: String?
    private var preparingContext: AudioWarmupContext?
    private var preparingAccountOnly = false
    private var preparingPosition = 0.0
    private var requiresAccount = false
    private var unavailableMessage: String {
      requiresAccount
        ? "Non riesco a riprodurre questo caricamento personale. Riprova; se persiste, copia la diagnostica audio dalle Impostazioni."
        : AudioPlaybackError.unavailable.localizedDescription
    }
    private var preparationRevision = UUID()
    private var selectedPreparation: UUID?
    private var changingDeck = false
    private var transitionRequest: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var outgoing: AVPlayer?
    private var outgoingLoader: AudioRangeLoader?
    private var outgoingTap: AudioEffectsTap?
    private var currentTap: AudioEffectsTap?
    func cancelTransition(discardPrepared: Bool = true) {
      if discardPrepared {
        preparationRevision = UUID()
        selectedPreparation = nil
        transitionRequest?.cancel()
        transitionRequest = nil
        preparingID = nil
        preparingContext = nil
        prepared?.player.currentItem?.cancelPendingSeeks()
        prepared?.player.cancelPendingPrerolls()
        prepared?.player.pause()
        prepared = nil
        warmReadyID = ""
      }
      fadeTask?.cancel()
      fadeTask = nil
      outgoing?.pause()
      outgoing = nil
      outgoingTap?.state.setDJ(nil, incoming: false)
      currentTap?.state.setDJ(nil, incoming: true)
      outgoingLoader = nil
      outgoingTap = nil
      nativePlayer.volume = Float(volume / 100)
    }
    func prepareTransition(videoID: String, accountOnly: Bool = false, startAt: Double = 0) {
      guard !cast.connected, !changingDeck, fadeTask == nil else { return }
      let context = warmupContext()
      if let prepared, prepared.id == videoID, prepared.accountOnly == accountOnly,
        prepared.startAt == startAt,
        AudioWarmupValidity.usable(preparedAt: prepared.preparedAt, sourceURL: prepared.sourceURL,
          context: prepared.context, current: context) { return }
      if preparingID == videoID, preparingContext == context, preparingAccountOnly == accountOnly,
        preparingPosition == startAt,
        transitionRequest != nil
      {
        return
      }
      cancelTransition()
      let revision = UUID()
      preparationRevision = revision
      preparingID = videoID
      preparingContext = context
      preparingAccountOnly = accountOnly
      preparingPosition = startAt
      warmStatus = "preparing " + videoID
      transitionRequest = Task {
        var retriedURL: URL?
        do {
          let local = localFileProvider(videoID)
          var source: YouTubeAudio.Source?
          if local == nil {
            source = try await YouTubeAudio().resolve(
              videoID: videoID, session: context.session,
              quality: context.quality, preferHLSForLongTracks: true, accountOnly: accountOnly,
              preloadFirstBlock: true)
          }
          #if DEBUG
            if let local, ProcessInfo.processInfo.arguments.contains("--test-warm-playlist-fallback") {
              source = .invalidPlaylistFixture(originalFile: local)
            }
          #endif
          let verifiedAt = Date()
          while true {
            try Task.checkCancellation()
            guard preparationRevision == revision, warmupContext() == context else { throw CancellationError() }
            let token = UUID()
            let loader = source.map { makeRangeLoader(source: $0, token: token) }
            let asset: AVURLAsset
            if let loader {
              try await loader.prepare()
              asset = loader.asset()
            } else if let local {
              asset = AVURLAsset(url: local)
            } else {
              throw AudioPlaybackError.unavailable
            }
            let timing = try await AudioPlaybackTiming.prepare(asset, source: source?.duration ?? 0,
              isLive: source?.isLive == true)
            let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [])
            if timing.duration > 0 {
              item.forwardPlaybackEndTime = CMTime(seconds: timing.duration, preferredTimescale: 600)
            }
            item.preferredForwardBufferDuration = 5
            let tap = AudioEffectsTap()
            tap.configure(AudioPreferences.shared.effects)
            try Task.checkCancellation()
            guard preparationRevision == revision, warmupContext() == context else { throw CancellationError() }
            let player = makeTransitionPlayer(item: item)
            player.volume = 0
            let deck = PreparedDeck(
              id: videoID, player: player, loader: loader, tap: tap, duration: timing.duration,
              timingDiagnostic: timing.diagnostic, sourceURL: source?.url, source: source, rangeToken: loader == nil ? nil : token,
              context: context, accountOnly: accountOnly, preparedAt: verifiedAt, usedOriginalReader: retriedURL != nil,
              startAt: startAt == 0 ? 0 : nil)
            prepared = deck
            warmStatus = "item " + videoID
            do {
              try await finishWarmup(deck, item: item, startAt: startAt, revision: revision)
              return
            } catch {
              try Task.checkCancellation()
              guard preparationRevision == revision, let original = loader?.originalSourceForRetry,
                AudioWarmupValidity.usable(preparedAt: verifiedAt, sourceURL: original.url,
                  context: context, current: warmupContext())
              else { throw error }
              // Keep the same validated source and waiting Play request. Its original
              // reader carries no replacement playlist, so this fallback runs once.
              player.replaceCurrentItem(with: nil)
              prepared = nil
              source = original
              retriedURL = original.url
            }
          }
        } catch {
          guard preparationRevision == revision else { return }
          if let retriedURL, selectedPreparation == revision, warmupContext() == context {
            rejectedSources.insert(retriedURL)
          }
          warmStatus = "failed " + videoID + " code " + String((error as NSError).code)
          cancelTransition()
        }
      }
    }

    private func finishWarmup(_ warmDeck: PreparedDeck, item: AVPlayerItem, startAt: Double,
      revision: UUID) async throws {
      let deck = warmDeck.player
      let waitingSince = ContinuousClock.now
      while item.status == .unknown || deck.status == .unknown {
        if item.status == .failed || deck.status == .failed { break }
        // A long item can take more than eight seconds to open after its
        // source is ready. A selected deck would otherwise do that work twice.
        let limit: Duration
        if warmDeck.loader?.originalSourceForRetry != nil { limit = .seconds(12) }
        else if warmDeck.duration >= 600 || selectedPreparation == revision { limit = .seconds(30) }
        else { limit = .seconds(8) }
        if ContinuousClock.now >= waitingSince.advanced(by: limit) { break }
        try await Task.sleep(for: .milliseconds(40))
      }
      guard item.status == .readyToPlay, deck.status == .readyToPlay else {
        throw AudioPlaybackError.unavailable
      }
      let seekNeeded = startAt > 0 && warmDeck.source?.isLive != true
      let timeout = Task { @MainActor in
        try? await Task.sleep(for: .seconds(seekNeeded ? 10 : 5))
        guard !Task.isCancelled, preparationRevision == revision else { return }
        item.cancelPendingSeeks()
        deck.cancelPendingPrerolls()
      }
      defer { timeout.cancel() }
      if seekNeeded {
        let finished: Bool = await deck.seek(to: CMTime(seconds: startAt, preferredTimescale: 600),
          toleranceBefore: .zero, toleranceAfter: .zero)
        try Task.checkCancellation()
        guard finished, preparationRevision == revision, warmupContext() == warmDeck.context
        else { throw AudioPlaybackError.unavailable }
      }
      try Task.checkCancellation()
      guard preparationRevision == revision, warmupContext() == warmDeck.context else { throw CancellationError() }
      prepared?.startAt = startAt
      // A foreground load is already awaiting this task. It can use the
      // same playable item now instead of waiting for speculative preroll.
      if selectedPreparation == revision { return }
      // Preroll fills/decodes the first samples without starting playback or
      // taking the audio route. The selected deck is promoted, never rebuilt.
      warmStatus = "preroll " + warmDeck.id
      let ready = await withCheckedContinuation { continuation in
        deck.preroll(atRate: 1) { continuation.resume(returning: $0) }
      }
      try Task.checkCancellation()
      guard ready, preparationRevision == revision, warmupContext() == warmDeck.context else {
        throw AudioPlaybackError.unavailable
      }
      preparingID = nil
      preparingContext = nil
      transitionRequest = nil
      warmReadyID = warmDeck.id
      warmStatus = "ready " + warmDeck.id
    }

    private func makeTransitionPlayer(item: AVPlayerItem) -> AVPlayer {
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-warm-delay") {
          let deck = AVPlayer()
          Task { @MainActor [weak deck] in
            try? await Task.sleep(for: .seconds(12))
            deck?.replaceCurrentItem(with: item)
          }
          return deck
        }
      #endif
      return AVPlayer(playerItem: item)
    }
    @discardableResult func transition(
      to videoID: String, seconds: Double, dj: Bool, preserveIntent: Bool = false,
      accountOnly: Bool = false, startAt: Double = 0
    ) -> Bool {
      guard !cast.connected, (seconds == 0 || playing), let deck = prepared, deck.id == videoID,
        deck.accountOnly == accountOnly, deck.startAt == startAt,
        (seconds == 0 || warmReadyID == videoID), deck.player.status == .readyToPlay,
        deck.player.currentItem?.status == .readyToPlay,
        AudioWarmupValidity.usable(preparedAt: deck.preparedAt, sourceURL: deck.sourceURL,
          context: deck.context, current: warmupContext())
      else { return false }
      let wasChangingDeck = changingDeck
      changingDeck = true
      defer { changingDeck = wasChangingDeck }
      let completedPreroll = warmReadyID == videoID
      // A tap can arrive while preroll is pending. Retire its callbacks before
      // promoting the deck so neither its timeout nor its cleanup touches playback.
      preparationRevision = UUID()
      selectedPreparation = nil
      transitionRequest?.cancel()
      if !completedPreroll { deck.player.cancelPendingPrerolls() }
      if seconds > 0 { crossfadeStarts += 1 } else { warmStarts += 1 }
      // An in-flight selection has already started this clock in startLoad.
      if !preserveIntent {
        preparationBegan = ProcessInfo.processInfo.systemUptime
        request?.cancel()
      } else if !intent.wantsPlayback {
        preparationBegan = nil
      }
      finishLoadingTask()
      restoredPosition = nil
      initialSeek = nil
      let old = nativePlayer
      if let progress { old.removeTimeObserver(progress) }
      progress = nil
      rateObservation = nil
      statusObservation = nil
      if let ended { NotificationCenter.default.removeObserver(ended) }
      ended = nil
      outgoing = old
      outgoingLoader = rangeLoader
      outgoingTap = currentTap ?? effectsTap
      nativePlayer = deck.player
      rangeLoader = deck.loader
      playlistContext = deck.loader?.originalSourceForRetry == nil ? nil : (deck.context, deck.preparedAt)
      playlistAttachedAt = nil
      activeSourceURL = deck.sourceURL
      activeRangeToken = deck.rangeToken
      assetRevision = UUID()
      recovery = AudioRecovery()
      rejectedSources.removeAll()
      deferredRecovery = false
      startRecoveryWatch()
      currentTap = deck.tap
      deck.tap.attach(to: deck.player.currentItem)
      prepared = nil
      preparingID = nil
      preparingContext = nil
      transitionRequest = nil
      warmReadyID = ""
      self.videoId = videoID
      requiresAccount = deck.accountOnly
      let expected = preserveIntent ? intent.revision : intent.load()
      loadID = expected
      elapsed = deck.source?.isLive == true ? 0 : startAt
      durationSeconds = deck.duration
      timingDiagnostic = deck.timingDiagnostic
      isLoading = false
      playbackError = nil
      sourceDiagnostic = deck.source?.accountDiagnostic ?? "File locale verificato"
      networkDiagnostic = "Audio preparato in anticipo; controlli della sorgente mantenuti"
      audioResolutionReport = (deck.source?.resolutionReport ?? "File locale")
        + (deck.usedOriginalReader ? "\nPreparazione: riuso della sorgente verificata con il lettore originale" : "")
        + (completedPreroll ? "\nPreparazione: riuso del player e del buffer già pronti"
                            : "\nPreparazione: riuso del player appena riproducibile, senza attendere il preroll")
      audioReportFinalized = true
      recordPreparation("player anticipato selezionato")
      bindPlayer()
      let generation = assetRevision
      statusObservation = deck.player.currentItem?.observe(\.status, options: [.new]) {
        @Sendable [weak self] item, _ in
        guard item.status == .failed else { return }
        Task { @MainActor in
          guard let self, self.assetRevision == generation else { return }
          if !self.recoverAudio(reason: "Errore del flusso durante la transizione") {
            self.pause()
            self.playbackError = self.unavailableMessage
          }
        }
      }
      ended = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: deck.player.currentItem, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.intent.revision == expected,
            self.assetRevision == generation
          else { return }
          self.pause()
          self.onEnded?()
        }
      }
      if seconds == 0 {
        old.pause()
        outgoing = nil
        outgoingLoader = nil
        outgoingTap = nil
        nativePlayer.volume = Float(volume / 100)
        startPreparedPlayback()
        return true
      }
      startPreparedPlayback()
      fadeTask = Task { [weak self] in
        let start = Date()
        while !Task.isCancelled {
          guard let self, self.loadID == expected else { return }
          let fraction = min(1, Date().timeIntervalSince(start) / seconds)
          let gain = CrossfadeCurve.gains(progress: fraction, dj: dj)
          if dj {
            self.outgoingTap?.state.setDJ(fraction, incoming: false)
            self.currentTap?.state.setDJ(fraction, incoming: true)
          }
          old.volume = Float(self.volume / 100 * gain.outgoing)
          self.nativePlayer.volume = Float(self.volume / 100 * gain.incoming)
          if fraction >= 1 {
            self.currentTap?.state.setDJ(nil, incoming: true)
            old.pause()
            self.outgoing = nil
            self.outgoingLoader = nil
            self.outgoingTap = nil
            self.fadeTask = nil
            break
          }
          try? await Task.sleep(for: .milliseconds(40))
        }
      }
      return true
    }
    var onEnded: (() -> Void)?
    var localFileProvider: @MainActor (String) -> URL? = { _ in nil }
    var accountProvider: @MainActor () -> YouTubeSession? = { nil }
    var accountRevisionProvider: @MainActor () -> UUID? = { nil }
    private let defaultAccountRevision = UUID()
    private func warmupContext() -> AudioWarmupContext {
      AudioWarmupContext(session: accountProvider(), quality: AudioPreferences.shared.currentQuality,
        networkRevision: AudioPreferences.shared.networkRevision,
        accountRevision: accountRevisionProvider() ?? defaultAccountRevision)
    }
    var beforePlay: (() -> Bool)?
    private var restoredPosition: Double?
    func prepareRestoredTrack() {
      guard let position = restoredPosition, !videoId.isEmpty, !isLoading, !playing else { return }
      prepareTransition(videoID: videoId, accountOnly: requiresAccount, startAt: position)
    }
    private var initialSeek: Double?
    func restore(videoID: String, position: Double, duration: Double, accountOnly: Bool = false) {
      clear()
      self.videoId = videoID
      requiresAccount = accountOnly
      elapsed = position
      durationSeconds = duration
      restoredPosition = position
    }
    private var intent = PlaybackIntent()
    private var request: Task<Void, Never>?
    private var rangeLoader: AudioRangeLoader?
    private var playlistAttachedAt: TimeInterval?
    private var playlistContext: (value: AudioWarmupContext, date: Date)?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var progress: Any?
    private var ended: NSObjectProtocol?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var activeSourceURL: URL?
    private var rejectedSources = Set<URL>()
    private var assetRevision = UUID()
    private var recovery = AudioRecovery()
    private var recoveryWatch: Task<Void, Never>?
    private var deferredRecovery = false
    #if DEBUG
      var recoveryAttempts: Int { recovery.attempts }
    #endif
    var wantsPlayback: Bool { intent.wantsPlayback }
    var rate: Float { nativePlayer.rate }
    var timeControlStatus: AVPlayer.TimeControlStatus { nativePlayer.timeControlStatus }

    init() {
      effectsSubscription = AudioPreferences.shared.$effects.combineLatest(AudioPreferences.shared.$djMode)
        .sink { [weak self] value, dj in
          self?.effectsTap.configure(value)
          self?.currentTap?.configure(value)
          self?.prepared?.tap.configure(value)
          if #unavailable(iOS 27), value.enabled || dj {
            Task { @MainActor [weak self] in self?.restoreFilePlaybackForEffects() }
          }
        }
      // Preparation supplies initial bytes; playImmediately starts without a throughput estimate.
      // Keep automatic recovery enabled when a cellular connection runs out of buffered audio.
      nativePlayer.automaticallyWaitsToMinimizeStalling = true
      bindPlayer()
    }
    private func bindPlayer() {
      nativePlayer.allowsExternalPlayback = true
      let observedPlayer = nativePlayer
      rateObservation = nativePlayer.observe(\.timeControlStatus, options: [.new]) {
        @Sendable [weak self] player, _ in
        Task { @MainActor [weak self] in
          guard let self, self.nativePlayer === observedPlayer, !self.cast.connected else { return }
          let active = observedPlayer.timeControlStatus == .playing
          self.playing = active
          if active {
            if !self.isLoading, self.initialSeek == nil {
              self.recordPreparation("riproduzione avviata")
              self.preparationBegan = nil
            }
            // Once audible, grow the forward buffer again for cellular resilience.
            self.nativePlayer.currentItem?.preferredForwardBufferDuration = 30
          }
        }
      }
      progress = nativePlayer.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
      ) { [weak self] time in
        let seconds = time.seconds
        Task { @MainActor [weak self] in
          guard let self, self.nativePlayer === observedPlayer, seconds.isFinite, seconds >= 0
          else { return }
          // Item replacement briefly reports zero before the restoring seek ends.
          guard !self.cast.connected, !self.isLoading, self.initialSeek == nil,
            self.restoredPosition == nil else { return }
          self.elapsed = seconds
          #if DEBUG
            if self.nativePlayer.currentItem?.status == .readyToPlay {
              self.diagnostic =
                "ready intent \(self.intent.wantsPlayback), rate \(self.nativePlayer.rate), control \(self.nativePlayer.timeControlStatus.rawValue), time \(Int(seconds)), recovery \(self.recovery.attempts), PCM \((self.currentTap ?? self.effectsTap).state.processedFrames)"
            }
          #endif
        }
      }
    }

    func load(videoId: String, startAt: Double? = nil, accountOnly: Bool = false) {
      requiresAccount = accountOnly
      if cast.connected {
        request?.cancel(); cancelTransition(); recoveryWatch?.cancel()
        intent.load(); intent.play()
        cast.load(id: videoId, position: startAt ?? 0, accountOnly: accountOnly); return
      }
      recovery = AudioRecovery()
      rejectedSources.removeAll()
      deferredRecovery = false
      activeSourceURL = nil
      activeRangeToken = nil
      startLoad(videoId: videoId, startAt: startAt, recovering: false)
    }

    /// A repaired source is still the same queue occurrence. Keep loadID and the
    /// user's intent so narration, pause, seeks and track changes remain authoritative.
    private func startLoad(videoId: String, startAt: Double?, recovering: Bool,
      originalSource: YouTubeAudio.Source? = nil) {
      let wasChangingDeck = changingDeck
      changingDeck = true
      defer { changingDeck = wasChangingDeck }
      let position = startAt ?? 0
      if !recovering,
        transition(to: videoId, seconds: 0, dj: false, accountOnly: requiresAccount, startAt: position)
      {
        return
      }
      // Share a matching in-flight preparation instead of restarting its requests.
      let pendingWarmup = !recovering && preparingPosition == position && preparingID == videoId
          && preparingContext == warmupContext() && preparingAccountOnly == requiresAccount
        ? transitionRequest : nil
      if pendingWarmup != nil { selectedPreparation = preparationRevision }
      preparationBegan = ProcessInfo.processInfo.systemUptime
      restoredPosition = nil
      initialSeek = position > 0 ? position : nil
      cancelTransition(discardPrepared: pendingWarmup == nil)
      currentTap = nil
      request?.cancel()
      finishLoadingTask()
      nativePlayer.pause()
      nativePlayer.replaceCurrentItem(with: nil)
      rangeLoader = nil
      playlistAttachedAt = nil
      playlistContext = nil
      activeRangeToken = nil
      statusObservation = nil
      if let ended { NotificationCenter.default.removeObserver(ended) }
      ended = nil
      let expected = recovering ? intent.revision : intent.load()
      assetRevision = UUID()
      let generation = assetRevision
      self.videoId = videoId
      loadID = expected
      playing = false
      isLoading = true
      elapsed = startAt ?? 0
      if !recovering { durationSeconds = 0 }
      timingDiagnostic = "Durata in verifica"
      let previousReport = recovering
        ? String(audioResolutionReport.suffix(16000)) + "\n--- Recupero audio ---\n" : ""
      let networkContext = previousReport + "Rete all'avvio: " + AudioPreferences.shared.networkDiagnostic + "\n"
      audioResolutionReport = networkContext + "Risoluzione audio in corso"
      audioReportFinalized = false
      playbackError = nil
      recovery.resetStall()
      startRecoveryWatch()
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-playback-order")
          || ProcessInfo.processInfo.arguments.contains("--test-full-search")
        {
          isLoading = false
          return
        }
      #endif
      // Allow the next track to resolve while the phone remains locked.
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare music") {
        [weak self] in
        Task { @MainActor [weak self] in
          guard let self, self.intent.revision == expected, self.assetRevision == generation else {
            return
          }
          self.request?.cancel()
          if self.selectedPreparation != nil { self.cancelTransition() }
          self.isLoading = false
          self.pause()
          self.playbackError = "Caricamento audio interrotto. Riprova."
          self.finishLoadingTask()
        }
      }
      request = Task {
        do {
          if let pendingWarmup {
            warmWaits += 1
            await pendingWarmup.value
            try Task.checkCancellation()
            guard intent.revision == expected, assetRevision == generation else { return }
            if transition(
              to: videoId, seconds: 0, dj: false, preserveIntent: true, accountOnly: requiresAccount,
              startAt: position
            ) {
              return
            }
            cancelTransition()
          }
          let asset: AVURLAsset
          var sourceDuration = 0.0
          var sourceIsLive = false
          if let local = localFileProvider(videoId) {
            asset = AVURLAsset(url: local)
            #if DEBUG
              if ProcessInfo.processInfo.arguments.contains("--test-padded-audio-end"),
                videoId == "local-1-padded" { sourceDuration = 6 }
            #endif
            sourceDiagnostic = "File locale verificato"
            networkDiagnostic = "Riproduzione offline, nessuna richiesta CDN"
            audioResolutionReport = "File locale; nessuna richiesta CDN"
            audioReportFinalized = true
          } else {
            let context = warmupContext()
            let source: YouTubeAudio.Source
            if let originalSource {
              source = originalSource
            } else {
              source = try await YouTubeAudio().resolve(
                videoID: videoId, session: context.session,
                quality: context.quality, excluding: rejectedSources,
                preferHLS: recovering, preferHLSForLongTracks: true, accountOnly: requiresAccount,
                preloadFirstBlock: true,
                diagnostic: { [weak self] report in
                  Task { @MainActor [weak self] in
                    guard let self, self.intent.revision == expected, self.assetRevision == generation,
                      !self.audioReportFinalized
                    else { return }
                    self.audioResolutionReport = networkContext + report
                  }
                })
            }
            #if DEBUG
              diagnostic = "source bytes \(source.byteCount ?? 0)"
            #endif
            try Task.checkCancellation()
            guard intent.revision == expected, assetRevision == generation else { return }
            activeSourceURL = source.url
            sourceDiagnostic = source.accountDiagnostic
            audioReportFinalized = true
            audioResolutionReport = originalSource == nil ? networkContext + source.resolutionReport
              : networkContext + "Riuso della sorgente verificata con il lettore originale"
            recordPreparation("sorgente verificata")
            if source.isHLS {
              networkDiagnostic = (source.authenticated ? "Flusso account HLS" : "Flusso pubblico HLS")
                + (source.isLive ? "; diretta, segmento corrente verificato" : "; segmenti iniziale, oltre il minuto e finale verificati")
            } else {
              networkDiagnostic =
                source.authenticated
                ? "Flusso account YouTube Music; controllo finale superato"
                : "Flusso pubblico; controlli oltre 1 MiB e finali superati"
            }
            if recovering {
              let mode = originalSource == nil ? "Nuova sorgente" : "Lettore originale"
              let action = recovery.attempts == 0 ? "Effetti audio" : "\(mode), recupero \(recovery.attempts)/2"
              networkDiagnostic = action + "; " + networkDiagnostic
            }
            durationSeconds = source.duration
            sourceDuration = source.duration
            sourceIsLive = source.isLive
            if source.isLive { initialSeek = nil }
            let token = UUID()
            activeRangeToken = token
            let loader = makeRangeLoader(source: source, token: token)
            rangeLoader = loader
            if loader.originalSourceForRetry != nil { playlistContext = (context, Date()) }
            try await loader.prepare()
            try Task.checkCancellation()
            guard intent.revision == expected, assetRevision == generation else { return }
            recordPreparation("primo buffer pronto")
            asset = loader.asset()
          }
          // The default initializer automatically loads duration before readyToPlay,
          // which scans long fragmented files even without an explicit load(.duration).
          let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [])
          item.preferredForwardBufferDuration = 5
          let timing = try await AudioPlaybackTiming.prepare(asset, source: sourceDuration, isLive: sourceIsLive)
          try Task.checkCancellation()
          guard intent.revision == expected, assetRevision == generation else { return }
          timingDiagnostic = timing.diagnostic
          recordPreparation("durata pronta")
          if timing.duration > 0 {
            item.forwardPlaybackEndTime = CMTime(seconds: timing.duration, preferredTimescale: 600)
          }
          statusObservation = item.observe(\.status, options: [.initial, .new]) {
            @Sendable [weak owner = self] item, _ in
            let status = item.status
            let duration = item.duration.seconds
            Task { @MainActor [weak owner] in
              guard let self = owner, self.intent.revision == expected,
                self.assetRevision == generation
              else { return }
              switch status {
              case .readyToPlay:
                self.playlistAttachedAt = nil
                self.effectsTap.attach(to: item)
                self.recordPreparation("player pronto")
                #if DEBUG
                  self.diagnostic = "ready intent \(self.intent.wantsPlayback)"
                #endif
                self.isLoading = false
                if timing.duration > 0 {
                  self.durationSeconds = timing.duration
                } else if !timing.isLive, duration.isFinite, duration > 0 {
                  self.durationSeconds = duration
                }
                if self.initialSeek != nil {
                  self.restorePendingSeek(expected: expected, generation: generation)
                } else {
                  self.startPreparedPlayback()
                }
                #if DEBUG
                  self.diagnostic +=
                    ", rate \(self.nativePlayer.rate), control \(self.nativePlayer.timeControlStatus.rawValue)"
                #endif
              case .failed:
                #if DEBUG
                  let error = self.nativePlayer.currentItem?.error as NSError?
                  let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError
                  self.diagnostic =
                    "failed \(error?.domain ?? "") \(error?.code ?? 0), underlying \(underlying?.code ?? 0)"
                #endif
                self.finishLoadingTask()
                self.isLoading = false
                if !self.recoverAudio(reason: "Il flusso audio si è interrotto") {
                  self.pause()
                  self.playbackError = self.unavailableMessage
                }
              default: break
              }
            }
          }
          ended = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
          ) { [weak owner = self] _ in
            Task { @MainActor [weak owner] in
              guard let self = owner, self.intent.revision == expected,
                self.assetRevision == generation
              else { return }
              self.pause()
              self.onEnded?()
            }
          }
          if rangeLoader?.originalSourceForRetry != nil {
            playlistAttachedAt = ProcessInfo.processInfo.systemUptime
          }
          nativePlayer.replaceCurrentItem(with: item)
        } catch {
          guard intent.revision == expected, assetRevision == generation, !Task.isCancelled else {
            return
          }
          isLoading = false
          finishLoadingTask()
          if let failure = error as? AudioResolutionFailure {
            audioReportFinalized = true
            sourceDiagnostic = failure.accountDiagnostic
            networkDiagnostic = failure.networkDiagnostic
            audioResolutionReport = networkContext + failure.resolutionReport
          }
          if !recoverAudio(reason: "Caricamento audio non riuscito") {
            pause()
            playbackError = unavailableMessage
          }
        }
      }
    }

    private func restorePendingSeek(expected: UUID, generation: UUID) {
      guard intent.revision == expected, assetRevision == generation,
        let position = initialSeek
      else { return }
      nativePlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600)) {
        [weak self] finished in
        Task { @MainActor in
          guard let self, self.intent.revision == expected,
            self.assetRevision == generation
          else { return }
          // A seek made while replacement was loading wins over the old position.
          if self.initialSeek != position {
            self.restorePendingSeek(expected: expected, generation: generation)
            return
          }
          guard finished else {
            self.finishLoadingTask()
            self.initialSeek = nil
            self.pause()
            self.playbackError = "Impossibile riprendere dalla posizione richiesta. Riprova."
            return
          }
          self.initialSeek = nil
          self.elapsed = position
          self.recordPreparation("posizione ripristinata")
          self.recovery.resetStall()
          self.startPreparedPlayback()
        }
      }
    }

    private func startPreparedPlayback() {
      defer { finishLoadingTask() }
      guard !cast.connected, intent.wantsPlayback, !isLoading, initialSeek == nil,
        beforePlay?() ?? true
      else { return }
      do {
        try AppleAudioSession.activate()
        nativePlayer.playImmediately(atRate: 1)
      } catch {
        pause()
        playbackError = "Impossibile attivare l’uscita audio. Riprova."
      }
    }

    private var needsFileForEffects: Bool {
      if #available(iOS 27, *) { return false }
      return AudioPreferences.shared.effects.enabled || AudioPreferences.shared.djMode
    }

    private func makeRangeLoader(source: YouTubeAudio.Source, token: UUID) -> AudioRangeLoader {
      var media = source
      if !source.isHLS, needsFileForEffects {
        // Earlier iOS versions can apply an audio processing tap to the AAC file only.
        media = source.withoutPlaylist
      }
      return AudioRangeLoader(source: media, diagnostic: rangeDiagnostic(token: token))
    }

    private func restoreFilePlaybackForEffects() {
      guard needsFileForEffects else { return }
      if prepared?.loader?.originalSourceForRetry?.isHLS == false { cancelTransition() }
      guard !cast.connected, rangeLoader?.originalSourceForRetry?.isHLS == false else { return }
      if intent.wantsPlayback { isLoading = false }
      _ = recoverAudio(reason: "Attivazione effetti audio")
    }

    private func rangeDiagnostic(token: UUID) -> @Sendable (String) -> Void {
      { [weak self] message in
        guard message.contains("HTTP ") && !message.contains("HTTP 206")
          || message.contains("network error") else { return }
        Task { @MainActor [weak self] in
          // Warm readers are silent until promoted. Ignore late callbacks from
          // any loader that is no longer the active validated source.
          guard let self, self.activeRangeToken == token else { return }
          self.networkDiagnostic = String(message.prefix(300))
          self.audioResolutionReport = (self.audioResolutionReport + "\nPlayback: " + message)
            .components(separatedBy: .newlines).suffix(96).joined(separator: "\n")
          if message.contains("HTTP 403"), !self.isLoading {
            if !self.recoverAudio(reason: "Il server ha rifiutato il flusso") {
              self.pause()
              self.playbackError = "Il server non consente di proseguire questo brano. Riprova."
            }
          }
        }
      }
    }

    private func startRecoveryWatch() {
      recoveryWatch?.cancel()
      recoveryWatch = Task { [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          guard let self else { return }
          let position = self.nativePlayer.currentTime().seconds
          if let attached = self.playlistAttachedAt, self.isLoading, self.intent.wantsPlayback,
            self.nativePlayer.currentItem?.status == .unknown,
            ProcessInfo.processInfo.systemUptime - attached >= 12 {
            self.playlistAttachedAt = nil
            self.isLoading = false
            if self.recoverAudio(reason: "Timeout in apertura della playlist") { return }
          }
          #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-audio-recovery"),
              self.recovery.attempts == 0, position >= 6, self.intent.wantsPlayback
            {
              _ = self.recoverAudio(reason: "Test: flusso interrotto")
              return
            }
          #endif
          guard
            self.recovery.observe(
              position: position, now: ProcessInfo.processInfo.systemUptime,
              shouldPlay: self.intent.wantsPlayback,
              ready: !self.isLoading && self.initialSeek == nil
                && self.nativePlayer.currentItem?.status == .readyToPlay,
              duration: self.durationSeconds)
          else { continue }
          guard self.activeSourceURL != nil else { continue }
          if !self.recoverAudio(reason: "La riproduzione non avanza") {
            self.pause()
            self.playbackError = "La riproduzione non riesce a proseguire. Riprova."
          }
          return
        }
      }
    }

    @discardableResult private func recoverAudio(reason: String) -> Bool {
      var canRecover = activeSourceURL != nil
      #if DEBUG
        canRecover =
          canRecover
          || ProcessInfo.processInfo.arguments.contains("--test-audio-recovery")
      #endif
      guard canRecover, !videoId.isEmpty else { return false }
      guard !isLoading else { return true }
      // Pause/TTS owns playback. Remember a failed source, but do not start audio
      // or consume retry budget until the user (or narration completion) resumes.
      guard intent.wantsPlayback else {
        deferredRecovery = true
        return true
      }
      // Changing the processing route on older systems does not fail the media source.
      let enablingEffects = needsFileForEffects && rangeLoader?.originalSourceForRetry?.isHLS == false
      guard enablingEffects || recovery.begin() else { return false }
      let originalSource = playlistContext.flatMap { context in
        AudioWarmupValidity.usable(preparedAt: context.date, sourceURL: activeSourceURL,
          context: context.value, current: warmupContext()) ? rangeLoader?.originalSourceForRetry : nil
      }
      if originalSource == nil, !enablingEffects, let activeSourceURL { rejectedSources.insert(activeSourceURL) }
      let actual = nativePlayer.currentTime().seconds
      let position = initialSeek ?? (actual.isFinite && actual >= 0 ? actual : elapsed)
      networkDiagnostic = "\(reason); recupero \(recovery.attempts)/2 a \(Int(position)) s"
      startLoad(videoId: videoId, startAt: position, recovering: true, originalSource: originalSource)
      return true
    }

    private func finishLoadingTask() {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }

    func syncCastPlayback(playing value: Bool) {
      if playing != value { controlRevision = UUID() }
      playing = value
      if value { intent.play() } else { intent.pause() }
    }
    func prepareForCasting() {
      request?.cancel(); assetRevision = UUID(); cancelTransition()
      recoveryWatch?.cancel(); nativePlayer.pause()
    }
    func clear() {
      cast.clear()
      playlistContext = nil
      playlistAttachedAt = nil
      preparationBegan = nil
      recoveryWatch?.cancel()
      recoveryWatch = nil
      assetRevision = UUID()
      activeSourceURL = nil
      rejectedSources.removeAll()
      recovery = AudioRecovery()
      deferredRecovery = false
      cancelTransition()
      currentTap = nil
      restoredPosition = nil
      initialSeek = nil
      request?.cancel()
      request = nil
      finishLoadingTask()
      intent.load()
      intent.pause()
      nativePlayer.pause()
      nativePlayer.replaceCurrentItem(with: nil)
      rangeLoader = nil
      activeRangeToken = nil
      statusObservation = nil
      if let ended { NotificationCenter.default.removeObserver(ended) }
      ended = nil
      videoId = ""
      loadID = intent.revision
      elapsed = 0
      durationSeconds = 0
      playing = false
      isLoading = false
      playbackError = nil
    }

    private(set) var controlRevision = UUID()

    func play() {
      guard beforePlay?() ?? true else { return }
      if cast.connected { controlRevision = UUID(); intent.play(); cast.play(); return }
      if let position = restoredPosition {
        restoredPosition = nil
        let id = videoId
        load(videoId: id, startAt: position, accountOnly: requiresAccount)
        return
      }
      controlRevision = UUID()
      do {
        try AppleAudioSession.activate()
        intent.play()
        recovery.resetStall()
        if deferredRecovery {
          deferredRecovery = false
          if recoverAudio(reason: "Riprendo il flusso interrotto") { return }
          pause()
          playbackError = unavailableMessage
          return
        }
        // A user can resume while replacement is still resolving. The ready/seek
        // callback starts audio after preparation, never the removed old item.
        guard !isLoading, initialSeek == nil else { return }
        nativePlayer.playImmediately(atRate: 1)
      } catch {
        #if DEBUG
          diagnostic = "resolve failed \((error as NSError).domain) \((error as NSError).code)"
        #endif
        pause()
        playbackError = "Impossibile attivare l’uscita audio. Riprova."
      }
    }
    func pause() {
      if cast.connected { controlRevision = UUID(); intent.pause(); cast.pause(); playing = false; return }
      // Pause/track-end/narration silence both audible decks, retaining only the
      // muted successor. Otherwise normal auto-advance would discard its warmup.
      cancelTransition(discardPrepared: false)
      controlRevision = UUID()
      intent.pause()
      recovery.resetStall()
      nativePlayer.pause()
      playing = false
    }
    func seek(to time: CMTime) {
      if cast.connected { if time.seconds.isFinite { cast.seek(max(0, time.seconds)) }; return }
      guard time.seconds.isFinite else { return }
      let preparingRestore = restoredPosition != nil && (preparingID == videoId || prepared?.id == videoId)
      cancelTransition()
      let value = max(0, min(durationSeconds > 0 ? durationSeconds : time.seconds, time.seconds))
      recovery.resetStall()
      if isLoading || initialSeek != nil {
        initialSeek = value
        elapsed = value
        return
      }
      if restoredPosition != nil {
        restoredPosition = value
        elapsed = value
        if preparingRestore { prepareRestoredTrack() }
        return
      }
      nativePlayer.seek(to: CMTime(seconds: value, preferredTimescale: 600))
    }
    func setVolume(_ value: Double) {
      volume = min(100, max(0, value))
      if cast.connected { cast.volume(volume); return }
      if fadeTask == nil { nativePlayer.volume = Float(volume / 100) }
    }
    func currentTime() -> CMTime {
      if cast.connected { return CMTime(seconds: elapsed, preferredTimescale: 600) }
      return restoredPosition == nil && !isLoading && initialSeek == nil
        ? nativePlayer.currentTime() : CMTime(seconds: elapsed, preferredTimescale: 600)
    }
    func interruptionBegan() {
      intent.interruptionBegan()
      recovery.resetStall()
      nativePlayer.pause()
      playing = false
    }
    func interruptionEnded(shouldResume: Bool) {
      if intent.interruptionEnded(shouldResume: shouldResume) { play() }
    }
  }
#endif

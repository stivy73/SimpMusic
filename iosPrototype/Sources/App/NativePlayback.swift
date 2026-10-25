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
    @Published var sourceDiagnostic =
      UserDefaults.standard.string(forKey: "lastAudioSourceDiagnostic") ?? "Flusso non verificato"
    { didSet { UserDefaults.standard.set(sourceDiagnostic, forKey: "lastAudioSourceDiagnostic") } }
    @Published var networkDiagnostic =
      UserDefaults.standard.string(forKey: "lastAudioNetworkDiagnostic")
      ?? "Nessun errore CDN registrato"
    {
      didSet { UserDefaults.standard.set(networkDiagnostic, forKey: "lastAudioNetworkDiagnostic") }
    }
    #if DEBUG
      @Published var diagnostic = "idle"
    #endif
    @Published private(set) var crossfadeStarts = 0
    private(set) var nativePlayer = AVPlayer()
    private let effectsTap = AudioEffectsTap()
    private var effectsSubscription: AnyCancellable?
    private struct PreparedDeck {
      let id: String
      let player: AVPlayer
      let loader: AudioRangeLoader?
      let tap: AudioEffectsTap
      let duration: Double
    }
    private var prepared: PreparedDeck?
    private var preparingID: String?
    private var transitionRequest: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var outgoing: AVPlayer?
    private var outgoingLoader: AudioRangeLoader?
    private var outgoingTap: AudioEffectsTap?
    private var currentTap: AudioEffectsTap?
    func cancelTransition() {
      transitionRequest?.cancel()
      transitionRequest = nil
      preparingID = nil
      prepared?.player.pause()
      prepared = nil
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
    func prepareTransition(videoID: String) {
      guard videoID != preparingID, videoID != prepared?.id else { return }
      transitionRequest?.cancel()
      prepared = nil
      preparingID = videoID
      transitionRequest = Task {
        do {
          let asset: AVURLAsset
          var loader: AudioRangeLoader?
          var duration = 0.0
          if let url = localFileProvider(videoID) {
            asset = AVURLAsset(url: url)
          } else {
            let source = try await YouTubeAudio().resolve(
              videoID: videoID, session: accountProvider(),
              quality: AudioPreferences.shared.currentQuality)
            let nextLoader = AudioRangeLoader(source: source)
            try await nextLoader.prepare()
            loader = nextLoader
            asset = nextLoader.asset()
            duration = source.duration
          }
          try Task.checkCancellation()
          let item = AVPlayerItem(asset: asset)
          item.preferredForwardBufferDuration = 15
          let tap = AudioEffectsTap()
          tap.configure(AudioPreferences.shared.effects)
          if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            tap.attach(to: item, track: track)
          }
          try Task.checkCancellation()
          guard preparingID == videoID else { return }
          let deck = AVPlayer(playerItem: item)
          deck.volume = 0
          prepared = PreparedDeck(
            id: videoID, player: deck, loader: loader, tap: tap, duration: duration)
        } catch { if preparingID == videoID { preparingID = nil } }
      }
    }
    @discardableResult func transition(to videoID: String, seconds: Double, dj: Bool) -> Bool {
      guard playing, let deck = prepared, deck.id == videoID,
        deck.player.currentItem?.status == .readyToPlay, seconds > 0
      else { return false }
      crossfadeStarts += 1
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
      currentTap = deck.tap
      prepared = nil
      preparingID = nil
      transitionRequest = nil
      self.videoId = videoID
      let expected = intent.load()
      loadID = expected
      elapsed = 0
      durationSeconds = deck.player.currentItem?.duration.seconds ?? deck.duration
      if !durationSeconds.isFinite { durationSeconds = deck.duration }
      isLoading = false
      playbackError = nil
      bindPlayer()
      ended = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: deck.player.currentItem, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self, self.intent.revision == expected else { return }
          self.pause()
          self.onEnded?()
        }
      }
      nativePlayer.playImmediately(atRate: 1)
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
    var beforePlay: (() -> Bool)?
    private var restoredPosition: Double?
    private var initialSeek: Double?
    func restore(videoID: String, position: Double, duration: Double) {
      clear()
      self.videoId = videoID
      elapsed = position
      durationSeconds = duration
      restoredPosition = position
    }
    private var intent = PlaybackIntent()
    private var request: Task<Void, Never>?
    private var rangeLoader: AudioRangeLoader?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var progress: Any?
    private var ended: NSObjectProtocol?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    var wantsPlayback: Bool { intent.wantsPlayback }
    var rate: Float { nativePlayer.rate }
    var timeControlStatus: AVPlayer.TimeControlStatus { nativePlayer.timeControlStatus }

    init() {
      effectsSubscription = AudioPreferences.shared.$effects.sink { [weak self] value in
        self?.effectsTap.configure(value)
        self?.currentTap?.configure(value)
        self?.prepared?.tap.configure(value)
      }
      // Preparation supplies initial bytes; playImmediately starts without a throughput estimate.
      // Keep automatic recovery enabled when a cellular connection runs out of buffered audio.
      nativePlayer.automaticallyWaitsToMinimizeStalling = true
      bindPlayer()
    }
    private func bindPlayer() {
      let observedPlayer = nativePlayer
      rateObservation = nativePlayer.observe(\.timeControlStatus, options: [.new]) {
        @Sendable [weak self] player, _ in
        let active = player.timeControlStatus == .playing
        Task { @MainActor [weak self] in
          guard let self, self.nativePlayer === observedPlayer else { return }
          self.playing = active
        }
      }
      progress = nativePlayer.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
      ) { [weak self] time in
        let seconds = time.seconds
        Task { @MainActor [weak self] in
          guard let self, self.nativePlayer === observedPlayer, seconds.isFinite, seconds >= 0
          else { return }
          self.elapsed = seconds
          #if DEBUG
            if self.nativePlayer.currentItem?.status == .readyToPlay {
              self.diagnostic =
                "ready intent \(self.intent.wantsPlayback), rate \(self.nativePlayer.rate), control \(self.nativePlayer.timeControlStatus.rawValue), time \(Int(seconds)), PCM \((self.currentTap ?? self.effectsTap).state.processedFrames)"
            }
          #endif
        }
      }
    }

    func load(videoId: String, startAt: Double? = nil) {
      restoredPosition = nil
      initialSeek = startAt
      cancelTransition()
      currentTap = nil
      request?.cancel()
      finishLoadingTask()
      nativePlayer.pause()
      nativePlayer.replaceCurrentItem(with: nil)
      rangeLoader = nil
      statusObservation = nil
      if let ended { NotificationCenter.default.removeObserver(ended) }
      ended = nil
      let expected = intent.load()
      self.videoId = videoId
      loadID = expected
      elapsed = 0
      durationSeconds = 0
      playing = false
      playbackError = nil
      isLoading = true
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
          guard let self, self.intent.revision == expected else { return }
          self.request?.cancel()
          self.isLoading = false
          self.pause()
          self.playbackError = "Caricamento audio interrotto. Riprova."
          self.finishLoadingTask()
        }
      }
      request = Task {
        do {
          let asset: AVURLAsset
          if let local = localFileProvider(videoId) {
            asset = AVURLAsset(url: local)
            sourceDiagnostic = "File locale verificato"
            networkDiagnostic = "Riproduzione offline, nessuna richiesta CDN"
          } else {
            let source = try await YouTubeAudio().resolve(
              videoID: videoId, session: accountProvider(),
              quality: AudioPreferences.shared.currentQuality)
            #if DEBUG
              diagnostic = "source bytes \(source.byteCount ?? 0)"
            #endif
            try Task.checkCancellation()
            guard intent.revision == expected else { return }
            sourceDiagnostic = source.accountDiagnostic
            networkDiagnostic =
              source.authenticated
              ? "Flusso account YouTube Music; controllo finale superato"
              : "Flusso IOS pubblico; nessun flusso autenticato disponibile"
            durationSeconds = source.duration
            let loader = AudioRangeLoader(source: source) { [weak self] message in
              guard
                message.contains("HTTP ") && !message.contains("HTTP 206")
                  || message.contains("network error")
              else { return }
              Task { @MainActor [weak self] in
                guard let self, self.intent.revision == expected else { return }
                self.networkDiagnostic = String(message.prefix(300))
              }
            }
            rangeLoader = loader
            try await loader.prepare()
            try Task.checkCancellation()
            guard intent.revision == expected else { return }
            asset = loader.asset()
          }
          let item = AVPlayerItem(asset: asset)
          item.preferredForwardBufferDuration = 30
          if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            try Task.checkCancellation()
            guard intent.revision == expected else { return }
            effectsTap.attach(to: item, track: track)
          }
          statusObservation = item.observe(\.status, options: [.initial, .new]) {
            @Sendable [weak owner = self] item, _ in
            let status = item.status
            let duration = item.duration.seconds
            Task { @MainActor [weak owner] in
              guard let self = owner, self.intent.revision == expected else { return }
              switch status {
              case .readyToPlay:
                #if DEBUG
                  self.diagnostic = "ready intent \(self.intent.wantsPlayback)"
                #endif
                self.finishLoadingTask()
                self.isLoading = false
                if duration.isFinite, duration > 0 { self.durationSeconds = duration }
                if let position = self.initialSeek {
                  self.initialSeek = nil
                  self.nativePlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600)) {
                    [weak self] _ in
                    Task { @MainActor in
                      guard let self, self.intent.revision == expected, self.intent.wantsPlayback
                      else { return }
                      self.play()
                    }
                  }
                } else if self.intent.wantsPlayback {
                  self.play()
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
                self.pause()
                self.playbackError = AudioPlaybackError.unavailable.localizedDescription
              default: break
              }
            }
          }
          ended = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
          ) { [weak owner = self] _ in
            Task { @MainActor [weak owner] in
              guard let self = owner, self.intent.revision == expected else { return }
              self.pause()
              self.onEnded?()
            }
          }
          nativePlayer.replaceCurrentItem(with: item)
        } catch {
          guard intent.revision == expected, !Task.isCancelled else { return }
          isLoading = false
          finishLoadingTask()
          pause()
          playbackError = AudioPlaybackError.unavailable.localizedDescription
        }
      }
    }

    private func finishLoadingTask() {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }

    func clear() {
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
      if let position = restoredPosition {
        restoredPosition = nil
        let id = videoId
        load(videoId: id, startAt: position)
        return
      }
      controlRevision = UUID()
      do {
        try AppleAudioSession.activate()
        intent.play()
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
      cancelTransition()
      controlRevision = UUID()
      intent.pause()
      nativePlayer.pause()
      playing = false
    }
    func seek(to time: CMTime) {
      cancelTransition()
      guard time.seconds.isFinite else { return }
      let value = max(0, min(durationSeconds > 0 ? durationSeconds : time.seconds, time.seconds))
      if restoredPosition != nil {
        restoredPosition = value
        elapsed = value
        return
      }
      nativePlayer.seek(to: CMTime(seconds: value, preferredTimescale: 600))
    }
    func setVolume(_ value: Double) {
      volume = min(100, max(0, value))
      if fadeTask == nil { nativePlayer.volume = Float(volume / 100) }
    }
    func currentTime() -> CMTime {
      restoredPosition == nil
        ? nativePlayer.currentTime() : CMTime(seconds: elapsed, preferredTimescale: 600)
    }
    func interruptionBegan() {
      intent.interruptionBegan()
      nativePlayer.pause()
      playing = false
    }
    func interruptionEnded(shouldResume: Bool) {
      if intent.interruptionEnded(shouldResume: shouldResume) { play() }
    }
  }
#endif

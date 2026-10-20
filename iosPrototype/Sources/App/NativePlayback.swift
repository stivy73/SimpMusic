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
    #if DEBUG
      @Published var diagnostic = "idle"
    #endif
    let nativePlayer = AVPlayer()
    var onEnded: (() -> Void)?
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
      // Custom resource loaders do not expose CDN throughput estimates to AVPlayer.
      nativePlayer.automaticallyWaitsToMinimizeStalling = false
      rateObservation = nativePlayer.observe(\.timeControlStatus, options: [.new]) {
        @Sendable [weak self] player, _ in
        let active = player.timeControlStatus == .playing
        Task { @MainActor [weak self] in self?.playing = active }
      }
      progress = nativePlayer.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
      ) { [weak self] time in
        let seconds = time.seconds
        Task { @MainActor [weak self] in
          guard let self, seconds.isFinite, seconds >= 0 else { return }
          self.elapsed = seconds
          #if DEBUG
            if self.nativePlayer.currentItem?.status == .readyToPlay {
              self.diagnostic =
                "ready intent \(self.intent.wantsPlayback), rate \(self.nativePlayer.rate), control \(self.nativePlayer.timeControlStatus.rawValue), time \(Int(seconds))"
            }
          #endif
        }
      }
    }

    func load(videoId: String) {
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
          let source = try await YouTubeAudio().resolve(videoID: videoId)
          #if DEBUG
            diagnostic = "source bytes \(source.byteCount ?? 0)"
          #endif
          try Task.checkCancellation()
          guard intent.revision == expected else { return }
          durationSeconds = source.duration
          let loader = AudioRangeLoader(source: source)
          rangeLoader = loader
          let asset = loader.asset()
          let item = AVPlayerItem(asset: asset)
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
                if self.intent.wantsPlayback { self.play() }
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

    func play() {
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
      intent.pause()
      nativePlayer.pause()
      playing = false
    }
    func seek(to time: CMTime) {
      guard time.seconds.isFinite else { return }
      let value = max(0, min(durationSeconds > 0 ? durationSeconds : time.seconds, time.seconds))
      nativePlayer.seek(to: CMTime(seconds: value, preferredTimescale: 600))
    }
    func setVolume(_ value: Double) {
      volume = min(100, max(0, value))
      nativePlayer.volume = Float(volume / 100)
    }
    func currentTime() -> CMTime { nativePlayer.currentTime() }
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

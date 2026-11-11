#if os(iOS)
  import AVKit
  import SwiftUI
  import Combine
  @preconcurrency import GoogleCast

  @MainActor
  final class CastPlayback: NSObject, @preconcurrency GCKSessionManagerListener {
    static func configure() {
      guard !GCKCastContext.isSharedInstanceInitialized() else { return }
      let options = GCKCastOptions(
        discoveryCriteria: GCKDiscoveryCriteria(
          applicationID: kGCKDefaultMediaReceiverApplicationID))
      GCKCastContext.setSharedInstanceWith(options)
    }
    private weak var player: PlaybackPlayer?
    private let relay = CastAudioRelay()
    private var task: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var routeChanges: AnyCancellable?
    private var resumeOnAirPlay = false
    private var revision = UUID()
    private var wantsPlayback = false
    private var accountOnly = false
    private var loaded = false
    private var loadedURL: String?
    private var cutoff = 0.0
    private var endingSession = false
    var connected: Bool {
      !endingSession && GCKCastContext.sharedInstance().sessionManager.currentCastSession != nil
    }
    private var client: GCKRemoteMediaClient? {
      GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
    }
    init(player: PlaybackPlayer) {
      Self.configure()
      self.player = player
      super.init()
      GCKCastContext.sharedInstance().sessionManager.add(self)
      routeChanges = NotificationCenter.default.publisher(
        for: AVAudioSession.routeChangeNotification
      )
      .receive(on: DispatchQueue.main).sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.connected,
            AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: {
              $0.portType == .airPlay
            })
          else { return }
          self.resumeOnAirPlay = self.wantsPlayback
          GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        }
      }
      timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink {
        [weak self] _ in
        MainActor.assumeIsolated { self?.update() }
      }
    }
    func load(id: String, position: Double, accountOnly: Bool) {
      guard let player else { return }
      task?.cancel()
      relay.stop()
      revision = UUID()
      let expected = revision
      self.accountOnly = accountOnly
      loaded = false
      wantsPlayback = true
      player.prepareForCasting()
      player.videoId = id
      player.elapsed = position
      player.playbackError = nil
      player.isLoading = true
      player.playing = false
      task = Task { [weak self, weak player] in
        guard let self, let player else { return }
        do {
          let local = player.localFileProvider(id)
          let source =
            local == nil
            ? try await YouTubeAudio().resolve(
              videoID: id, session: player.accountProvider(),
              quality: AudioPreferences.shared.currentQuality, accountOnly: accountOnly) : nil
          try Task.checkCancellation()
          guard self.revision == expected, self.connected else { return }
          let url = try await self.relay.start(source: source, file: local)
          try Task.checkCancellation()
          guard self.revision == expected, let client = self.client else { return }
          let song = AppleAppSession.shared.music.current
          let metadata = GCKMediaMetadata(metadataType: .musicTrack)
          metadata.setString(song?.title ?? "NoteNarrate", forKey: kGCKMetadataKeyTitle)
          metadata.setString(song?.artist ?? "", forKey: kGCKMetadataKeyArtist)
          if let artwork = song?.artwork {
            metadata.addImage(GCKImage(url: artwork, width: 512, height: 512))
          }
          let media = GCKMediaInformationBuilder(contentURL: url)
          media.contentID = url.absoluteString
          media.contentType = "audio/mp4"
          media.streamType = .buffered
          if let local {
            let duration = try await AVURLAsset(url: local).load(.duration).seconds
            cutoff = duration.isFinite ? max(0, duration) : 0
          } else {
            cutoff = source?.duration ?? 0
          }
          media.metadata = metadata
          media.streamDuration = cutoff
          let load = GCKMediaLoadRequestDataBuilder()
          load.mediaInformation = media.build()
          load.startTime = position
          load.autoplay = NSNumber(value: self.wantsPlayback)
          client.loadMedia(with: load.build())
          self.loadedURL = url.absoluteString
          self.loaded = true
          try await Task.sleep(for: .seconds(25))
          if self.revision == expected, player.isLoading {
            self.loaded = false
            self.relay.stop()
            player.isLoading = false
            player.playbackError = "Chromecast non risponde. Verifica la rete Wi-Fi e riprova."
          }
        } catch {
          guard self.revision == expected, !Task.isCancelled else { return }
          self.relay.stop()
          player.isLoading = false
          player.playing = false
          player.playbackError =
            "Chromecast: impossibile trasmettere il brano. Verifica che i dispositivi siano sulla stessa rete Wi-Fi e riprova."
        }
      }
    }
    func play() {
      wantsPlayback = true
      if !loaded, let player {
        load(id: player.videoId, position: player.elapsed, accountOnly: accountOnly)
      } else {
        client?.play()
      }
    }
    func pause() {
      wantsPlayback = false
      client?.pause()
    }
    func seek(_ seconds: Double) {
      let options = GCKMediaSeekOptions()
      options.interval = max(0, cutoff > 0 ? min(cutoff, seconds) : seconds)
      client?.seek(with: options)
    }
    func volume(_ value: Double) {
      GCKCastContext.sharedInstance().sessionManager.currentCastSession?.setDeviceVolume(
        Float(value / 100))
    }
    func clear() {
      task?.cancel()
      revision = UUID()
      loaded = false
      wantsPlayback = false
      loadedURL = nil
      relay.stop()
      if !endingSession { client?.stop() }
    }
    private func update() {
      guard connected, loaded, let player, let client, let status = client.mediaStatus,
        (status.mediaInformation?.contentURL?.absoluteString ?? status.mediaInformation?.contentID)
          == loadedURL
      else { return }
      player.elapsed = max(0, client.approximateStreamPosition())
      let remoteDuration = status.mediaInformation?.streamDuration ?? 0
      player.durationSeconds =
        cutoff > 0 ? (remoteDuration > 0 ? min(cutoff, remoteDuration) : cutoff) : remoteDuration
      if cutoff > 0, player.elapsed >= cutoff, status.playerState == .playing {
        loaded = false
        client.stop()
        relay.stop()
        player.onEnded?()
        return
      }
      player.isLoading = status.playerState == .buffering || status.playerState == .loading
      if status.playerState == .playing || status.playerState == .paused {
        player.syncCastPlayback(playing: status.playerState == .playing)
      } else {
        player.playing = false
      }
      if status.playerState == .idle {
        if status.idleReason == .finished {
          loaded = false
          relay.stop()
          player.onEnded?()
        } else if status.idleReason == .error {
          loaded = false
          relay.stop()
          player.isLoading = false
          player.playbackError =
            "Chromecast non riesce a leggere l’audio. Riprova o seleziona AirPlay."
        }
      }
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
      transfer()
    }
    func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
      transfer()
    }
    private func transfer() {
      guard let player, !player.videoId.isEmpty else { return }
      let wasPlaying = player.playing
      load(id: player.videoId, position: player.elapsed, accountOnly: player.castAccountOnly)
      wantsPlayback = wasPlaying
    }
    func sessionManager(
      _ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?
    ) {
      guard let player else { return }
      endingSession = true
      defer { endingSession = false }
      let position = player.elapsed
      let id = player.videoId
      let resume = resumeOnAirPlay
      resumeOnAirPlay = false
      task?.cancel()
      revision = UUID()
      loaded = false
      relay.stop()
      // Disconnect retains position without unexpectedly starting the phone speaker.
      player.restore(
        videoID: id, position: position, duration: player.durationSeconds, accountOnly: accountOnly)
      if resume { player.play() }
    }
  }

  struct AudioOutputButtons: View {
    var body: some View {
      HStack(spacing: 12) {
        AirPlayButton().frame(width: 44, height: 44).accessibilityLabel("AirPlay e uscita audio")
        ChromecastButton().frame(width: 44, height: 44).accessibilityLabel("Chromecast")
      }
    }
  }
  private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
      let view = AVRoutePickerView()
      view.tintColor = .cyan
      view.activeTintColor = .cyan
      view.prioritizesVideoDevices = false
      return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
  }
  private struct ChromecastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
      CastPlayback.configure()
      let button = GCKUICastButton(frame: .zero)
      button.tintColor = .cyan
      return button
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
  }
#endif

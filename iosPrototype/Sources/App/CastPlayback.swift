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
      // Google's physical-button integration is unsupported on modern iOS.
      // Use the public audio-session observation below, avoiding double commands.
      options.physicalVolumeButtonsWillControlDeviceVolume = false
      GCKCastContext.setSharedInstanceWith(options)
    }
    private weak var player: PlaybackPlayer?
    private let relay = CastAudioRelay()
    private var task: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var routeChanges: AnyCancellable?
    private var volumeChanges: AnyCancellable?
    private var volumeLifecycle: AnyCancellable?
    private var volumeRevision = UUID()
    private var volumeControl = CastVolumeControl()
    private var localPlayerVolume: Double?
    private let lockScreen = CastNowPlaying()
    var hasRemoteNowPlaying: Bool { lockScreen.suppressesLegacy }
    var systemCardStatus: String { lockScreen.diagnostic }
    func restoreSystemCard() { client?.requestStatus(); lockScreen.refresh(); update() }
    var diagnosticReport: String {
      let bundle = Bundle.main.infoDictionary ?? [:]
      let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession
      let sdkState = session.map { String($0.connectionState.rawValue) } ?? "nessuna sessione"
      let mediaState = client?.mediaStatus.map { String($0.playerState.rawValue) } ?? "nessun brano"
      return "Build: \(bundle["CFBundleShortVersionString"] as? String ?? "?") (\(bundle["CFBundleVersion"] as? String ?? "?"))"
        + "\nChromecast collegato: \(connected)"
        + "\nSessione SDK: \(sdkState)\nStato ricevitore: \(mediaState)"
        + "\nScheda registrata: \(lockScreen.published)\nScheda principale: \(lockScreen.isPrimary)"
        + "\nScheda di sistema: \(lockScreen.diagnostic)"
        + "\nComandi Chromecast: \(CastControlDiagnostics.latest)"
        + "\nNarrazione attiva: \(AppleAppSession.shared.music.reading)"
        + "\niOS: \(UIDevice.current.systemVersion)\nRete: \(AudioPreferences.shared.networkDiagnostic)"
        + "\n\nCoda Chromecast:\n" + queueEvents.joined(separator: "\n")
    }
    private var queueEvents: [String] = []
    private var lastReceiverState: Int?
    private func recordQueue(_ event: String) {
      let state = UIApplication.shared.applicationState == .active ? "attiva" : "background"
      queueEvents.append(Date().formatted(date: .omitted, time: .standard) + " · app " + state + " · " + event)
      if queueEvents.count > 24 { queueEvents.removeFirst(queueEvents.count - 24) }
    }
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
          self.stopVolumeObservation()
          self.resumeOnAirPlay = self.wantsPlayback
          GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        }
      }
      volumeLifecycle = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        .merge(with: NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification))
        .receive(on: DispatchQueue.main).sink { [weak self] notification in
          MainActor.assumeIsolated {
            if notification.name == UIApplication.didBecomeActiveNotification {
              self?.recordQueue("ritorno in primo piano")
              self?.startVolumeObservation()
              self?.lockScreen.refresh()
              self?.update()
            } else { self?.recordQueue("uscita dal primo piano"); self?.stopVolumeObservation() }
          }
        }
      timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink {
        [weak self] _ in
        MainActor.assumeIsolated { self?.update() }
      }
      startVolumeObservation()
    }
    func load(id: String, position: Double, accountOnly: Bool) {
      guard let player else { return }
      recordQueue("richiesto caricamento brano")
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
          metadata.setString(id, forKey: "notenarrateTrackID")
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
          self.recordQueue("LOAD inviato al ricevitore")
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
      CastControlDiagnostics.record("PAUSE", "inoltrato al Cast SDK · " +
        (UIApplication.shared.applicationState == .active ? "app attiva" : "app in background"))
      client?.pause()
    }
    func seek(_ seconds: Double) {
      let options = GCKMediaSeekOptions()
      options.interval = max(0, cutoff > 0 ? min(cutoff, seconds) : seconds)
      client?.seek(with: options)
    }
    func volume(_ value: Double) {
      startVolumeObservation()
      guard let target = volumeControl.request(value / 100, now: ProcessInfo.processInfo.systemUptime)
      else { return }
      sendVolume(target)
    }

    private func startVolumeObservation() {
      guard volumeChanges == nil, connected, UIApplication.shared.applicationState == .active,
        !AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { $0.portType == .airPlay }),
        let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession,
        session.connectionState == .connected, session.traits?.isFixedVolume() != true
      else { return }
      guard (try? AppleAudioSession.activate()) != nil else { return }
      if localPlayerVolume == nil { localPlayerVolume = player?.volume }
      let audio = AVAudioSession.sharedInstance()
      volumeControl.begin(phone: Double(audio.outputVolume), receiver: session.currentDeviceMuted ? 0 : Double(session.currentDeviceVolume))
      publishVolume()
      volumeRevision = UUID()
      let expected = volumeRevision
      let route = audio.currentRoute.outputs.map(\.uid)
      volumeChanges = audio.publisher(for: \.outputVolume, options: [.new])
        .receive(on: DispatchQueue.main).sink { [weak self] value in
          MainActor.assumeIsolated {
            guard let self, self.volumeRevision == expected, self.connected,
              UIApplication.shared.applicationState == .active,
              GCKCastContext.sharedInstance().sessionManager.currentCastSession?.connectionState == .connected
            else { return }
            guard AVAudioSession.sharedInstance().currentRoute.outputs.map(\.uid) == route else {
              self.stopVolumeObservation()
              return
            }
            if let target = self.volumeControl.phoneChanged(to: Double(value), now: ProcessInfo.processInfo.systemUptime) {
              self.sendVolume(target)
            }
            self.publishVolume()
          }
        }
    }

    private func stopVolumeObservation() {
      guard volumeChanges != nil || volumeControl.phoneVolume != nil else { return }
      volumeRevision = UUID()
      volumeChanges = nil
      volumeControl.end()
      if player?.castVolumeAtLimit == true { player?.castVolumeAtLimit = false }
    }

    private func sendVolume(_ target: Double) {
      guard connected, let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession,
        session.connectionState == .connected, session.traits?.isFixedVolume() != true else { return }
      if target > 0, session.currentDeviceMuted { session.setDeviceMuted(false) }
      session.setDeviceVolume(Float(target))
      publishVolume()
    }

    private func publishVolume() {
      guard let player else { return }
      let value = volumeControl.receiverVolume * 100
      if abs(player.volume - value) > 0.01 { player.volume = value }
      if player.castVolumeAtLimit != volumeControl.phoneAtLimit {
        player.castVolumeAtLimit = volumeControl.phoneAtLimit
      }
    }
    func clear() {
      lockScreen.end()
      task?.cancel()
      revision = UUID()
      loaded = false
      wantsPlayback = false
      loadedURL = nil
      relay.stop()
      if !endingSession { client?.stop() }
    }
    private func update() {
      if player?.castDiagnostic != lockScreen.diagnostic { player?.castDiagnostic = lockScreen.diagnostic }
      if GCKCastContext.sharedInstance().sessionManager.currentCastSession?.connectionState != .connected {
        stopVolumeObservation()
      }
      startVolumeObservation()
      if volumeChanges != nil,
        let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession {
        volumeControl.receive(session.currentDeviceMuted ? 0 : Double(session.currentDeviceVolume), now: ProcessInfo.processInfo.systemUptime)
        publishVolume()
      }
      guard connected, loaded, let player, let client, let status = client.mediaStatus,
        (status.mediaInformation?.contentURL?.absoluteString ?? status.mediaInformation?.contentID)
          == loadedURL
      else { return }
      if lastReceiverState != status.playerState.rawValue {
        lastReceiverState = status.playerState.rawValue
        recordQueue("stato ricevitore \(status.playerState.rawValue), motivo fine \(status.idleReason.rawValue)")
      }
      player.elapsed = max(0, client.approximateStreamPosition())
      let remoteDuration = status.mediaInformation?.streamDuration ?? 0
      player.durationSeconds =
        cutoff > 0 ? (remoteDuration > 0 ? min(cutoff, remoteDuration) : cutoff) : remoteDuration
      if let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession,
        let receiverSession = session.sessionID, let host = session.device.networkAddress.ipAddress,
        let song = AppleAppSession.shared.music.current {
        lockScreen.publish(CastRemoteState(
          id: session.device.uniqueID + ":" + receiverSession,
          receiverSession: receiverSession, host: host, port: session.device.servicePort,
          certificate: Data(), deviceName: session.device.friendlyName ?? "Chromecast",
          trackID: song.id, title: song.title, artist: song.artist, artwork: song.artwork,
          duration: player.durationSeconds, position: player.elapsed, timestamp: Date(),
          playback: status.playerState == .playing ? "PLAYING" : status.playerState == .paused ? "PAUSED" : status.playerState == .buffering || status.playerState == .loading ? "BUFFERING" : "IDLE",
          volume: session.currentDeviceMuted ? 0 : Double(session.currentDeviceVolume),
          mediaSessionID: status.mediaSessionID), allowPromotion: !AppleAppSession.shared.music.reading)
      }
      if cutoff > 0, player.elapsed >= cutoff, status.playerState == .playing {
        loaded = false
        client.stop()
        relay.stop()
        recordQueue("durata raggiunta: richiesto avanzamento coda")
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
        lockScreen.end()
        if status.idleReason == .finished {
          loaded = false
          relay.stop()
          recordQueue("fine ricevitore: richiesto avanzamento coda")
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
      // The receiver may have advanced while the app was suspended. Keep the
      // existing stream and its clock instead of loading the old phone position.
      if loaded, let status = client?.mediaStatus,
        (status.mediaInformation?.contentURL?.absoluteString ?? status.mediaInformation?.contentID) == loadedURL {
        stopVolumeObservation(); startVolumeObservation(); update()
        return
      }
      transfer()
    }
    private func transfer() {
      stopVolumeObservation()
      startVolumeObservation()
      guard let player, !player.videoId.isEmpty else { return }
      let wasPlaying = player.playing
      load(id: player.videoId, position: player.elapsed, accountOnly: player.castAccountOnly)
      wantsPlayback = wasPlaying
    }
    func sessionManager(
      _ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?
    ) {
      lockScreen.end()
      stopVolumeObservation()
      guard let player else { return }
      endingSession = true
      defer { endingSession = false }
      if let localPlayerVolume { player.setVolume(localPlayerVolume) }
      localPlayerVolume = nil
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

#if os(iOS)
  struct CastDiagnosticsScreen: View {
    @ObservedObject var player: PlaybackPlayer
    var body: some View {
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        List {
          Section("Collegamento") {
            LabeledContent("Chromecast", value: player.cast.connected ? "Collegato" : "Non collegato")
            Text(player.cast.systemCardStatus).textSelection(.enabled)
              .accessibilityIdentifier("cast-system-card-status")
            Button("Ripristina controlli") { player.cast.restoreSystemCard() }
              .disabled(!player.cast.connected).accessibilityIdentifier("restore-cast-controls")
          }
          Section("Ultimo comando") {
            Text(CastControlDiagnostics.latest).textSelection(.enabled)
              .accessibilityIdentifier("cast-command-status")
          }
          Section("Report") {
            Text(player.cast.diagnosticReport).font(.caption).textSelection(.enabled)
              .accessibilityIdentifier("cast-diagnostic-report")
            Button("Copia diagnostica") { PlatformClipboard.copy(player.cast.diagnosticReport) }
              .accessibilityIdentifier("copy-cast-diagnostics")
            ShareLink(item: player.cast.diagnosticReport) {
              Label("Condividi diagnostica", systemImage: "square.and.arrow.up")
            }
          }
        }
      }.navigationTitle("Diagnostica Chromecast").inlineNavigationTitle()
    }
  }
#endif

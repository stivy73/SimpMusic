#if os(iOS)
  import AVFoundation
  import Combine
  import MediaPlayer
  import UIKit
  #if DEBUG
    import CoreImage
  #endif

  /// iPhone and CarPlay share one playback/interpretation session, including cold car launch.
  @MainActor
  final class AppleAppSession {
    static let shared = AppleAppSession()
    let music = MusicModel()
    let library = LibraryModel()
    let home = HomeModel()
    private(set) var widgets: WidgetBridge!
    private(set) var releaseNotifications: ReleaseNotifications!
    private(set) var passengers: PassengerBridge!
    private var media: AppleMediaSession!
    private var watch: WatchPhoneBridge!
    private var radioSubscription: AnyCancellable?
    private var favoritesMigration: Task<Void, Never>?
    private init() {
      music.player.accountProvider = { [weak library] in library?.session }
      music.player.accountRevisionProvider = { [weak library] in library?.accountRevision }
      media = AppleMediaSession(model: music)
      widgets = WidgetBridge(music: music, library: library)
      releaseNotifications = ReleaseNotifications(music: music, library: library)
      watch = WatchPhoneBridge(music: music)
      passengers = PassengerBridge(music: music)
      radioSubscription = library.$session.sink { [weak self] session in
        guard let self else { return }
        self.music.configureRadio(session: session)
        self.music.searchResults.configure(session: session)
        self.favoritesMigration?.cancel()
        if let session {
          self.favoritesMigration = Task { [weak self] in
            guard let self else { return }
            await self.music.migrateFavorites(to: self.library, account: session)
          }
        }
      }
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--diagnose-audio-timing") {
          Task { await diagnoseAudioTiming() }
        }
      #endif
    }
    func showPassengerQR(_ invitation: PassengerInvitation?) {
      media.showPassengerQR(invitation)
    }
    #if DEBUG
      func verifyPassengerQRArtwork() async -> String {
        for _ in 0..<100 where music.current == nil || music.player.isLoading {
          try? await Task.sleep(for: .milliseconds(100))
        }
        return media.verifyPassengerQRArtwork()
      }
      private func diagnoseAudioTiming() async {
        var report: [String: String] = [:]
        do {
          report["accountAvailable"] = String(library.session != nil)
          let items = try await HomeDiscovery(session: library.session).search(
            query: "Fleetwood Mac Dreams 2004 Remaster", filter: .songs)
          guard let song = items.first else { throw AudioPlaybackError.unavailable }
          report["catalogDuration"] = String(song.durationSeconds ?? 0)
          let source = try await YouTubeAudio().resolve(videoID: song.mediaId, session: library.session)
          report["sourceDuration"] = String(source.duration)
          report["authenticated"] = String(source.authenticated)
          report["hls"] = String(source.isHLS)
          let loader = AudioRangeLoader(source: source)
          try await loader.prepare()
          let asset = loader.asset()
          report["assetDuration"] = String(try await asset.load(.duration).seconds)
          for (index, track) in try await asset.loadTracks(withMediaType: .audio).enumerated() {
            report["audioEnd\(index)"] = String(try await track.load(.timeRange).end.seconds)
            for (n, segment) in try await track.load(.segments).enumerated() {
              report["segment\(index)-\(n)"] = "\(segment.isEmpty):\(segment.timeMapping.target.start.seconds):\(segment.timeMapping.target.end.seconds)"
            }
          }
        } catch { report["error"] = AudioResolutionFailure.detail(error) }
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
          .appendingPathComponent("NoteNarrate-AudioTiming.json")
        try? JSONEncoder().encode(report).write(to: path, options: .atomic)
      }
    #endif
  }

  @MainActor
  final class AppleMediaSession {
    private let model: MusicModel
    private var subscriptions = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var artworkID: String?
    private var artworkRevision = UUID()
    private var passengerInvitation: PassengerInvitation?
    private var passengerArtwork: MPMediaItemArtwork?

    func showPassengerQR(_ invitation: PassengerInvitation?) {
      guard passengerInvitation != invitation else { return }
      passengerInvitation = invitation
      passengerArtwork = invitation.flatMap { value in
        PassengerQRCode.image(for: value).map { Self.systemArtwork(UIImage(cgImage: $0)) }
      }
      artworkRevision = UUID()
      update()
    }
    #if DEBUG
      func verifyPassengerQRArtwork() -> String {
        guard model.current != nil else { return "FAIL no track" }
        // Deterministic album cover ensures restoration is checked even before a network image arrives.
        let savedArtwork = artwork
        defer { artwork = savedArtwork; artworkRevision = UUID(); update() }
        let cover = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
          UIColor.systemBlue.setFill()
          context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        artwork = Self.systemArtwork(cover)
        artworkRevision = UUID()
        update()
        let original = (center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)?.image(at: CGSize(width: 600, height: 600))?.pngData()
        let title = center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String
        let playing = model.player.playing
        let invitation = PassengerInvitation()
        showPassengerQR(invitation)
        defer { showPassengerQR(nil) }
        guard let image = (center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)?.image(at: CGSize(width: 600, height: 600)), let cg = image.cgImage else { return "FAIL missing QR" }
        // Software decoding also works in Simulator without the Vision neural-engine backend.
        let detector = CIDetector(
          ofType: CIDetectorTypeQRCode,
          context: CIContext(options: [.useSoftwareRenderer: true]),
          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let payload = (detector?.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString
        guard payload == invitation.text, cg.width == cg.height,
          title == center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String,
          playing == model.player.playing else { return "FAIL QR or playback changed" }
        showPassengerQR(nil)
        let restored = (center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)?.image(at: CGSize(width: 600, height: 600))?.pngData()
        return original == restored ? "PASS square QR decodes, playback unchanged, artwork restored" : "FAIL cover not restored"
      }
    #endif
    private var publication = NowPlayingPublication()
    private let center = MPNowPlayingInfoCenter.default()

    init(model: MusicModel) {
      self.model = model
      let commands = MPRemoteCommandCenter.shared()
      commands.playCommand.addTarget { @Sendable [weak model] _ in
        Task { @MainActor in
          guard let model else { return }
          if model.reading || model.busyMeaning { model.stopMeaning(resume: false) }
          model.player.play()
        }
        return .success
      }
      commands.pauseCommand.addTarget { @Sendable [weak model] _ in
        Task { @MainActor in
          model?.stopMeaning(resume: false)
          model?.player.pause()
        }
        return .success
      }
      commands.togglePlayPauseCommand.addTarget { @Sendable [weak model] _ in
        Task { @MainActor in
          guard let model else { return }
          if model.reading || model.busyMeaning {
            model.stopMeaning(resume: true)
          } else if model.player.wantsPlayback {
            model.player.pause()
          } else {
            model.player.play()
          }
        }
        return .success
      }
      commands.stopCommand.addTarget { @Sendable [weak model] _ in
        Task { @MainActor in
          model?.stopMeaning(resume: false)
          model?.player.pause()
        }
        return .success
      }
      commands.nextTrackCommand.addTarget { @Sendable [weak model] _ in
        Task { @MainActor in model?.nextSong() }
        return .success
      }
      commands.previousTrackCommand.addTarget { @Sendable [weak model] _ in
        Task { @MainActor in model?.previousSong() }
        return .success
      }
      commands.changeShuffleModeCommand.addTarget { @Sendable [weak model] event in
        guard let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
        let enabled = event.shuffleType != .off
        Task { @MainActor in model?.setShuffle(enabled) }
        return .success
      }
      commands.changeRepeatModeCommand.addTarget { @Sendable [weak model] event in
        guard let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
        let mode: PlaybackRepeatMode =
          event.repeatType == .one ? .one : event.repeatType == .all ? .all : .off
        Task { @MainActor in model?.repeatMode = mode }
        return .success
      }
      commands.changePlaybackPositionCommand.addTarget { @Sendable [weak model] event in
        guard let value = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime,
          value.isFinite, value >= 0
        else { return .commandFailed }
        Task { @MainActor in
          model?.player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
        }
        return .success
      }
      model.$current.sink { [weak self] song in self?.loadArtwork(song) }.store(in: &subscriptions)
      model.objectWillChange.merge(with: model.player.objectWillChange)
        .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
      NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
        .receive(on: RunLoop.main)
        .sink { [weak self] note in
          let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
          let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
          Task { @MainActor [weak self] in
            guard let self else { return }
            if type == AVAudioSession.InterruptionType.began.rawValue {
              if self.model.busyMeaning || self.model.reading {
                self.model.stopMeaning(resume: false, reason: "Voce interrotta dal sistema audio")
                self.model.showMeaning = false
              }
              self.model.player.interruptionBegan()
            } else if type == AVAudioSession.InterruptionType.ended.rawValue {
              self.model.player.interruptionEnded(
                shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(
                  .shouldResume))
            }
          }
        }.store(in: &subscriptions)
      NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
        .receive(on: RunLoop.main)
        .sink { [weak self] note in
          let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
          guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else {
            return
          }
          Task { @MainActor [weak self] in
            self?.model.stopMeaning(
              resume: false, reason: "Voce interrotta: uscita audio scollegata")
            self?.model.player.pause()
          }
        }.store(in: &subscriptions)
      NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
          Task { @MainActor [weak self] in
            guard let self else { return }
            self.model.stopMeaning(
              resume: false, reason: "Voce interrotta: servizi audio riavviati")
            self.model.player.pause()
            self.model.player.playbackError =
              "Il sistema audio è stato riavviato. Seleziona nuovamente il brano."
          }
        }.store(in: &subscriptions)
    }

    private func loadArtwork(_ song: Song?) {
      artworkTask?.cancel()
      artwork = nil
      artworkID = song?.id
      artworkRevision = UUID()
      update()
      guard let song else {
        showPassengerQR(nil)
        return
      }
      artworkTask = Task {
        guard
          let image = await AppleArtworkStore.shared.image(primary: song.artwork, videoID: song.id),
          !Task.isCancelled, artworkID == song.id
        else { return }
        artwork = Self.systemArtwork(image)
        artworkRevision = UUID()
        update()
      }
    }

    // MediaPlayer invokes the image provider on its own queue, not the main actor.
    nonisolated private static func systemArtwork(_ image: UIImage) -> MPMediaItemArtwork {
      MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func update() {
      let commands = MPRemoteCommandCenter.shared()
      commands.changeShuffleModeCommand.currentShuffleType = model.shuffleEnabled ? .items : .off
      commands.changeRepeatModeCommand.currentRepeatType =
        model.repeatMode == .one ? .one : model.repeatMode == .all ? .all : .off

      let available = model.current != nil
      commands.changeShuffleModeCommand.isEnabled = available
      commands.changeRepeatModeCommand.isEnabled = available
      commands.playCommand.isEnabled = available
      commands.pauseCommand.isEnabled = available
      commands.togglePlayPauseCommand.isEnabled = available
      commands.stopCommand.isEnabled = available
      commands.nextTrackCommand.isEnabled = model.hasNext
      commands.previousTrackCommand.isEnabled = model.hasPrevious || model.player.elapsed > 3
      commands.changePlaybackPositionCommand.isEnabled =
        available && model.player.durationSeconds > 0
        && !model.player.isLoading && !model.busyMeaning && !model.reading
      guard let song = model.current else {
        center.nowPlayingInfo = nil
        publication.reset()
        return
      }
      if model.player.cast.hasRemoteNowPlaying, !model.reading {
        if center.nowPlayingInfo != nil { center.nowPlayingInfo = nil }
        publication.reset()
        return
      }
      let live = model.reading
      let contentID = live ? song.id + ":narration:" + model.meaningRequestID.uuidString : song.id
      let rate = model.player.playing || live ? 1.0 : 0.0
      let duration = model.player.durationSeconds.isFinite ? max(0, model.player.durationSeconds) : 0
      let time = model.player.currentTime().seconds
      let position = time.isFinite ? max(0, duration > 0 ? min(time, duration) : time) : 0
      let key = [contentID, song.title, song.artist, artworkRevision.uuidString].joined(separator: "\n")
      guard publication.shouldPublish(
        key: key, duration: live ? 0 : duration, position: position,
        rate: rate, live: live, now: ProcessInfo.processInfo.systemUptime)
      else { return }
      var info: [String: Any] = [
        MPMediaItemPropertyTitle: live ? "Significato della canzone" : song.title,
        MPMediaItemPropertyArtist: song.artist,
        MPNowPlayingInfoPropertyIsLiveStream: live,
        MPNowPlayingInfoPropertyPlaybackRate: rate,
        MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        MPNowPlayingInfoPropertyExternalContentIdentifier: contentID,
      ]
      // Speech has no seekable music timeline. Give it a distinct identity, then
      // restore the complete finite music clock when it finishes or is cancelled.
      if !live {
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
      }
      if let displayArtwork = passengerArtwork ?? artwork { info[MPMediaItemPropertyArtwork] = displayArtwork }
      center.nowPlayingInfo = info
      #if DEBUG
        let timeline = "\(live ? 0 : duration):\(live ? 0 : position):\(rate):\(live)"
        if model.systemNowPlayingTimeline != timeline { model.systemNowPlayingTimeline = timeline }
        let narrationRate =
          model.reading && (info[MPNowPlayingInfoPropertyPlaybackRate] as? Double) == 1
        if model.systemNarrationActive != narrationRate {
          model.systemNarrationActive = narrationRate
        }
        let image = (center.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)?
          .image(at: CGSize(width: 100, height: 100))
        if model.systemArtworkAvailable != (image != nil) {
          model.systemArtworkAvailable = image != nil
        }
      #endif
    }
  }
#endif

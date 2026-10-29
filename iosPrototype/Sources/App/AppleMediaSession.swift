#if os(iOS)
  import AVFoundation
  import Combine
  import MediaPlayer
  import UIKit

  /// iPhone and CarPlay share one playback/interpretation session, including cold car launch.
  @MainActor
  final class AppleAppSession {
    static let shared = AppleAppSession()
    let music = MusicModel()
    let library = LibraryModel()
    let home = HomeModel()
    private(set) var widgets: WidgetBridge!
    private(set) var releaseNotifications: ReleaseNotifications!
    private var media: AppleMediaSession!
    private var radioSubscription: AnyCancellable?
    private var favoritesMigration: Task<Void, Never>?
    private init() {
      music.player.accountProvider = { [weak library] in library?.session }
      media = AppleMediaSession(model: music)
      widgets = WidgetBridge(music: music, library: library)
      releaseNotifications = ReleaseNotifications(music: music, library: library)
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
    #if DEBUG
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
      guard let song else { return }
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
      if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
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

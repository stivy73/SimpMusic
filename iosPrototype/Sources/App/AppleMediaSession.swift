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
    private var media: AppleMediaSession!
    private var radioSubscription: AnyCancellable?
    private init() {
      music.player.accountProvider = { [weak library] in library?.session }
      media = AppleMediaSession(model: music)
      radioSubscription = library.$session.sink { [weak music] session in
        music?.configureRadio(session: session)
        music?.searchResults.configure(session: session)
      }
    }
  }

  @MainActor
  final class AppleMediaSession {
    private let model: MusicModel
    private var subscriptions = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var artworkID: String?
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
      update()
      guard let song else { return }
      artworkTask = Task {
        guard
          let image = await AppleArtworkStore.shared.image(primary: song.artwork, videoID: song.id),
          !Task.isCancelled, artworkID == song.id
        else { return }
        artwork = Self.systemArtwork(image)
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
        return
      }
      var info: [String: Any] = [
        MPMediaItemPropertyTitle: model.reading ? "Significato della canzone" : song.title,
        MPMediaItemPropertyArtist: song.artist,
        MPMediaItemPropertyPlaybackDuration: model.reading ? 0 : model.player.durationSeconds,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: model.reading ? 0 : model.player.elapsed,
        MPNowPlayingInfoPropertyPlaybackRate: model.player.playing || model.reading ? 1.0 : 0.0,
        MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        MPNowPlayingInfoPropertyExternalContentIdentifier: song.id,
      ]
      if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
      center.nowPlayingInfo = info
      #if DEBUG
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

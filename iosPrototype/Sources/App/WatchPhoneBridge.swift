#if os(iOS)
  import Combine
  import Foundation
  import UIKit
  import WatchConnectivity

  /// Uses the same session as iPhone, Siri and CarPlay. The watch never receives credentials.
  @MainActor final class WatchPhoneBridge {
    private let music: MusicModel
    private let link = WatchSessionLink()
    private var subscriptions = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var artworkID: String?
    private var artwork: Data?
    init(music: MusicModel) {
      self.music = music
      link.onAvailabilityChanged = { [weak self] in self?.loadArtwork() }
      link.onCommand = { [weak self] command in
        guard let self else { throw WatchCommandError.malformed }
        try command.validate(against: self.snapshot())
        switch command.action {
        case .refresh: break
        case .play: try SiriPlaybackCommands.perform(.resume)
        case .pause: try SiriPlaybackCommands.perform(.pause)
        case .next: try SiriPlaybackCommands.perform(.next)
        case .explain: try SiriPlaybackCommands.perform(.explain)
        case .radio: try SiriPlaybackCommands.perform(.radio)
        case .previous:
          self.music.stopMeaning(resume: false)
          self.music.previousSong()
        case .stopExplanation: self.music.stopMeaning(resume: true)
        case .playOccurrence:
          guard let id = command.occurrenceID.flatMap(UUID.init(uuidString:)) else {
            throw WatchCommandError.stale
          }
          self.music.stopMeaning(resume: false)
          self.music.playQueueOccurrence(id)
        }
        let value = self.snapshot()
        self.link.publish(value)
        return value
      }
      music.objectWillChange.throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
        .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
      music.player.objectWillChange.throttle(
        for: .seconds(3), scheduler: RunLoop.main, latest: true
      )
      .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
      music.player.$playing.removeDuplicates().debounce(
        for: .milliseconds(150), scheduler: RunLoop.main
      )
      .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
      music.$current.receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.loadArtwork() }.store(in: &subscriptions)
      publish()
    }
    private func snapshot() -> WatchSnapshot {
      var value = WatchSnapshot()
      if let song = music.current {
        let occurrence =
          music.queueRows.first { $0.index == music.queueIndex }?.id.uuidString ?? song.id
        value.track = .init(id: occurrence, title: song.title, artist: song.artist)
      }
      value.playing = music.player.playing
      value.loading = music.player.isLoading
      value.narrating = music.reading
      value.preparingMeaning = music.busyMeaning
      value.elapsed = music.player.elapsed
      value.duration = music.player.durationSeconds
      value.meaning = String(music.meaning.prefix(6000))
      value.artwork = music.current?.id == artworkID ? artwork : nil
      value.progress =
        music.meaningError ?? music.player.playbackError
        ?? (music.busyMeaning ? music.meaningProgress : "")
      let rows = music.queueRows
      let currentOffset = rows.firstIndex(where: { $0.index == music.queueIndex }) ?? 0
      let range = WatchSnapshot.queueRange(count: rows.count, currentOffset: currentOffset)
      value.queue = rows[range].map {
        .init(id: $0.id.uuidString, title: $0.song.title, artist: $0.song.artist)
      }
      value.queueTotal = rows.count
      return value
    }
    private func publish() { link.publish(snapshot()) }
    private func loadArtwork() {
      artworkTask?.cancel()
      artwork = nil
      artworkID = music.current?.id
      guard WCSession.isSupported(), WCSession.default.activationState == .activated,
        WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
      else { return }
      guard let song = music.current else {
        publish()
        return
      }
      artworkTask = Task { [weak self] in
        guard
          let image = await AppleArtworkStore.shared.image(primary: song.artwork, videoID: song.id),
          image.size.width > 0, image.size.height > 0,
          !Task.isCancelled, let self, self.music.current?.id == song.id
        else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(
          size: CGSize(width: 140, height: 140), format: format
        ).image { _ in
          let scale = min(140 / image.size.width, 140 / image.size.height)
          let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
          image.draw(
            in: CGRect(
              x: (140 - size.width) / 2, y: (140 - size.height) / 2, width: size.width,
              height: size.height))
        }
        if let data = thumbnail.jpegData(compressionQuality: 0.65), data.count <= 16_000 {
          self.artwork = data
        }
        self.publish()
      }
      publish()
    }
  }
#endif

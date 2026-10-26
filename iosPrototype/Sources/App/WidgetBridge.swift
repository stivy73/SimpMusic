#if os(iOS)
  import Combine
  import UIKit
  import WidgetKit

  @MainActor final class WidgetBridge {
    private let music: MusicModel
    private let library: LibraryModel
    private var subscriptions = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?
    private var artworkID: String?
    private var artworkFile: String?
    private var playlistArt: [String: String] = [:]
    private var playlistTask: Task<Void, Never>?
    private var lastCleanup = Date.distantPast
    init(music: MusicModel, library: LibraryModel) {
      self.music = music
      self.library = library
      music.$current.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadArtwork() }.store(
        in: &subscriptions)
      music.player.objectWillChange
        .throttle(for: .seconds(15), scheduler: RunLoop.main, latest: true)
        .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
      music.player.$playing.removeDuplicates().debounce(
        for: .milliseconds(100), scheduler: RunLoop.main
      )
      .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
      music.listening.objectWillChange.debounce(for: .seconds(2), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.publish() }.store(in: &subscriptions)
      library.objectWillChange.debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          self?.publish()
          self?.loadPlaylistArtwork()
        }.store(in: &subscriptions)
      library.$session.removeDuplicates().sink { [weak self] _ in
        self?.playlistTask?.cancel()
        self?.playlistArt = [:]
        // Wipe the previous account's shared playlists before fetching the new account.
        guard let directory = WidgetSnapshot.directory() else { return }
        try? WidgetSnapshot().write(at: directory)
        WidgetCenter.shared.reloadAllTimelines()
      }.store(in: &subscriptions)
      publish()
    }
    func publish() {
      guard let directory = WidgetSnapshot.directory() else { return }
      let now = Date()
      let calendar = Calendar.current
      let today = music.listening.report(in: calendar.dateInterval(of: .day, for: now))
      let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
      let week = music.listening.report(
        in: DateInterval(start: start, end: now.addingTimeInterval(1)))
      let track = music.current.map {
        WidgetSnapshot.Track(
          id: $0.id, title: $0.title, artist: $0.artist,
          duration: music.player.durationSeconds, elapsed: music.player.elapsed,
          playing: music.player.playing && !music.reading,
          artworkFile: $0.id == artworkID ? artworkFile : nil)
      }
      let playlists =
        library.session == nil
        ? []
        : library.state(.playlists).items.map {
          WidgetSnapshot.Playlist(
            id: $0.mediaId, title: $0.title, subtitle: $0.subtitle,
            artworkFile: playlistArt[$0.mediaId])
        }
      let value = WidgetSnapshot(
        date: now, track: track, playlists: playlists,
        todaySeconds: today.seconds, weekSeconds: week.seconds, weekPlays: week.plays,
        topArtist: week.artists.first?.title)
      try? value.write(at: directory)
      if now.timeIntervalSince(lastCleanup) > 3600 {
        let keep = Set(
          ([value.track?.artworkFile] + value.playlists.map(\.artworkFile)).compactMap { $0 })
        let files =
          (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files
        where file.lastPathComponent.hasPrefix("art-") && file.pathExtension == "jpg"
          && !keep.contains(file.lastPathComponent)
        {
          try? FileManager.default.removeItem(at: file)
        }
        lastCleanup = now
      }
      WidgetCenter.shared.reloadAllTimelines()
    }
    private func loadArtwork() {
      artworkTask?.cancel()
      artworkID = music.current?.id
      artworkFile = nil
      guard let song = music.current, let directory = WidgetSnapshot.directory() else {
        publish()
        return
      }
      artworkTask = Task {
        let image = await AppleArtworkStore.shared.image(primary: song.artwork, videoID: song.id)
        guard !Task.isCancelled, music.current?.id == song.id,
          let data = image?.jpegData(compressionQuality: 0.8)
        else { return }
        let name = "art-" + LocalFiles.key(song.id) + ".jpg"
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
        artworkFile = name
        publish()
      }
      publish()
    }
    private func loadPlaylistArtwork() {
      guard playlistTask == nil, let session = library.session,
        let directory = WidgetSnapshot.directory()
      else { return }
      let items = library.state(.playlists).items.prefix(24).filter {
        playlistArt[$0.mediaId] == nil && $0.artwork != nil
      }
      guard !items.isEmpty else { return }
      playlistTask = Task {
        defer { playlistTask = nil }
        for item in items {
          guard !Task.isCancelled, library.session == session else { return }
          guard
            let image = await AppleArtworkStore.shared.image(primary: item.artwork, videoID: nil),
            let data = image.jpegData(compressionQuality: 0.75)
          else { continue }
          guard !Task.isCancelled, library.session == session else { return }
          let name = "art-" + LocalFiles.key(item.id) + ".jpg"
          try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
          playlistArt[item.mediaId] = name
        }
        publish()
      }
    }
  }
#endif

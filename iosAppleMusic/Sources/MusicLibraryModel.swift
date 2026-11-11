@preconcurrency import MusicKit
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class MusicLibraryModel: ObservableObject {
  @Published var authorization = MusicAuthorization.currentStatus
  @Published var canPlayCatalog = false
  @Published var songs: [MusicKit.Song] = []
  @Published var albums: [Album] = []
  @Published var playlists: [Playlist] = []
  @Published var results: [MusicKit.Song] = []
  @Published var error: String?
  @Published var loading = false
  @Published var query = ""
  @Published var nowPlaying: MusicKit.Song?
  @Published var queueSongs: [MusicKit.Song] = []
  @Published var playing = false
  @Published var position = 0.0
  @Published var duration = 0.0
  var beforePlayback: (() -> Void)?
  let player = ApplicationMusicPlayer.shared
  private var searchRevision = UUID()
  private var timer: AnyCancellable?
  init() {
    timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.playing = self.player.state.playbackStatus == .playing
        self.position = max(0, self.player.playbackTime)
        if let entry = self.player.queue.currentEntry, case .song(let song) = entry.item {
          self.nowPlaying = song; self.duration = song.duration ?? 0
        }
      }
    }
  }
  func connect() async {
    authorization = await MusicAuthorization.request()
    guard authorization == .authorized else {
      error = "Accesso Apple Music non consentito. Puoi modificarlo nelle Impostazioni di iOS."; return
    }
    await refresh()
  }
  func refresh() async {
    authorization = MusicAuthorization.currentStatus
    guard authorization == .authorized else { return }
    loading = true; defer { loading = false }
    do {
      canPlayCatalog = try await MusicSubscription.current.canPlayCatalogContent
      var songRequest = MusicLibraryRequest<MusicKit.Song>(); songRequest.limit = 100
      songs = try await collect(songRequest.response().items)
      var albumRequest = MusicLibraryRequest<Album>(); albumRequest.limit = 100
      albums = try await collect(albumRequest.response().items)
      var playlistRequest = MusicLibraryRequest<Playlist>(); playlistRequest.limit = 100
      playlists = try await collect(playlistRequest.response().items)
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  private func collect<T: MusicItem & Decodable>(_ initial: MusicItemCollection<T>) async throws -> [T] {
    var values = Array(initial); var page = initial
    while page.hasNextBatch {
      try Task.checkCancellation()
      guard let next = try await page.nextBatch(limit:100) else { break }
      values.append(contentsOf:next); page=next
    }
    return values
  }
  func search() async {
    guard authorization == .authorized else { return }
    let revision = UUID(); searchRevision = revision
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { results = []; return }
    do {
      var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self]); request.limit = 25
      let response = try await request.response()
      guard searchRevision == revision else { return }
      results = Array(response.songs); error = nil
    } catch { if searchRevision == revision { self.error = error.localizedDescription } }
  }
  private func activateAudio() throws {
    beforePlayback?()
    let session=AVAudioSession.sharedInstance()
    try session.setCategory(.playback,mode:.default,policy:.longFormAudio)
    try session.setActive(true)
  }
  func play(_ song: MusicKit.Song, in list: [MusicKit.Song]) async {
    do {
      guard try await MusicSubscription.current.canPlayCatalogContent || song.playParameters != nil else {
        throw MusicPortError.subscriptionRequired
      }
      try activateAudio()
      queueSongs = list.isEmpty ? [song] : list
      player.queue = ApplicationMusicPlayer.Queue(for: queueSongs, startingAt: song)
      try await player.play(); nowPlaying = song; duration = song.duration ?? 0; error = nil
    } catch { self.error = error.localizedDescription }
  }
  func play(album: Album) async {
    do {
      let detail = try await album.with([.tracks])
      let allTracks: [Track]
      if let page = detail.tracks { allTracks = try await collect(page) } else { allTracks = [] }
      let tracks = allTracks.compactMap { track -> MusicKit.Song? in
        if case .song(let song) = track { return song }; return nil
      }
      guard let first = tracks.first else { throw MusicPortError.emptyCollection }
      await play(first, in: tracks)
    } catch { self.error = error.localizedDescription }
  }
  func play(playlist: Playlist) async {
    do {
      let detail = try await playlist.with([.tracks])
      let allTracks: [Track]
      if let page = detail.tracks { allTracks = try await collect(page) } else { allTracks = [] }
      let tracks = allTracks.compactMap { track -> MusicKit.Song? in
        if case .song(let song) = track { return song }; return nil
      }
      guard let first = tracks.first else { throw MusicPortError.emptyCollection }
      await play(first, in: tracks)
    } catch { self.error = error.localizedDescription }
  }
  func toggle() async {
    if playing { player.pause() }
    else { await resume() }
  }
  func resume() async { do { try activateAudio(); try await player.play() } catch { self.error = error.localizedDescription } }
  func next() async { do { try await player.skipToNextEntry() } catch { self.error = error.localizedDescription } }
  func previous() async { do { try await player.skipToPreviousEntry() } catch { self.error = error.localizedDescription } }
  func add(_ song: MusicKit.Song) async {
    do { try await MusicLibrary.shared.add(song); await refresh() }
    catch { self.error = error.localizedDescription }
  }
  func enqueue(_ song: MusicKit.Song, next: Bool) async {
    do {
      try await player.queue.insert(song, position: next ? .afterCurrentEntry : .tail)
      queueSongs.append(song)
    } catch { self.error = error.localizedDescription }
  }
}
enum MusicPortError: LocalizedError {
  case subscriptionRequired, emptyCollection
  var errorDescription: String? {
    switch self {
    case .subscriptionRequired: "Per riprodurre il catalogo occorre un abbonamento Apple Music attivo."
    case .emptyCollection: "La raccolta non contiene brani riproducibili."
    }
  }
}

@preconcurrency import MusicKit
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class MusicLibraryModel: ObservableObject {
  @Published var authorization = MusicAuthorization.currentStatus
  @Published var accessReport = "Nessuna verifica eseguita."
  @Published var checkingAccess = false
  @Published var subscriptionVerified = false
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
  private var accessEvents: [String] = []
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
    guard authorization == .authorized, !loading else { return }
    loading = true; defer { loading = false }
    var failures: [String] = []
    // Subscription/token access must not gate the local music library.
    do {
      var request = MusicLibraryRequest<MusicKit.Song>(); request.limit = 100
      songs = try await collect(request.response().items); record("Libreria brani: \(songs.count)")
    } catch { recordFailure(error,stage:"Brani"); failures.append("Brani: " + accessMessage(error)) }
    do {
      var request = MusicLibraryRequest<Album>(); request.limit = 100
      albums = try await collect(request.response().items); record("Libreria album: \(albums.count)")
    } catch { recordFailure(error,stage:"Album"); failures.append("Album: " + accessMessage(error)) }
    do {
      var request = MusicLibraryRequest<Playlist>(); request.limit = 100
      playlists = try await collect(request.response().items); record("Libreria playlist: \(playlists.count)")
    } catch { recordFailure(error,stage:"Playlist"); failures.append("Playlist: " + accessMessage(error)) }
    do {
      canPlayCatalog = try await withTokenRecovery { try await MusicSubscription.current.canPlayCatalogContent }
      subscriptionVerified = true; record("Abbonamento: verifica riuscita; catalogo=\(canPlayCatalog)")
    } catch {
      subscriptionVerified = false; recordFailure(error, stage:"Abbonamento")
      failures.append(accessMessage(error))
    }
    error = failures.isEmpty ? nil : Array(Set(failures)).sorted().joined(separator:"\n\n")
  }
  nonisolated private static func isDeveloperTokenFailure(_ error: any Error) -> Bool {
    if let value = error as? MusicTokenRequestError, value == .developerTokenRequestFailed { return true }
    if let nested = (error as NSError).userInfo[NSUnderlyingErrorKey] as? MusicTokenRequestError {
      return nested == .developerTokenRequestFailed
    }
    return false
  }
  private func withTokenRecovery<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    let recovery = MusicAccessRecovery(isDeveloperTokenFailure:Self.isDeveloperTokenFailure,
      renewDeveloperToken:{ [weak self] in
        await self?.record("Token sviluppatore: nuovo tentativo senza cache")
        _ = try await MusicDataRequest.tokenProvider.developerToken(options:.ignoreCache)
        await self?.record("Token sviluppatore: rinnovo riuscito")
      })
    return try await recovery.perform(operation)
  }
  func restoreAccess() async {
    guard !checkingAccess else { return }
    checkingAccess = true; defer { checkingAccess = false }
    record("Ripristino richiesto; autorizzazione=\(authorization)")
    if MusicAuthorization.currentStatus != .authorized { await connect(); return }
    do {
      _ = try await MusicDataRequest.tokenProvider.developerToken(options:.ignoreCache)
      record("Token sviluppatore: rinnovo manuale riuscito")
    } catch { recordFailure(error,stage:"Rinnovo token"); self.error = accessMessage(error) }
    await refresh()
  }
  private func accessMessage(_ error: any Error) -> String {
    if Self.isDeveloperTokenFailure(error) {
      return "Apple non riesce a generare il token sviluppatore per NoteNarrate Music. Questa verifica non indica che il tuo abbonamento sia assente. Prova Ripristina collegamento in Impostazioni; se persiste, condividi la diagnostica Apple Music."
    }
    if let value = error as? MusicTokenRequestError {
      switch value {
      case .userNotSignedIn: return "Apri Musica e verifica l’account Apple usato per l’abbonamento, poi riprova."
      case .permissionDenied, .userTokenRevoked: return "Consenti l’accesso di NoteNarrate Music alla libreria nelle Impostazioni di iOS."
      case .privacyAcknowledgementRequired: return "Apri Musica e completa le richieste Apple in sospeso, poi riprova."
      case .userTokenRequestFailed: return "Apple non riesce ad autorizzare l’account musicale. Apri Musica, poi riprova il collegamento."
      default: break
      }
    }
    return error.localizedDescription
  }
  private func recordFailure(_ error: any Error, stage: String) {
    let ns = error as NSError
    let kind = (error as? MusicTokenRequestError)?.rawValue ?? "altro"
    // Never include userInfo, URL, localizedDescription, tokens or response bodies.
    let domain = ns.domain.filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }.prefix(120)
    record("\(stage): errore \(kind), dominio=\(domain), codice=\(ns.code)")
    if let nested = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
      let nestedDomain = nested.domain.filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }.prefix(120)
      record("\(stage): causa dominio=\(nestedDomain), codice=\(nested.code)")
    }
  }
  private func record(_ event: String) {
    accessEvents.append(event); accessEvents = Array(accessEvents.suffix(35))
    let bundle = Bundle.main
    accessReport = "NoteNarrate Music \(bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "?") (\(bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "?"))\nBundle: \(bundle.bundleIdentifier ?? "?")\niOS: \(UIDevice.current.systemVersion)\nAutorizzazione: \(MusicAuthorization.currentStatus)\n" + accessEvents.joined(separator:"\n")
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
      let searchRequest = request
      let response = try await withTokenRecovery { try await searchRequest.response() }
      guard searchRevision == revision else { return }
      results = Array(response.songs); error = nil; record("Ricerca catalogo: riuscita")
    } catch { if searchRevision == revision { recordFailure(error,stage:"Ricerca catalogo"); self.error = accessMessage(error) } }
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

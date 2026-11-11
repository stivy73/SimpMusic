@preconcurrency import MusicKit
import SwiftUI
import Combine
import AVFoundation
@preconcurrency import MediaPlayer

@MainActor
final class MusicLibraryModel: ObservableObject {
  @Published var authorization = MusicAuthorization.currentStatus
  @Published var accessReport = "Nessuna verifica eseguita."
  @Published var checkingAccess = false
  @Published var checkingCloudLibrary = false
  @Published var subscriptionVerified = false
  @Published var canPlayCatalog = false
  @Published var songs: [MusicKit.Song] = []
  @Published var albums: [Album] = []
  @Published var playlists: [Playlist] = []
  @Published var results: [MusicKit.Song] = []
  @Published var error: String?
  @Published var loading = false
  @Published var mediaLibrarySummary = ""
  @Published var libraryAlbumQuery = ""
  @Published var libraryAlbumMatches: [Album] = []
  @Published var searchingLibraryAlbums = false
  private var albumSearchRevision = UUID()
  @Published var query = ""
  @Published var nowPlaying: MusicKit.Song?
  @Published var queueSongs: [MusicKit.Song] = []
  @Published var preparingPlayback = false
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
    await compareDeviceLibrary()
    // Show native data quickly, then prefer the complete account cloud library.
    var localSongs: [MusicKit.Song]?
    var localAlbums: [Album]?
    var localPlaylists: [Playlist]?
    do {
      var request = MusicLibraryRequest<MusicKit.Song>(); request.limit = 100; request.includeOnlyDownloadedContent = false
      let values = try await collect(request.response().items); localSongs = values
      if !values.isEmpty || songs.isEmpty { songs = values }
      record("Libreria locale brani: \(values.count)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Brani locali") }
    do {
      var request = MusicLibraryRequest<Album>(); request.limit = 100; request.includeOnlyDownloadedContent = false
      let values = try await collect(request.response().items); localAlbums = values
      if !values.isEmpty || albums.isEmpty { albums = values }
      record("Libreria locale album: \(values.count)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Album locali") }
    do {
      var request = MusicLibraryRequest<Playlist>(); request.limit = 100; request.includeOnlyDownloadedContent = false
      let values = try await collect(request.response().items); localPlaylists = values
      if !values.isEmpty || playlists.isEmpty { playlists = values }
      record("Libreria locale playlist: \(values.count)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Playlist locali") }
    let cloud = MusicCloudLibrary(fetch:{ [weak self] request in
      guard let self else { throw CancellationError() }
      return try await self.withTokenRecovery {
        let response = try await MusicDataRequest(urlRequest:request).response()
        return MusicCloudLibrary.Response(data:response.data,status:response.urlResponse.statusCode)
      }
    })
    do {
      let result = try await cloud.load(MusicKit.Song.self,resource:.songs)
      songs = MusicCloudLibrary.combining(result.items,local:localSongs ?? [])
      record("Libreria cloud brani: completata; elementi=\(result.items.count); pagine=\(result.pages)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Brani cloud"); failures.append("Brani cloud: " + accessMessage(error)) }
    do {
      let result = try await cloud.load(Album.self,resource:.albums)
      albums = MusicCloudLibrary.combining(result.items,local:localAlbums ?? [])
      record("Libreria cloud album: completata; elementi=\(result.items.count); pagine=\(result.pages)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Album cloud"); failures.append("Album cloud: " + accessMessage(error)) }
    do {
      let result = try await cloud.load(Playlist.self,resource:.playlists)
      playlists = MusicCloudLibrary.combining(result.items,local:localPlaylists ?? [])
      record("Libreria cloud playlist: completata; elementi=\(result.items.count); pagine=\(result.pages)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Playlist cloud"); failures.append("Playlist cloud: " + accessMessage(error)) }
    do {
      canPlayCatalog = try await withTokenRecovery { try await MusicSubscription.current.canPlayCatalogContent }
      subscriptionVerified = true; record("Abbonamento: verifica riuscita; catalogo=\(canPlayCatalog)")
    } catch {
      subscriptionVerified = false; recordFailure(error, stage:"Abbonamento")
      failures.append(accessMessage(error))
    }
    record("Elenco pubblicato: brani=\(songs.count); album=\(albums.count); playlist=\(playlists.count)")
    error = failures.isEmpty ? nil : Array(Set(failures)).sorted().joined(separator:"\n\n")
  }
  // Independent, read-only view of the device media database. Counts only:
  // no album titles, account identifiers or media URLs enter shared diagnostics.
  private func compareDeviceLibrary() async {
    let report = await Task.detached(priority:.userInitiated) {
      let status = MPMediaLibrary.authorizationStatus()
      guard status == .authorized else {
        return "Libreria multimediale iOS: autorizzazione=\(status.rawValue); lettura non eseguita"
      }
      let tracks = MPMediaQuery.songs().items ?? []
      let albums = MPMediaQuery.albums().collections ?? []
      let playlists = MPMediaQuery.playlists().collections ?? []
      let cloud = tracks.lazy.filter { $0.isCloudItem }.count
      return "Libreria multimediale iOS: brani=\(tracks.count); album=\(albums.count); playlist=\(playlists.count); brani cloud=\(cloud)"
    }.value
    guard !Task.isCancelled else { return }
    mediaLibrarySummary = report
    record(report)
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
  func checkCloudLibrary() async {
    guard authorization == .authorized, !checkingCloudLibrary else { return }
    checkingCloudLibrary = true; defer { checkingCloudLibrary = false }
    for resource in MusicCloudProbe.Resource.allCases {
      let stage = "Libreria cloud \(resource.rawValue)"
      do {
        let request = MusicCloudProbe.request(for:resource)
        let result = try await withTokenRecovery {
          let response = try await MusicDataRequest(urlRequest:request).response()
          return try MusicCloudProbe.parse(response.data,status:response.urlResponse.statusCode)
        }
        record("\(stage): HTTP 200; prima pagina=\(result.firstPageCount); altre pagine=\(result.hasMore)")
      } catch { recordFailure(error,stage:stage) }
    }
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
    if let response = error as? MusicDataRequest.Error {
      record("\(stage): HTTP \(response.status); codice Apple=\(response.code)")
    }
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
  func searchLibraryAlbums() async {
    guard authorization == .authorized else { return }
    let revision = UUID(); albumSearchRevision = revision
    let term = libraryAlbumQuery.trimmingCharacters(in:.whitespacesAndNewlines)
    libraryAlbumMatches = []
    guard !term.isEmpty else { searchingLibraryAlbums = false; return }
    searchingLibraryAlbums = true
    defer { if albumSearchRevision == revision { searchingLibraryAlbums = false } }
    var matches: [Album] = []
    do {
      var request = MusicLibrarySearchRequest(term:term,types:[Album.self]); request.limit = 25
      let response = try await request.response()
      guard revision == albumSearchRevision else { return }
      matches = Array(response.albums); libraryAlbumMatches = matches
      record("Ricerca album locale: prima pagina=\(matches.count); altre pagine=\(response.albums.hasNextBatch)")
    } catch { if Task.isCancelled { return }; if revision == albumSearchRevision { recordFailure(error,stage:"Ricerca album locale") } }
    guard revision == albumSearchRevision, !Task.isCancelled else { return }
    do {
      let request = MusicCloudProbe.albumSearchRequest(term:term)
      let page = try await withTokenRecovery {
        let response = try await MusicDataRequest(urlRequest:request).response()
        return try MusicCloudProbe.albumSearchPage(Album.self,data:response.data,status:response.urlResponse.statusCode)
      }
      guard revision == albumSearchRevision else { return }
      libraryAlbumMatches = MusicCloudLibrary.combining(page.data,local:matches)
      record("Ricerca album cloud: prima pagina=\(page.data.count); altre pagine=\(page.next?.isEmpty == false)")
    } catch { if Task.isCancelled { return }; if revision == albumSearchRevision { recordFailure(error,stage:"Ricerca album cloud"); self.error = accessMessage(error) } }
    guard revision == albumSearchRevision, !Task.isCancelled else { return }
    let count = await Task.detached(priority:.userInitiated) {
      guard MPMediaLibrary.authorizationStatus() == .authorized else { return -1 }
      let request = MPMediaQuery.albums()
      request.addFilterPredicate(MPMediaPropertyPredicate(value:term,forProperty:MPMediaItemPropertyAlbumTitle,comparisonType:.contains))
      return request.collections?.count ?? 0
    }.value
    guard revision == albumSearchRevision else { return }
    record("Ricerca album multimediale iOS: corrispondenze=\(count); risultati pubblicati=\(libraryAlbumMatches.count)")
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
    let values = list.isEmpty ? [song] : list
    record("Selezione brano: parametri=\(song.playParameters != nil); elementi=\(values.count)")
    await startPlayback(queue:ApplicationMusicPlayer.Queue(for:values,startingAt:song),origin:"Brano")
  }
  func play(album: Album) async {
    record("Selezione album: parametri=\(album.playParameters != nil)")
    // Let MusicKit expand the album, retaining its playback context and lazy loading.
    await startPlayback(queue:ApplicationMusicPlayer.Queue(for:[album]),origin:"Album")
  }
  func play(playlist: Playlist) async {
    record("Selezione playlist: parametri=\(playlist.playParameters != nil)")
    // Do not flatten library playlist tracks into detached Song values.
    await startPlayback(queue:ApplicationMusicPlayer.Queue(for:[playlist]),origin:"Playlist")
  }
  private func startPlayback(queue: ApplicationMusicPlayer.Queue, origin: String) async {
    guard !preparingPlayback else { record("\(origin): preparazione già in corso"); return }
    preparingPlayback = true; defer { preparingPlayback = false }
    var stage = "Sessione audio"
    do {
      error = nil
      try activateAudio()
      player.stop()
      player.queue = queue
      stage = "Preparazione audio \(origin)"
      record("\(stage): avviata; coda nativa")
      try await player.prepareToPlay()
      try Task.checkCancellation()
      record("\(stage): riuscita")
      stage = "Avvio audio \(origin)"
      try await player.play()
      syncPlaybackState()
      record("\(stage): riuscito; stato=\(player.state.playbackStatus)")
    } catch {
      recordFailure(error,stage:stage)
      if Task.isCancelled { player.stop(); return }
      self.error = playbackMessage(error)
    }
  }
  private func syncPlaybackState() {
    queueSongs = player.queue.entries.compactMap { entry in
      if case .song(let song) = entry.item { return song }; return nil
    }
    playing = player.state.playbackStatus == .playing
    if let entry = player.queue.currentEntry, case .song(let song) = entry.item {
      nowPlaying = song; duration = song.duration ?? 0
    }
  }
  private func playbackMessage(_ error: any Error) -> String {
    let ns = error as NSError
    if ns.domain == "MPMusicPlayerControllerErrorDomain", ns.code == 6 {
      return "Apple Music non è riuscita a preparare l’audio (codice 6). Se il problema persiste, condividi la diagnostica da Impostazioni → Collegamento Apple Music."
    }
    return accessMessage(error)
  }
  func toggle() async {
    if playing { player.pause() }
    else { await resume() }
  }
  func resume() async {
    guard !preparingPlayback else { return }
    preparingPlayback = true; defer { preparingPlayback = false }
    do {
      try activateAudio()
      if !player.isPreparedToPlay { try await player.prepareToPlay() }
      try await player.play(); syncPlaybackState(); record("Ripresa audio: riuscita")
    } catch { recordFailure(error,stage:"Ripresa audio"); self.error = playbackMessage(error) }
  }
  func next() async { do { try await player.skipToNextEntry() } catch { recordFailure(error,stage:"Brano successivo"); self.error = playbackMessage(error) } }
  func previous() async { do { try await player.skipToPreviousEntry() } catch { recordFailure(error,stage:"Brano precedente"); self.error = playbackMessage(error) } }
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

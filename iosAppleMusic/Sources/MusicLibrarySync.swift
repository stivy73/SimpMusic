import Foundation
@preconcurrency import MusicKit
@preconcurrency import MediaPlayer

struct DeviceLibrarySnapshot: Sendable {
  var tracks: [LibraryTrackReference] = []
  var albumTitles: [String] = []
  var report = ""
}

extension MusicLibraryModel {
  func libraryState(_ category: BrowseKind) -> LibrarySectionState { libraryStates[category] ?? .init() }

  func refresh(category: BrowseKind? = nil) async {
    if isPlayerFixture { return }
    authorization = MusicAuthorization.currentStatus
    let requested = category.map { Set([$0]) } ?? Set(BrowseKind.allCases)
    guard authorization == .authorized else {
      librarySyncActivity = .init(); loading = false
      songs = []; albums = []; playlists = []; artists = []
      for kind in BrowseKind.allCases {
        libraryStates[kind] = .init(phase: .failed, message: "Consenti l’accesso ad Apple Music per leggere la libreria.")
      }
      return
    }
    observeLibraryChanges()
    let work = librarySyncActivity.begin(requested), selected = work.categories
    guard !selected.isEmpty else { return }
    loading = true
    let previous = libraryStates
    for kind in selected {
      var state = libraryState(kind); state.phase = .updating; state.message = nil
      libraryStates[kind] = state
    }
    defer {
      for kind in selected where librarySyncActivity.finish(kind, work: work.id) {
        if libraryState(kind).phase == .updating { libraryStates[kind] = previous[kind] ?? .init() }
      }
      loading = librarySyncActivity.busy
    }
    do {
      let device = await deviceLibrarySnapshot()
      try Task.checkCancellation()
      // Categories finish independently; a slow songs recovery does not hide
      // playlists or artists. Albums precede songs only to supply owned IDs.
      async let playlistRead: Void = syncPlaylists(if: selected.contains(.playlists), work: work.id)
      async let artistRead: Void = syncArtists(if: selected.contains(.artists), work: work.id)
      if selected.contains(.albums) { try await syncAlbums(device, work: work.id) }
      if selected.contains(.songs) { try await syncSongs(device, work: work.id) }
      _ = try await (playlistRead, artistRead)
      if category == nil { await verifyLibrarySubscription() }
      record("Elenco pubblicato: brani=\(songs.count); album=\(albums.count); playlist=\(playlists.count); artisti=\(artists.count)")
    } catch {
      if !(error is CancellationError) && !Task.isCancelled { recordFailure(error, stage: "Sincronizzazione libreria") }
    }
  }

  private var libraryReader: MusicCloudLibrary {
    MusicCloudLibrary(fetch: { request in
      try await MusicRead.perform {
        let response = try await MusicDataRequest(urlRequest: request).response()
        return .init(data: response.data, status: response.urlResponse.statusCode)
      }
    })
  }

  private func localLibraryRead<Item: MusicLibraryRequestable & Decodable & Sendable>(
    _ type: Item.Type, label: String
  ) async throws -> LibraryRead<Item> {
    do {
      var request = MusicLibraryRequest<Item>(); request.limit = 100; request.includeOnlyDownloadedContent = false
      let submitted = request
      let page = try await withTokenRecovery { try await submitted.response().items }
      let values = try await collect(page)
      try Task.checkCancellation()
      record("Libreria locale \(label): completata; elementi=\(values.count)")
      return .success(values)
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      recordFailure(error, stage: "Libreria locale \(label)")
      return .failure("Libreria sul dispositivo: " + accessMessage(error))
    }
  }
  private func cloudLibraryRead<Item: Decodable & Identifiable & Sendable>(
    _ type: Item.Type, resource: MusicCloudProbe.Resource, label: String
  ) async throws -> LibraryRead<Item> where Item.ID: Hashable {
    do {
      let result = try await libraryReader.load(type, resource: resource)
      record("Libreria cloud \(label): completata; elementi=\(result.items.count); pagine=\(result.pages)")
      return .success(result.items)
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      recordFailure(error, stage: "Libreria cloud \(label)")
      return .failure("Libreria iCloud: " + accessMessage(error))
    }
  }

  private func syncPlaylists(if enabled: Bool, work: UUID) async throws {
    guard enabled else { return }
    async let local = localLibraryRead(Playlist.self, label: "playlist")
    async let cloud = cloudLibraryRead(Playlist.self, resource: .playlists, label: "playlist")
    let result = try await LibrarySyncPolicy.reconcile(previous: playlists, local: local, cloud: cloud, previousState: libraryState(.playlists))
    try validateLibraryWork(.playlists, work: work)
    playlists = result.items; libraryStates[.playlists] = result.state
    recordSection(.playlists, count: playlists.count, work: work)
  }
  private func syncArtists(if enabled: Bool, work: UUID) async throws {
    guard enabled else { return }
    async let local = localLibraryRead(Artist.self, label: "artisti")
    async let cloud = cloudLibraryRead(Artist.self, resource: .artists, label: "artisti")
    let result = try await LibrarySyncPolicy.reconcile(previous: artists, local: local, cloud: cloud, previousState: libraryState(.artists))
    try validateLibraryWork(.artists, work: work)
    artists = result.items; libraryStates[.artists] = result.state
    recordSection(.artists, count: artists.count, work: work)
  }
  private func syncAlbums(_ device: DeviceLibrarySnapshot, work: UUID) async throws {
    async let localRead = localLibraryRead(Album.self, label: "album")
    async let cloudRead = cloudLibraryRead(Album.self, resource: .albums, label: "album")
    let (local, cloud) = try await (localRead, cloudRead)
    var fresh = MusicCloudLibrary.combining(cloud.values, local: local.values)
    var recovered: [Album] = [], recoveryFailures = 0
    let saved = UserDefaults.standard.stringArray(forKey: recoveredAlbumKey) ?? []
    do {
      let restored = try await libraryReader.albumsByID(Album.self, ids: saved, id: { $0.id.rawValue })
      recovered = restored; fresh = MusicCloudLibrary.combining(fresh, local: restored)
      // Prune removed references only after a successful current-account read.
      UserDefaults.standard.set(MusicCloudLibrary.libraryAlbumIDs(restored.map { $0.id.rawValue }), forKey: recoveredAlbumKey)
      record("Album recuperati: riferimenti=\(saved.count); verificati=\(restored.count)")
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      recoveryFailures += 1; recordFailure(error, stage: "Verifica album recuperati")
    }
    let listed = Set(fresh.map { LibrarySongIdentity.key($0.title) })
    let missing = device.albumTitles.filter { !listed.contains(LibrarySongIdentity.key($0)) }
    var completed = 0
    for title in missing {
      try Task.checkCancellation()
      do {
        let found = try await findLibraryAlbums(title)
        try Task.checkCancellation()
        recovered = MusicCloudLibrary.combining(recovered, local: found); completed += 1
      } catch {
        if Task.isCancelled || error is CancellationError { throw CancellationError() }
        recoveryFailures += 1; recordFailure(error, stage: "Ricerca album personale")
      }
    }
    fresh = MusicCloudLibrary.combining(fresh, local: recovered)
    let verifiedTitles = Set(fresh.map { LibrarySongIdentity.key($0.title) })
    remainingAlbumLookups = device.albumTitles.filter { !verifiedTitles.contains(LibrarySongIdentity.key($0)) }.count
    let message = remainingAlbumLookups > 0 ? "\(remainingAlbumLookups) album rilevati da iOS non sono ancora stati restituiti da Apple Music." :
      (recoveryFailures > 0 ? "Una verifica degli album recuperati non è riuscita. Riprova per completare la sincronizzazione." : nil)
    let result = LibrarySyncPolicy.reconcile(previous: albums, local: local, cloud: cloud,
      recovered: recovered, unresolved: remainingAlbumLookups, recoveryMessage: message, previousState: libraryState(.albums))
    try validateLibraryWork(.albums, work: work)
    albums = result.items; libraryStates[.albums] = result.state
    let remembered = UserDefaults.standard.stringArray(forKey: recoveredAlbumKey) ?? []
    UserDefaults.standard.set(MusicCloudLibrary.libraryAlbumIDs(remembered + recovered.map { $0.id.rawValue }), forKey: recoveredAlbumKey)
    record("Recupero album iOS: ricerche=\(completed); mancanti=\(remainingAlbumLookups)")
    recordSection(.albums, count: albums.count, work: work)
  }

  private func syncSongs(_ device: DeviceLibrarySnapshot, work: UUID) async throws {
    async let localRead = localLibraryRead(Song.self, label: "brani")
    async let cloudRead = cloudLibraryRead(Song.self, resource: .songs, label: "brani")
    let (local, cloud) = try await (localRead, cloudRead)
    let fresh = LibrarySongRecovery.merging(cloud.values, local.values, identity: Self.libraryIdentity)
    let reader = libraryReader, ownedAlbums = albums
    let recovery = try await LibrarySongRecovery.recover(references: device.tracks, available: fresh,
      id: { $0.id.rawValue }, identity: Self.libraryIdentity,
      albumTracks: { title in
        let matches = ownedAlbums.filter { LibrarySongIdentity.key($0.title) == LibrarySongIdentity.key(title) &&
          MusicCloudLibrary.libraryAlbumIDs([$0.id.rawValue]) == [$0.id.rawValue] }
        var songs: [Song] = []
        for album in matches {
          let page = try await reader.albumTracks(Song.self, albumID: album.id.rawValue)
          songs = LibrarySongRecovery.merging(songs, page.items, identity: Self.libraryIdentity)
        }
        return songs
      }, search: { [weak self] term in
        guard let self else { throw CancellationError() }
        return try await self.findLibrarySongs(term)
      }, catalog: { [weak self] ids in
        guard let self else { throw CancellationError() }
        let values = try await self.withTokenRecovery {
          let country = try await MusicDataRequest.currentCountryCode
          let request = try MediaCatalogRequest.request(ids: ids, storefront: country)
          let response = try await MusicDataRequest(urlRequest: request).response()
          return try MediaCatalogRequest.items(Song.self, data: response.data, status: response.urlResponse.statusCode)
        }
        await self.record("Recupero catalogo esatto: richiesti=\(ids.count); restituiti=\(values.count)")
        return values
      })
    try validateLibraryWork(.songs, work: work)
    let message = recovery.unresolved > 0 ? "\(recovery.unresolved) brani rilevati da iOS non sono ancora disponibili nell’elenco. La libreria è parziale; puoi riprovare questa categoria." : nil
    var result = LibrarySyncPolicy.reconcile(previous: songs, local: local, cloud: cloud,
      recovered: recovery.items, unresolved: recovery.unresolved, recoveryMessage: message, previousState: libraryState(.songs))
    result.items = LibrarySongRecovery.merging(result.items, [], identity: Self.libraryIdentity)
    songs = result.items; libraryStates[.songs] = result.state
    rememberArtwork(songs)
    record("Recupero brani iOS: rilevati=\(device.tracks.count); mancanti=\(recovery.unresolved); letture album=\(recovery.albumReads); ricerche personali=\(recovery.searches); ID catalogo richiesti=\(recovery.catalogRequested); errori recupero=\(recovery.failedReads)")
    recordSection(.songs, count: songs.count, work: work)
  }
  private func findLibrarySongs(_ term: String) async throws -> [Song] {
    var native: [Song] = [], cloud: [Song] = [], succeeded = false
    var lastError: (any Error)?
    do {
      var request = MusicLibrarySearchRequest(term: term, types: [Song.self]); request.limit = 25
      let submitted = request
      let first = try await withTokenRecovery { try await submitted.response().songs }
      native = try await collect(first, batchSize: 25); succeeded = true
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      lastError = error; recordFailure(error, stage: "Ricerca brani locale")
    }
    do {
      cloud = try await libraryReader.search(Song.self, resource: .songs, term: term).items; succeeded = true
    } catch {
      if Task.isCancelled || error is CancellationError { throw CancellationError() }
      lastError = error; recordFailure(error, stage: "Ricerca brani cloud")
    }
    guard succeeded else { throw lastError ?? MusicPortError.emptyCollection }
    return LibrarySongRecovery.merging(cloud, native, identity: Self.libraryIdentity)
  }

  nonisolated static func libraryIdentity(_ song: Song) -> LibrarySongIdentity {
    var ids: Set<String> = [song.id.rawValue]
    if let parameters = song.playParameters, let data = try? JSONEncoder().encode(parameters),
      let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
      for key in ["id", "catalogId", "catalogID"] {
        if let id = fields[key] as? String, !id.isEmpty { ids.insert(id) }
      }
    }
    return .init(ids: ids, title: song.title, artist: song.artistName, album: song.albumTitle ?? "",
      track: song.trackNumber ?? 0, disc: song.discNumber ?? 0, duration: song.duration ?? 0)
  }
  private func verifyLibrarySubscription() async {
    do {
      canPlayCatalog = try await withTokenRecovery { try await MusicSubscription.current.canPlayCatalogContent }
      subscriptionVerified = true; record("Abbonamento: verifica riuscita; catalogo=\(canPlayCatalog)")
    } catch {
      if Task.isCancelled { return }
      subscriptionVerified = false; recordFailure(error, stage: "Abbonamento")
    }
  }
  private func recordSection(_ kind: BrowseKind, count: Int, work: UUID) {
    librarySyncActivity.finish(kind, work: work); loading = librarySyncActivity.busy
    let state = libraryState(kind)
    record("Sincronizzazione \(kind.rawValue): stato=\(state.phase); elementi=\(count); mancanti=\(state.unresolved)")
  }
  private func validateLibraryWork(_ kind: BrowseKind, work: UUID) throws {
    try Task.checkCancellation()
    guard librarySyncActivity.owns(kind, work: work), MusicAuthorization.currentStatus == .authorized else { throw CancellationError() }
  }
  private func deviceLibrarySnapshot() async -> DeviceLibrarySnapshot {
    let snapshot = await Task.detached(priority: .userInitiated) {
      let status = MPMediaLibrary.authorizationStatus()
      guard status == .authorized else {
        return DeviceLibrarySnapshot(report: "Libreria multimediale iOS: autorizzazione=\(status.rawValue); lettura non eseguita")
      }
      let tracks = MPMediaQuery.songs().items ?? []
      let albums = MPMediaQuery.albums().collections ?? []
      let playlists = MPMediaQuery.playlists().collections ?? []
      return DeviceLibrarySnapshot(tracks: tracks.map {
        .init(storeID: $0.playbackStoreID, title: $0.title ?? "", artist: $0.artist ?? "", album: $0.albumTitle ?? "",
          track: $0.albumTrackNumber, disc: $0.discNumber, duration: $0.playbackDuration)
      }, albumTitles: Array(Set(albums.compactMap { $0.representativeItem?.albumTitle })).filter { !$0.isEmpty }.sorted(),
      report: "Libreria multimediale iOS: brani=\(tracks.count); album=\(albums.count); playlist=\(playlists.count); brani cloud=\(tracks.filter(\.isCloudItem).count)")
    }.value
    guard !Task.isCancelled else { return .init() }
    mediaLibrarySummary = snapshot.report; record(snapshot.report)
    let ids = MediaCatalogBridge.catalogIDs(snapshot.tracks.map(\.storeID))
    record("Identificativi brani iOS: ID catalogo distinti=\(ids.count); senza ID utilizzabile=\(snapshot.tracks.filter { MediaCatalogBridge.catalogIDs([$0.storeID]).isEmpty }.count)")
    return snapshot
  }
}

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
  @Published var artists:[Artist]=[]
  @Published var results: [MusicKit.Song] = []
  @Published var searchAlbums:[Album]=[]
  @Published var searchArtists:[Artist]=[]
  @Published var searchPlaylists:[Playlist]=[]
  @Published var searchingCatalog=false
  @Published var recentSongs:[MusicKit.Song]=[]
  @Published var recommendations:[MusicPersonalRecommendation]=[]
  @Published var discoveryError:String?
  @Published var loadingDiscovery=false
  @Published var sendingFavorite=false
  @Published var favoriteStates:[String:Bool]=[:]
  @Published var favoriteSongs:[MusicKit.Song]=[]
  @Published var favoriteAlbums:[Album]=[]
  @Published var favoritePlaylists:[Playlist]=[]
  @Published var favoriteArtists:[Artist]=[]
  @Published var favoritesFailure:String?
  @Published var loadingFavorites=false
  @Published var notice:String?
  @Published var error: String?
  @Published var loading = false
  @Published var mediaLibrarySummary = ""
  @Published var libraryAlbumQuery = ""
  @Published var libraryAlbumMatches: [Album] = []
  @Published var searchingLibraryAlbums = false
  private var albumSearchRevision = UUID()
  @Published var remainingAlbumLookups = 0
  private let recoveredAlbumKey = "musicRecoveredLibraryAlbumIDs"
  @Published var query = ""
  @Published var nowPlaying: MusicKit.Song?
  @Published var activeCollectionID:String?
  @Published var activeCollectionRowID:String?
  var activeCollectionQueueEntryID:MusicKit.MusicPlayer.Queue.Entry.ID?
  @Published var queueSongs: [MusicKit.Song] = []
  @Published var showPlayer = false
  @Published var playbackFailure:String?
  private var playbackIntent=UUID()
  @Published var preparingPlayback = false
  @Published var playing = false
  @Published var position = 0.0
  @Published var duration = 0.0
  let artwork=PlaybackArtwork(fetch:MusicArtworkResolver.resolve)
  var artworkFixtureQueue:[MusicKit.MusicPlayer.Queue.Entry]=[]
  private var artworkChanges:AnyCancellable?
  var beforePlayback: (() -> Void)?
  let player = ApplicationMusicPlayer.shared
  private var accessEvents: [String] = []
  private var searchRevision = UUID()
  private var timer: AnyCancellable?
  var isPlayerFixture:Bool {
    #if DEBUG && PLAYER_LAYOUT_FIXTURE
      true
    #else
      false
    #endif
  }
  init() {
    artworkChanges=artwork.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
    #if DEBUG && PLAYER_LAYOUT_FIXTURE
    let data=Data(#"{"id":"123456789","type":"songs","attributes":{"name":"Brano di prova","artistName":"NoteNarrate · test interfaccia","albumName":"Album di prova","durationInMillis":261000,"playParams":{"id":"123456789","kind":"song"}}}"#.utf8)
    nowPlaying=try? JSONDecoder().decode(MusicKit.Song.self,from:data)
    duration=261;position=42;authorization = .authorized;showPlayer=true
    #if BROWSE_LAYOUT_FIXTURE
    showPlayer=false
    func fixture<T:Decodable>(_ type:T.Type,id:String,kind:String,attributes:[String:Any])->T? {
      guard let bytes=try? JSONSerialization.data(withJSONObject:["id":id,"type":kind,"attributes":attributes]) else{return nil}
      return try? JSONDecoder().decode(type,from:bytes)
    }
    songs=[nowPlaying].compactMap{$0}
    albums=[fixture(Album.self,id:"100001",kind:"albums",attributes:["url":"https://music.apple.com/it/album/100001","name":"Album Beta","artistName":"Artista di prova","genreNames":[],"trackCount":2]),fixture(Album.self,id:"100002",kind:"albums",attributes:["url":"https://music.apple.com/it/album/100002","name":"Album Alpha","artistName":"Altro artista","genreNames":[],"trackCount":2])].compactMap{$0}
    playlists=[fixture(Playlist.self,id:"p.fixture",kind:"library-playlists",attributes:["name":"Playlist di prova","canEdit":true])].compactMap{$0}
    artists=[fixture(Artist.self,id:"1003",kind:"artists",attributes:["name":"Artista di prova"]),fixture(Artist.self,id:"1004",kind:"artists",attributes:["name":"Altro artista"])].compactMap{$0}
    albums+=(3...7).compactMap{fixture(Album.self,id:String(100000+$0),kind:"albums",attributes:["name":"Album di prova \($0)","artistName":"Artista di prova","genreNames":[],"trackCount":2])}
    songs+=(1...5).compactMap{fixture(Song.self,id:String(123456789+$0),kind:"songs",attributes:["name":"Ascolto recente \($0)","artistName":"Artista di prova","albumName":"Album di prova","durationInMillis":200000,"playParams":["id":String(123456789+$0),"kind":"song"]])}
    recentSongs=songs;favoriteSongs=songs;favoriteAlbums=albums;favoritePlaylists=playlists;favoriteArtists=artists
    #endif
    #if ARTWORK_LAYOUT_FIXTURE
    MusicArtworkFixture.configure(self)
    #endif
    return
    #endif
    timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.syncPlaybackState()
        if self.playing { self.playbackFailure=nil }
        self.position = max(0, self.player.playbackTime)
      }
    }
  }
  func connect() async {
    authorization = await MusicAuthorization.request()
    guard authorization == .authorized else {
      error = "Accesso Apple Music non consentito. Puoi modificarlo nelle Impostazioni di iOS."; return
    }
    await refreshHome()
  }
  func refresh() async {
    if isPlayerFixture {return}
    authorization = MusicAuthorization.currentStatus
    guard authorization == .authorized, !loading else { return }
    loading = true; defer { loading = false }
    var failures: [String] = []
    let device = await compareDeviceLibrary()
    let deviceStoreIDs = device.ids
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
    do {
      var request=MusicLibraryRequest<Artist>();request.limit=100
      artists=try await collect(request.response().items)
    } catch {if Task.isCancelled {return};recordFailure(error,stage:"Artisti locali")}
    let cloud = MusicCloudLibrary(fetch:{ [weak self] request in
      guard let self else { throw CancellationError() }
      return try await self.withTokenRecovery {
        let response = try await MusicDataRequest(urlRequest:request).response()
        return MusicCloudLibrary.Response(data:response.data,status:response.urlResponse.statusCode)
      }
    })
    do {
      let result=try await cloud.load(Artist.self,resource:.artists)
      artists=MusicCloudLibrary.combining(result.items,local:artists)
      record("Libreria cloud artisti: completata; elementi=\(result.items.count)")
    } catch {if Task.isCancelled {return};recordFailure(error,stage:"Artisti cloud");failures.append("Artisti cloud: "+accessMessage(error))}
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
      let saved = UserDefaults.standard.stringArray(forKey:recoveredAlbumKey) ?? []
      let restored = try await cloud.albumsByID(Album.self,ids:saved,id:{$0.id.rawValue})
      albums = MusicCloudLibrary.combining(albums,local:restored)
      record("Album recuperati: riferimenti=\(saved.count); verificati=\(restored.count)")
    } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Verifica album recuperati") }
    let listed = Set(albums.map { $0.title.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current) })
    let missing = device.albumTitles.filter { !listed.contains($0.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)) }
    remainingAlbumLookups = max(0,missing.count - 25)
    var attempted = 0
    for title in missing.prefix(25) {
      do {
        let found = try await findLibraryAlbums(title)
        try Task.checkCancellation()
        rememberLibraryAlbums(found)
        attempted += 1
      } catch { if Task.isCancelled { return }; recordFailure(error,stage:"Recupero album iOS") }
    }
    record("Recupero album iOS: ricerche completate=\(attempted); altre ricerche=\(remainingAlbumLookups); elenco=\(albums.count)")
    if songs.isEmpty, !deviceStoreIDs.isEmpty {
      do {
        let result = try await MediaCatalogBridge.resolve(deviceStoreIDs,id:{ (song:MusicKit.Song) in song.id.rawValue }) { [weak self] ids in
          guard let self else { throw CancellationError() }
          let storefront=try await MusicDataRequest.currentCountryCode
          let request=try MediaCatalogRequest.request(ids:ids,storefront:storefront)
          let response=try await MusicDataRequest(urlRequest:request).response()
          let values=try MediaCatalogRequest.items(MusicKit.Song.self,data:response.data,status:response.urlResponse.statusCode)
          await self.record("Catalogo esplicito: storefront=\(storefront); HTTP \(response.urlResponse.statusCode); richiesti=\(ids.count); restituiti=\(values.count)")
          return values
        }
        try Task.checkCancellation()
        songs = result.items
        record("Recupero brani iOS: ID validi=\(result.requested); risolti=\(result.items.count); non restituiti=\(result.unresolved)")
      } catch {
        if Task.isCancelled { return }
        recordFailure(error,stage:"Recupero brani iOS")
        failures.append("Non è stato possibile recuperare i brani della libreria iOS. Riprova l’aggiornamento.")
      }
    }
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
  private func compareDeviceLibrary() async -> (ids:[String],albumTitles:[String]) {
    let report = await Task.detached(priority:.userInitiated) {
      let status = MPMediaLibrary.authorizationStatus()
      guard status == .authorized else {
        return ("Libreria multimediale iOS: autorizzazione=\(status.rawValue); lettura non eseguita",[String](),[String]())
      }
      let tracks = MPMediaQuery.songs().items ?? []
      let albums = MPMediaQuery.albums().collections ?? []
      let playlists = MPMediaQuery.playlists().collections ?? []
      let cloud = tracks.lazy.filter { $0.isCloudItem }.count
      return ("Libreria multimediale iOS: brani=\(tracks.count); album=\(albums.count); playlist=\(playlists.count); brani cloud=\(cloud)",tracks.map(\.playbackStoreID),albums.compactMap { $0.representativeItem?.albumTitle })
    }.value
    guard !Task.isCancelled else { return ([],[]) }
    mediaLibrarySummary = report.0
    record(report.0)
    let ids = MediaCatalogBridge.catalogIDs(report.1)
    record("Identificativi brani iOS: con ID catalogo=\(ids.count); senza ID utilizzabile=\(report.1.filter { MediaCatalogBridge.catalogIDs([$0]).isEmpty }.count)")
    return (ids,Array(Set(report.2)).filter { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.sorted())
  }
  nonisolated static func isDeveloperTokenFailure(_ error: any Error) -> Bool {
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
    artwork.reset()
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
  private func collect<T: MusicItem & Decodable>(_ initial: MusicItemCollection<T>, batchSize:Int = 100) async throws -> [T] {
    var values = Array(initial); var page = initial
    while page.hasNextBatch {
      try Task.checkCancellation()
      guard let next = try await page.nextBatch(limit:batchSize) else { break }
      values.append(contentsOf:next); page=next
    }
    return values
  }
  func rememberLibraryAlbums(_ values:[Album]) {
    albums = MusicCloudLibrary.combining(albums,local:values)
    let saved = UserDefaults.standard.stringArray(forKey:recoveredAlbumKey) ?? []
    let ids = MusicCloudLibrary.libraryAlbumIDs(saved + values.map { $0.id.rawValue })
    UserDefaults.standard.set(ids,forKey:recoveredAlbumKey)
  }
  private func findLibraryAlbums(_ term:String) async throws -> [Album] {
    var native: [Album] = []; var cloud: [Album] = []; var succeeded = false
    var lastError: (any Error)?
    do {
      var request = MusicLibrarySearchRequest(term:term,types:[Album.self]); request.limit = 25
      let response = try await request.response()
      native = try await collect(response.albums,batchSize:25); succeeded = true
      record("Ricerca album locale: completata; elementi=\(native.count)")
    } catch { if Task.isCancelled { throw CancellationError() }; lastError=error; recordFailure(error,stage:"Ricerca album locale") }
    do {
      let reader = MusicCloudLibrary(fetch:{ [weak self] request in
        guard let self else { throw CancellationError() }
        return try await self.withTokenRecovery {
          let response = try await MusicDataRequest(urlRequest:request).response()
          return .init(data:response.data,status:response.urlResponse.statusCode)
        }
      })
      let response = try await reader.searchAlbums(Album.self,term:term)
      cloud = response.items; succeeded = true
      record("Ricerca album cloud: completata; elementi=\(cloud.count); pagine=\(response.pages)")
    } catch { if Task.isCancelled { throw CancellationError() }; lastError=error; recordFailure(error,stage:"Ricerca album cloud") }
    guard succeeded else { throw lastError ?? MusicPortError.emptyCollection }
    return MusicCloudLibrary.combining(cloud,local:native)
  }
  func searchLibraryAlbums() async {
    guard authorization == .authorized else { return }
    let revision = UUID(); albumSearchRevision = revision
    let term = libraryAlbumQuery.trimmingCharacters(in:.whitespacesAndNewlines)
    libraryAlbumMatches = []
    guard !term.isEmpty else { searchingLibraryAlbums = false; return }
    searchingLibraryAlbums = true
    defer { if albumSearchRevision == revision { searchingLibraryAlbums = false } }
    do {
      let matches = try await findLibraryAlbums(term)
      guard revision == albumSearchRevision, !Task.isCancelled else { return }
      libraryAlbumMatches = matches
      rememberLibraryAlbums(matches)
    } catch {
      if Task.isCancelled { return }
      if revision == albumSearchRevision { recordFailure(error,stage:"Ricerca album"); self.error = accessMessage(error) }
    }
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
    guard !term.isEmpty else { results=[];searchAlbums=[];searchArtists=[];searchPlaylists=[];searchingCatalog=false;return }
    searchingCatalog=true
    defer {if searchRevision == revision {searchingCatalog=false}}
    do {
      var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self,Album.self,Artist.self,Playlist.self]); request.limit = 25
      let searchRequest = request
      let response = try await withTokenRecovery { try await searchRequest.response() }
      guard searchRevision == revision else { return }
      results = Array(response.songs); searchAlbums=Array(response.albums);searchArtists=Array(response.artists);searchPlaylists=Array(response.playlists);error = nil; record("Ricerca catalogo: riuscita")
    } catch { if searchRevision == revision { recordFailure(error,stage:"Ricerca catalogo"); self.error = accessMessage(error) } }
  }
  func refreshHome() async {
    async let library:Void=refresh()
    async let discovery:Void=refreshDiscovery()
    _ = await (library,discovery)
  }
  func refreshDiscovery() async {
    if isPlayerFixture {return}
    guard MusicAuthorization.currentStatus == .authorized,!loadingDiscovery else{return}
    loadingDiscovery=true;defer{loadingDiscovery=false}
    var failures:[String]=[]
    do { var request=MusicRecentlyPlayedRequest<MusicKit.Song>();request.limit=20
      let response=try await request.response();try Task.checkCancellation();recentSongs=Array(response.items)
    } catch {if Task.isCancelled {return};recordFailure(error,stage:"Recenti");failures.append("Recenti non disponibili.")}
    do {var request=MusicPersonalRecommendationsRequest();request.limit=5
      let response=try await request.response();try Task.checkCancellation();recommendations=Array(response.recommendations)
    } catch {if Task.isCancelled {return};recordFailure(error,stage:"Consigli");failures.append("Consigli personali non disponibili.")}
    discoveryError=failures.isEmpty ? nil:failures.joined(separator:" ")
  }
  func collectionTracks(album:Album?,playlist:Playlist?) async throws -> [Track] {
    if let album {let detail=try await album.with([.tracks]);return try await collect(detail.tracks ?? [])}
    if let playlist {let detail=try await playlist.with([.tracks]);return try await collect(detail.tracks ?? [])}
    return []
  }
  func playCollectionTrack(album:Album?,track:Track) async {
    if let album {await startPlayback(queue:.init(album:album,startingAt:track),origin:"Traccia album")}

  }
  func playlistEntries(_ playlist:Playlist) async throws -> [Playlist.Entry] {
    let detail=try await playlist.with([.entries]);return try await collect(detail.entries ?? [])
  }
  func playPlaylistEntry(_ playlist:Playlist,entry:Playlist.Entry) async {
    await startPlayback(queue:.init(playlist:playlist,startingAt:entry),origin:"Traccia playlist")
  }
  func saveAlbum(_ album:Album) async {
    do {try await MusicLibrary.shared.add(album);await refresh();notice="Richiesta di salvataggio inviata ad Apple Music."}
    catch {self.error=accessMessage(error)}
  }
  func refreshFavorites() async {
    if isPlayerFixture {return}
    guard !loadingFavorites else {return};loadingFavorites=true;defer{loadingFavorites=false}
    let reader=MusicCloudLibrary(fetch:{request in
      var request=request
      var parts=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
      parts.queryItems=(parts.queryItems ?? []).filter{$0.name != "extend"} + [.init(name:"extend",value:"inFavorites")]
      request.url=parts.url
      let response=try await MusicDataRequest(urlRequest:request).response()
      return .init(data:try MusicFavoriteRequest.favoritePage(response.data,status:response.urlResponse.statusCode),status:200)
    })
    var failures:[String]=[]
    do {favoriteSongs=try await reader.load(MusicKit.Song.self,resource:.songs).items}
    catch {if Task.isCancelled{return};failures.append("Brani preferiti non verificabili.")}
    do {favoriteAlbums=try await reader.load(Album.self,resource:.albums).items}
    catch {if Task.isCancelled{return};failures.append("Album preferiti non verificabili.")}
    do {favoritePlaylists=try await reader.load(Playlist.self,resource:.playlists).items}
    catch {if Task.isCancelled{return};failures.append("Playlist preferite non verificabili.")}
    do {favoriteArtists=try await AppleArtistService.favorites()}
    catch {if Task.isCancelled{return};failures.append("Artisti preferiti non verificabili.")}
    favoritesFailure=failures.isEmpty ? nil:failures.joined(separator:" ") + " Riprova o verifica nell’app Musica."
  }
  func artistDetails(_ artist:Artist) async throws -> (albums:[Album],songs:[MusicKit.Song]) {
    if artist.id.rawValue.hasPrefix("r.") {
      let detail=try await artist.with([.albums])
      return (try await collect(detail.albums ?? []),[])
    }
    let detail=try await artist.with([.albums,.topSongs])
    return (try await collect(detail.albums ?? []),try await collect(detail.topSongs ?? []))
  }
  func invalidateCatalogSearch() {
    searchRevision=UUID();searchingCatalog=false
    results=[];searchAlbums=[];searchArtists=[];searchPlaylists=[]
  }
  func favoriteStatus(type:String,id:String) async -> Bool? {
    guard ["songs","albums","artists","playlists"].contains(type),!id.isEmpty,
      id.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0)}) else {return nil}
    let key=type+":"+id
    do {
      let scope:String
      if id.hasPrefix("i.") || id.hasPrefix("l.") || id.hasPrefix("p.") || id.hasPrefix("r.") {scope="me/library"}
      else {scope="catalog/" + (try await MusicDataRequest.currentCountryCode)}
      var request=URLRequest(url:URL(string:"https://api.music.apple.com/v1/\(scope)/\(type)/\(id)?extend=inFavorites")!,cachePolicy:.reloadIgnoringLocalCacheData)
      request.timeoutInterval=15
      let response=try await MusicDataRequest(urlRequest:request).response()
      let state=try MusicFavoriteRequest.state(from:response.data,status:response.urlResponse.statusCode)
      favoriteStates[key]=state;return state
    } catch {favoriteStates[key]=nil;return nil}
  }
  func requestFavorite(type:String,id:String) async {
    guard !sendingFavorite else {return};sendingFavorite=true;defer{sendingFavorite=false}
    do {
      var catalogID=id
      if id.hasPrefix("i.") || id.hasPrefix("l.") || id.hasPrefix("p.") || id.hasPrefix("r.") {
        guard ["songs","albums","artists","playlists"].contains(type) else {throw MusicPortError.emptyCollection}
        let url=URL(string:"https://api.music.apple.com/v1/me/library/\(type)/\(id)/catalog")!
        let response=try await MusicDataRequest(urlRequest:URLRequest(url:url)).response()
        catalogID=try MusicFavoriteRequest.catalogID(from:response.data,status:response.urlResponse.statusCode)
      }
      let request=try MusicFavoriteRequest.request(type:type,id:catalogID)
      let response=try await MusicDataRequest(urlRequest:request).response()
      guard response.urlResponse.statusCode == 202 else {throw MusicFavoriteRequest.Failure.invalidResponse}
      let confirmed=await favoriteStatus(type:type,id:id)
      notice=confirmed == true ? "Preferito confermato da Apple Music. Per rimuoverlo usa l’app Musica.":"Apple ha accettato la richiesta, ma lo stato non è ancora confermato. Verifica nell’app Musica prima di riprovare."
    } catch {recordFailure(error,stage:"Preferiti");self.error=accessMessage(error)}
  }
  private func activateAudio() throws {
    beforePlayback?()
    let session=AVAudioSession.sharedInstance()
    try session.setCategory(.playback,mode:.default,policy:.longFormAudio)
    try session.setActive(true)
  }
  func play(_ song: MusicKit.Song, in list: [MusicKit.Song]) async {
    guard !preparingPlayback else {record("Brano: preparazione già in corso");return}
    activeCollectionID=nil;activeCollectionRowID=nil;activeCollectionQueueEntryID=nil
    let values = list.isEmpty ? [song] : list
    rememberArtwork(values)
    nowPlaying=song;duration=song.duration ?? 0;position=0
    record("Selezione brano: parametri=\(song.playParameters != nil); elementi=\(values.count)")
    await startPlayback(queue:ApplicationMusicPlayer.Queue(for:values,startingAt:song),origin:"Brano")
  }
  func play(album: Album) async {
    guard !preparingPlayback else{return};activeCollectionID=AppleCollection.album(album).id
    activeCollectionRowID=nil;activeCollectionQueueEntryID=nil
    record("Selezione album: parametri=\(album.playParameters != nil)")
    // Let MusicKit expand the album, retaining its playback context and lazy loading.
    await startPlayback(queue:ApplicationMusicPlayer.Queue(for:[album]),origin:"Album")
  }
  func play(playlist: Playlist) async {
    guard !preparingPlayback else{return};activeCollectionID=AppleCollection.playlist(playlist).id
    activeCollectionRowID=nil;activeCollectionQueueEntryID=nil
    record("Selezione playlist: parametri=\(playlist.playParameters != nil)")
    // Do not flatten library playlist tracks into detached Song values.
    await startPlayback(queue:ApplicationMusicPlayer.Queue(for:[playlist]),origin:"Playlist")
  }
  func startPlayback(queue: ApplicationMusicPlayer.Queue, origin: String,shuffle:Bool?=nil) async {
    guard !preparingPlayback else { record("\(origin): preparazione già in corso"); return }
    preparingPlayback = true; defer { preparingPlayback = false }
    let intent=UUID();playbackIntent=intent;showPlayer=true;playbackFailure=nil
    var stage = "Sessione audio"
    do {
      error = nil
      try activateAudio()
      beforePlayback?()
      player.stop()
      player.queue = queue
      if let shuffle {player.state.shuffleMode=shuffle ? .songs:.off}
      stage = "Preparazione audio \(origin)"
      record("\(stage): avviata; coda nativa")
      try await player.prepareToPlay()
      try Task.checkCancellation()
      guard intent==playbackIntent else {record("\(stage): richiesta interrotta dall’utente");return}
      record("\(stage): riuscita")
      stage = "Avvio audio \(origin)"
      try await player.play()
      guard intent==playbackIntent else {player.pause();record("\(stage): richiesta interrotta dall’utente");return}
      guard try await observeStart(intent:intent,stage:stage) else {return}
    } catch {
      guard intent==playbackIntent else {record("\(stage): richiesta interrotta dall’utente");return}
      recordFailure(error,stage:stage)
      if Task.isCancelled { player.stop(); return }
      playbackFailure=playbackMessage(error)
    }
  }
  // play() returning is not proof that audio started. Observe the native state;
  // an explicit pause cancels the pending intent instead of being reported as an error.
  private func observeStart(intent:UUID,stage:String) async throws -> Bool {
    let observed=try await PlaybackStartObservation.wait(current:{intent==self.playbackIntent},playing:{
      self.syncPlaybackState();return self.player.state.playbackStatus == .playing
    })
    switch observed {
    case .playing:record("\(stage): riproduzione osservata; elementi=\(player.queue.entries.count)");return true
    case .cancelled:record("\(stage): richiesta interrotta dall’utente");return false
    case .unconfirmed:break
    }
    record("\(stage): avvio non confermato; stato=\(player.state.playbackStatus); preparato=\(player.isPreparedToPlay); elementi=\(player.queue.entries.count)")
    playbackFailure="Apple Music è rimasta in pausa dopo la richiesta. Premi Riprova; se persiste condividi la diagnostica."
    return false
  }
  func pause() {if isPlayerFixture {playing=false;return};playbackIntent=UUID();player.pause();syncPlaybackState()}
  private func syncPlaybackState() {
    queueSongs = player.queue.entries.compactMap { entry in
      if case .song(let song) = entry.item { return song }; return nil
    }
    playing = player.state.playbackStatus == .playing
    if let entry=player.queue.currentEntry {
      if let previous=activeCollectionQueueEntryID,previous != entry.id {activeCollectionRowID=nil}
      activeCollectionQueueEntryID=entry.id
    }
    if let entry = player.queue.currentEntry, case .song(let song) = entry.item {
      let changed=nowPlaying?.id != song.id
      rememberArtwork([song])
      artwork.remember(id:song.id.rawValue,url:entry.artwork?.url(width:900,height:900))
      nowPlaying = song; duration = song.duration ?? 0
      if changed || artwork.status[song.id.rawValue]==nil {Task{await artwork.load(id:song.id.rawValue)}}
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
    if playing { pause() }
    else { await resume() }
  }
  func resume() async {
    if isPlayerFixture {playing=true;return}
    guard !preparingPlayback else { return }
    preparingPlayback = true; defer { preparingPlayback = false }
    let intent=UUID();playbackIntent=intent;playbackFailure=nil
    do {
      try activateAudio()
      if !player.isPreparedToPlay { try await player.prepareToPlay() }
      guard intent==playbackIntent else {return}
      try await player.play()
      guard intent==playbackIntent else {player.pause();return}
      _ = try await observeStart(intent:intent,stage:"Ripresa audio")
    } catch {if intent==playbackIntent && !Task.isCancelled {recordFailure(error,stage:"Ripresa audio");playbackFailure=playbackMessage(error)}}
  }
  func next() async { do { try await player.skipToNextEntry() } catch { recordFailure(error,stage:"Brano successivo"); self.error = playbackMessage(error) } }
  func previous() async { do { try await player.skipToPreviousEntry() } catch { recordFailure(error,stage:"Brano precedente"); self.error = playbackMessage(error) } }
  func add(_ song: MusicKit.Song) async {
    do { try await MusicLibrary.shared.add(song); await refresh() }
    catch { self.error = error.localizedDescription }
  }
  func enqueue(_ song: MusicKit.Song, next: Bool) async {
    do {
      rememberArtwork([song])
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

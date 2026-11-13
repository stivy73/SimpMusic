import Foundation
import Combine
@preconcurrency import MusicKit

@MainActor final class MusicSearchStore:ObservableObject {
  let personal:Bool
  let songs=BrowsePage<Song>(),albums=BrowsePage<Album>(),artists=BrowsePage<Artist>(),playlists=BrowsePage<Playlist>()
  @Published var query=""
  @Published private(set) var submitted=""
  @Published var category:BrowseKind?
  @Published private(set) var history:[String]
  private var job:Task<Void,Never>?
  private var historyKey:String {personal ? "personalSearchHistory":"catalogSearchHistory"}
  init(personal:Bool) {
    self.personal=personal;history=UserDefaults.standard.stringArray(forKey:personal ? "personalSearchHistory":"catalogSearchHistory") ?? []
    #if DEBUG && BROWSE_LAYOUT_FIXTURE
    if !personal && history.isEmpty {history=["Seal","Rock","Jazz"]}
    #endif
  }
  func invalidate() {job?.cancel();job=nil;submitted="";songs.reset();albums.reset();artists.reset();playlists.reset()}
  func clearHistory() {history=[];UserDefaults.standard.removeObject(forKey:historyKey)}
  func removeHistory(_ term:String) {
    history=BrowseHistory.removing(term,from:history);UserDefaults.standard.set(history,forKey:historyKey)
  }
  func submit(_ value:String?=nil) {
    let term=(value ?? query).trimmingCharacters(in:.whitespacesAndNewlines)
    invalidate();query=term;guard !term.isEmpty else{return};submitted=term
    if !personal {history=BrowseHistory.adding(term,to:history);UserDefaults.standard.set(history,forKey:historyKey)}
    job=Task {await loadAll(term)}
  }
  func retry(_ kind:BrowseKind) {let term=submitted;guard !term.isEmpty else{return};Task{await load(kind,term:term)}}
  private func loadAll(_ term:String) async {
    async let s:Void=load(.songs,term:term)
    async let a:Void=load(.albums,term:term)
    async let p:Void=load(.playlists,term:term)
    async let r:Void=load(.artists,term:term)
    _ = await(s,a,p,r)
  }
  private func load(_ kind:BrowseKind,term:String) async {
    // A queued retry must not resurrect an older query.
    guard term==submitted,!Task.isCancelled else{return}
    switch kind {
    case .songs:await songs.load{try await self.fetchSongs(term)}
    case .albums:await albums.load{try await self.fetchAlbums(term)}
    case .playlists:await playlists.load{try await self.fetchPlaylists(term)}
    case .artists:await artists.load{try await self.fetchArtists(term)}
    }
  }
  private static func recover<T:Sendable>(_ operation:@Sendable () async throws -> T) async throws -> T {
    try await MusicAccessRecovery(isDeveloperTokenFailure:MusicLibraryModel.isDeveloperTokenFailure,
      renewDeveloperToken:{_ = try await MusicDataRequest.tokenProvider.developerToken(options:.ignoreCache)}).perform(operation)
  }
  private func batch<T:MusicItem & Decodable & Sendable>(_ page:MusicItemCollection<T>)->BrowseBatch<T> {
    var continuation:(@MainActor () async throws -> BrowseBatch<T>)?
    if page.hasNextBatch {
      continuation = { [weak self] in
        guard let self else {throw CancellationError()}
        guard let following=try await Self.recover({try await page.nextBatch(limit:25)}) else {return BrowseBatch<T>(items:[])}
        return self.batch(following)
      }
    }
    return BrowseBatch(items:Array(page),next:continuation)
  }
  private func personalBatch<T:MusicItem & Decodable & Sendable>(
    _ type:T.Type,resource:MusicCloudProbe.Resource,term:String,
    native:@Sendable () async throws -> MusicItemCollection<T>
  ) async throws -> BrowseBatch<T> {
    var values:[T]=[],succeeded=false,failures=0
    do {
      var page=try await Self.recover(native);values=Array(page)
      while page.hasNextBatch {try Task.checkCancellation();guard let next=try await page.nextBatch(limit:100) else{break};values=BrowseHistory.merging(values,Array(next));page=next}
      succeeded=true
    } catch {if Task.isCancelled {throw CancellationError()};failures+=1}
    do {
      let cloud=MusicCloudLibrary(fetch:{request in
        let response=try await Self.recover {try await MusicDataRequest(urlRequest:request).response()}
        return .init(data:response.data,status:response.urlResponse.statusCode)
      })
      let result=try await cloud.search(type,resource:resource,term:term)
      values=BrowseHistory.merging(result.items,values);succeeded=true
    } catch {if Task.isCancelled {throw CancellationError()};failures+=1}
    guard succeeded else {throw SearchFailure.personalUnavailable}
    return BrowseBatch(items:values,warning:failures>0 ? "Una parte della ricerca personale non è stata verificata. Riprova per completarla." : nil)
  }
  enum SearchFailure:LocalizedError {case personalUnavailable
    var errorDescription:String? {"Ricerca nella libreria personale non disponibile. Riprova o verifica il collegamento Apple Music."}
  }
  private func fetchSongs(_ term:String) async throws -> BrowseBatch<Song> {
    if personal {
      return try await personalBatch(Song.self,resource:.songs,term:term) {
        var request=MusicLibrarySearchRequest(term:term,types:[Song.self]);request.limit=25
        return try await request.response().songs
      }
    }
    var request=MusicCatalogSearchRequest(term:term,types:[Song.self]);request.limit=25
    let submittedRequest=request
    return batch(try await Self.recover {try await submittedRequest.response().songs})
  }
  private func fetchAlbums(_ term:String) async throws -> BrowseBatch<Album> {
    if personal {
      return try await personalBatch(Album.self,resource:.albums,term:term) {
        var request=MusicLibrarySearchRequest(term:term,types:[Album.self]);request.limit=25
        return try await request.response().albums
      }
    }
    var request=MusicCatalogSearchRequest(term:term,types:[Album.self]);request.limit=25
    let submittedRequest=request
    return batch(try await Self.recover {try await submittedRequest.response().albums})
  }
  private func fetchPlaylists(_ term:String) async throws -> BrowseBatch<Playlist> {
    if personal {
      return try await personalBatch(Playlist.self,resource:.playlists,term:term) {
        var request=MusicLibrarySearchRequest(term:term,types:[Playlist.self]);request.limit=25
        return try await request.response().playlists
      }
    }
    var request=MusicCatalogSearchRequest(term:term,types:[Playlist.self]);request.limit=25
    let submittedRequest=request
    return batch(try await Self.recover {try await submittedRequest.response().playlists})
  }
  private func fetchArtists(_ term:String) async throws -> BrowseBatch<Artist> {
    if personal {
      return try await personalBatch(Artist.self,resource:.artists,term:term) {
        var request=MusicLibrarySearchRequest(term:term,types:[Artist.self]);request.limit=25
        return try await request.response().artists
      }
    }
    var request=MusicCatalogSearchRequest(term:term,types:[Artist.self]);request.limit=25
    let submittedRequest=request
    return batch(try await Self.recover {try await submittedRequest.response().artists})
  }
}

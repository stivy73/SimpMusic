import Foundation
import Combine
@preconcurrency import MusicKit

enum AppleCollection:Identifiable {
  case album(Album),playlist(Playlist)
  var id:String {switch self {case .album(let v):"album:"+v.id.rawValue;case .playlist(let v):"playlist:"+v.id.rawValue}}
  var identity:CollectionIdentity {switch self {
  case .album(let v):.init(title:v.title,artist:v.artistName,artwork:v.artwork?.url(width:1000,height:1000),url:v.url,kind:"Album")
  case .playlist(let v):.init(title:v.name,artist:v.curatorName ?? "Playlist",artwork:v.artwork?.url(width:1000,height:1000),url:v.url,kind:"Playlist")
  }}
}
struct CollectionIdentity {
  let title:String,artist:String
  let artwork:URL?,url:URL?
  let kind:String
}
struct AppleCollectionRow:Identifiable {
  let id:String
  let track:Track?
  let entry:Playlist.Entry?
  var title:String {track?.title ?? entry?.title ?? "Brano non disponibile"}
  var artist:String {track?.artistName ?? entry?.artistName ?? ""}
  var artwork:URL? {(track?.artwork ?? entry?.artwork)?.url(width:300,height:300)}
  var durationSeconds:Double? {track?.duration ?? entry?.duration}
  var playable:Bool {(track?.playParameters ?? entry?.playParameters) != nil}
  var song:Song? {if case .song(let song)=track {return song};if case .song(let song)=entry?.item {return song};return nil}
  var mediaID:String? {track?.id.rawValue ?? entry?.item.map {switch $0 {case .song(let v):v.id.rawValue;case .musicVideo(let v):v.id.rawValue;@unknown default:""}}}
}
struct AppleCollectionDetail {
  let identity:CollectionIdentity
  let year:String?
  let description:String
  let songs:[AppleCollectionRow]
  var durationSeconds:Double? {
    guard songs.allSatisfy({$0.durationSeconds != nil}) else{return nil}
    return songs.reduce(0){$0+($1.durationSeconds ?? 0)}
  }
}
enum MusicRead {
  static func perform<T:Sendable>(_ action:@Sendable () async throws -> T) async throws -> T {
    try await MusicAccessRecovery(isDeveloperTokenFailure:MusicLibraryModel.isDeveloperTokenFailure,
      renewDeveloperToken:{_ = try await MusicDataRequest.tokenProvider.developerToken(options:.ignoreCache)}).perform(action)
  }
  static func all<T:MusicItem & Decodable & Sendable>(_ initial:MusicItemCollection<T>) async throws -> [T] {
    var page=initial,values=Array(initial)
    while page.hasNextBatch {try Task.checkCancellation();let current=page
      guard let next=try await perform({try await current.nextBatch(limit:100)}) else{break};values.append(contentsOf:next);page=next
    };return values
  }
}
extension MusicLibraryModel {
  func collectionDetail(_ collection:AppleCollection) async throws -> AppleCollectionDetail {
    #if DEBUG && BROWSE_LAYOUT_FIXTURE
    if isPlayerFixture {return .init(identity:collection.identity,year:"1988",description:"Storie e viaggi nell’album di prova.",songs:songs.enumerated().map{.init(id:"fixture-\($0.offset)",track:.song($0.element),entry:nil)})}
    #endif
    switch collection {
    case .album(let album):
      let detail=try await MusicRead.perform{try await album.with([.tracks])}
      let values=try await MusicRead.all(detail.tracks ?? [])
      return .init(identity:AppleCollection.album(detail).identity,year:detail.releaseDate.map{String(Calendar.current.component(.year,from:$0))},
        description:detail.editorialNotes?.standard ?? detail.editorialNotes?.short ?? "Nessuna descrizione",
        songs:values.enumerated().map{.init(id:"track-\($0.offset)",track:$0.element,entry:nil)})
    case .playlist(let playlist):
      let detail=try await MusicRead.perform{try await playlist.with([.entries])}
      let values=try await MusicRead.all(detail.entries ?? [])
      return .init(identity:AppleCollection.playlist(detail).identity,year:nil,description:detail.standardDescription ?? detail.shortDescription ?? "Nessuna descrizione",
        songs:values.map{.init(id:"\($0.position):\($0.id.rawValue)",track:nil,entry:$0)})
    }
  }
  func playCollection(_ collection:AppleCollection,row:AppleCollectionRow?,shuffle:Bool) async {
    guard !preparingPlayback else{return}
    #if DEBUG && BROWSE_LAYOUT_FIXTURE
    if isPlayerFixture {activeCollectionID=collection.id;activeCollectionRowID=row?.id;activeCollectionQueueEntryID=nil;playing=true;showPlayer=true;return}
    #endif
    activeCollectionID=collection.id;activeCollectionRowID=row?.id;activeCollectionQueueEntryID=nil
    switch collection {
    case .album(let album):
      let queue:ApplicationMusicPlayer.Queue
      if let track=row?.track {queue = .init(album:album,startingAt:track)} else{queue = .init(for:[album])}
      await startPlayback(queue:queue,origin:"Album",shuffle:shuffle)
    case .playlist(let playlist):
      let queue:ApplicationMusicPlayer.Queue
      if let entry=row?.entry {queue = .init(playlist:playlist,startingAt:entry)} else{queue = .init(for:[playlist])}
      await startPlayback(queue:queue,origin:"Playlist",shuffle:shuffle)
    }
  }
  func enqueueCollection(_ collection:AppleCollection,next:Bool=false) async {
    do {
      switch collection {
      case .album(let v):try await player.queue.insert(v,position:next ? .afterCurrentEntry:.tail)
      case .playlist(let v):try await player.queue.insert(v,position:next ? .afterCurrentEntry:.tail)
      }
      notice="Raccolta aggiunta alla coda."
    } catch {self.error=error.localizedDescription}
  }
}

@MainActor final class ApplePlaylistService:ObservableObject {
  @Published private(set) var busy=false
  private let registryKey="appleMusic.createdPlaylists.v1"
  func createdHere(_ playlist:Playlist)->Bool {(UserDefaults.standard.stringArray(forKey:registryKey) ?? []).contains(playlist.id.rawValue)}
  func create(name:String,songs:[Song]) async throws -> Playlist {
    guard !busy else{throw PlaylistPolicy.Failure.changed};busy=true;defer{busy=false}
    let title=try PlaylistPolicy.name(name)
    // A write is never retried automatically: a timeout can follow a successful create.
    let playlist=try await MusicLibrary.shared.createPlaylist(name:title,items:songs)
    var ids=Set(UserDefaults.standard.stringArray(forKey:registryKey) ?? []);ids.insert(playlist.id.rawValue)
    UserDefaults.standard.set(Array(ids),forKey:registryKey);return playlist
  }
  func add(_ songs:[Song],to playlist:Playlist) async throws {
    guard !busy else{throw PlaylistPolicy.Failure.changed};busy=true;defer{busy=false}
    guard !songs.isEmpty else{throw MusicPortError.emptyCollection}
    guard playlist.id.rawValue.hasPrefix("p.") else{throw PlaylistPolicy.Failure.readOnly}
    let url=URL(string:"https://api.music.apple.com/v1/me/library/playlists/\(playlist.id.rawValue)")!
    let response=try await MusicRead.perform{try await MusicDataRequest(urlRequest:URLRequest(url:url)).response()}
    guard try PlaylistPolicy.canAdd(data:response.data,status:response.urlResponse.statusCode,id:playlist.id.rawValue) else{throw PlaylistPolicy.Failure.readOnly}
    // Add one at a time; report exactly what was accepted if a later write fails.
    var completed=0
    do {for song in songs {try Task.checkCancellation();_ = try await MusicLibrary.shared.add(song,to:playlist);completed+=1}}
    catch {throw PlaylistWriteFailure(completed:completed,total:songs.count)}
  }
  func edit(_ playlist:Playlist,name:String?=nil,entries:[Playlist.Entry]?=nil,expected:[Playlist.Entry]) async throws -> Playlist {
    guard !busy else{throw PlaylistPolicy.Failure.changed};busy=true;defer{busy=false}
    guard createdHere(playlist) else{throw PlaylistPolicy.Failure.notCreatedHere}
    let title=try name.map(PlaylistPolicy.name)
    if entries != nil {guard expected.allSatisfy({$0.playParameters != nil}),entries!.allSatisfy({$0.playParameters != nil}) else{throw PlaylistPolicy.Failure.incomplete}}
    var lookup=MusicLibraryRequest<Playlist>();lookup.filter(matching:\.id,equalTo:playlist.id);lookup.limit=1
    let lookupRequest=lookup
    guard let latest=try await MusicRead.perform({try await lookupRequest.response()}).items.first else{throw PlaylistPolicy.Failure.changed}
    let detail=try await MusicRead.perform{try await latest.with([.entries])}
    let current=try await MusicRead.all(detail.entries ?? [])
    try PlaylistPolicy.requireSnapshot(expected.map{Self.fingerprint($0)},current:current.map{Self.fingerprint($0)})
    if let entries {return try await MusicLibrary.shared.edit(playlist,name:title,items:entries)}
    return try await MusicLibrary.shared.edit(playlist,name:title)
  }
  private static func fingerprint(_ entry:Playlist.Entry)->String {
    "\(entry.position):\(entry.id.rawValue):\(entry.title)"
  }
  struct PlaylistWriteFailure:LocalizedError {
    let completed:Int,total:Int
    var errorDescription:String? {"Aggiunta interrotta: \(completed) di \(total) brani confermati. Controlla la playlist in Musica prima di riprovare, per evitare duplicati."}
  }
}

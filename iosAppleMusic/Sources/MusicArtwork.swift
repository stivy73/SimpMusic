import Foundation
@preconcurrency import MusicKit

enum MusicArtworkResolver {
  static func resolve(_ id:String) async throws -> URL? {
    #if DEBUG && ARTWORK_LAYOUT_FIXTURE
    if let url=await MusicArtworkFixture.url(id) {return url}
    #endif
    if ArtworkIdentity.isCatalogSong(id) {return try await catalog(id)}
    guard ArtworkIdentity.isLibrarySong(id) else{return nil}
    // Library uploads may have their own cover and no catalog counterpart.
    let url=URL(string:"https://api.music.apple.com/v1/me/library/songs/\(id)")!
    let response=try await MusicRead.perform{try await MusicDataRequest(urlRequest:URLRequest(url:url)).response()}
    let values=try MediaCatalogRequest.items(Song.self,data:response.data,status:response.urlResponse.statusCode)
    guard let song=values.first(where:{$0.id.rawValue==id}) else{return nil}
    if let own=song.artwork?.url(width:900,height:900) {return own}
    if let album=try? await relatedAlbum(song) {return album}
    let mapping=URL(string:"https://api.music.apple.com/v1/me/library/songs/\(id)/catalog")!
    let mapped=try await MusicRead.perform{try await MusicDataRequest(urlRequest:URLRequest(url:mapping)).response()}
    let catalogID=try MusicFavoriteRequest.catalogID(from:mapped.data,status:mapped.urlResponse.statusCode)
    guard ArtworkIdentity.isCatalogSong(catalogID) else{return nil}
    return try await catalog(catalogID)
  }
  private static func catalog(_ id:String) async throws -> URL? {
    let country=try await MusicDataRequest.currentCountryCode
    let request=try MediaCatalogRequest.request(ids:[id],storefront:country)
    let response=try await MusicRead.perform{try await MusicDataRequest(urlRequest:request).response()}
    let values=try MediaCatalogRequest.items(Song.self,data:response.data,status:response.urlResponse.statusCode)
    guard let song=values.first(where:{$0.id.rawValue==id}) else{return nil}
    if let own=song.artwork?.url(width:900,height:900) {return own}
    return try await relatedAlbum(song)
  }
  private static func relatedAlbum(_ song:Song) async throws -> URL? {
    let detail=try await MusicRead.perform{try await song.with([.albums])}
    return detail.albums?.first?.artwork?.url(width:900,height:900)
  }
}

extension MusicLibraryModel {
  func rememberArtwork(_ songs:[Song]) {for song in songs {artwork.remember(id:song.id.rawValue,url:song.artwork?.url(width:900,height:900))}}
  func artworkURL(_ song:Song)->URL? {artwork.url(id:song.id.rawValue,native:song.artwork?.url(width:900,height:900))}
  func artworkID(_ entry:MusicPlayer.Queue.Entry)->String? {entry.item?.id.rawValue ?? (entry.transientItem as? Song)?.id.rawValue}
  func artworkURL(_ entry:MusicPlayer.Queue.Entry)->URL? {
    let native=entry.artwork?.url(width:900,height:900)
    return artworkID(entry).flatMap{artwork.url(id:$0,native:native)} ?? PlaybackArtworkURL.resolve(native)
  }
  func loadArtwork(_ entry:MusicPlayer.Queue.Entry) async {
    guard let id=artworkID(entry) else{return}
    artwork.remember(id:id,url:entry.artwork?.url(width:900,height:900))
    if case .song(let song)=entry.item {rememberArtwork([song])}
    else if let song=entry.transientItem as? Song {rememberArtwork([song])}
    await artwork.load(id:id)
  }
  var playbackQueueEntries:[MusicPlayer.Queue.Entry] {
    #if DEBUG && ARTWORK_LAYOUT_FIXTURE
    if isPlayerFixture {return artworkFixtureQueue}
    #endif
    return Array(player.queue.entries)
  }
  var artworkReport:String {
    guard let id=nowPlaying?.id.rawValue else{return "Copertina: nessun brano corrente"}
    return "Copertina player: ID \(id); nativa=\(nowPlaying?.artwork != nil); \(artwork.status[id] ?? "non richiesta"); coda=\(playbackQueueEntries.count)"
  }
}

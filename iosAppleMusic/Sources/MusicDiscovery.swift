import Foundation
import Combine
@preconcurrency import MusicKit

enum AppleDiscoveryKind {case song,album,playlist,artist}
@MainActor struct AppleShelf:Identifiable {
  let id:String,title:String
  var subtitle=""
  var avatar:URL?=nil
  let items:[MusicBrowseItem]
  var load:(@MainActor () async throws -> BrowseBatch<MusicBrowseItem>)?=nil
}

@MainActor enum AppleDiscoveryService {
  static func batch<T:MusicItem & Decodable & Sendable>(_ page:MusicItemCollection<T>,map:@escaping @Sendable (T)->MusicBrowseItem?)->BrowseBatch<MusicBrowseItem> {
    var next:(@MainActor () async throws -> BrowseBatch<MusicBrowseItem>)?
    if page.hasNextBatch {next={
      guard let following=try await MusicRead.perform({try await page.nextBatch(limit:25)}) else{return .init(items:[])}
      return batch(following,map:map)
    }}
    return .init(items:page.compactMap(map),next:next)
  }
  static func recentPage() async throws -> BrowseBatch<MusicBrowseItem> {
    var request=MusicRecentlyPlayedRequest<Song>();request.limit=25
    let value=request
    return batch(try await MusicRead.perform{try await value.response()}.items,map:MusicBrowseItem.song)
  }
  static func genres() async throws -> [Genre] {
    var request=MusicCatalogResourceRequest<Genre>();request.limit=100
    let value=request
    let response=try await MusicRead.perform{try await value.response()}
    return try await MusicRead.all(response.items)
  }
  static func charts(_ genre:Genre?) async throws -> [AppleShelf] {
    var request=MusicCatalogChartsRequest(genre:genre,types:[Song.self,Album.self,Playlist.self]);request.limit=25
    let value=request
    let response=try await MusicRead.perform{try await value.response()}
    return response.songCharts.map {chart in AppleShelf(id:"songs:"+chart.id,title:chart.title,items:chart.items.map(MusicBrowseItem.song),load:{batch(chart.items,map:MusicBrowseItem.song)})}
      + response.albumCharts.map {chart in AppleShelf(id:"albums:"+chart.id,title:chart.title,items:chart.items.map(MusicBrowseItem.album),load:{batch(chart.items,map:MusicBrowseItem.album)})}
      + response.playlistCharts.map {chart in AppleShelf(id:"playlists:"+chart.id,title:chart.title,items:chart.items.map(MusicBrowseItem.playlist),load:{batch(chart.items,map:MusicBrowseItem.playlist)})}
  }
  static func mood(_ mood:MusicMood) async throws -> BrowseBatch<MusicBrowseItem> {
    var request=MusicCatalogSearchRequest(term:mood.query,types:[Playlist.self]);request.limit=25
    let value=request
    return batch(try await MusicRead.perform{try await value.response()}.playlists,map:MusicBrowseItem.playlist)
  }
  static func recommendation(_ value:MusicPersonalRecommendation)->AppleShelf {
    let map:@Sendable (MusicPersonalRecommendation.Item)->MusicBrowseItem?={item in
      switch item {case .album(let v):.album(v);case .playlist(let v):.playlist(v);default:nil}
    }
    return AppleShelf(id:"recommendation:"+value.id.rawValue,title:value.title ?? "Consigliati per te",subtitle:value.reason ?? "",items:value.items.compactMap(map),load:{batch(value.items,map:map)})
  }
}

@MainActor enum AppleArtistService {
  private struct ArtistsPage:Decodable {let data:[Artist]}
  static func favorites() async throws -> [Artist] {
    let reader=MusicCloudLibrary(fetch:{request in
      var request=request
      var parts=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
      parts.queryItems=(parts.queryItems ?? [])+[.init(name:"include",value:"catalog")];request.url=parts.url
      let submitted=request
      let response=try await MusicRead.perform{try await MusicDataRequest(urlRequest:submitted).response()}
      return .init(data:try ArtistFavoriteBridge.references(response.data,status:response.urlResponse.statusCode),status:200)
    })
    let references=try await reader.load(ArtistFavoriteBridge.Reference.self,resource:.artists).items
    let country=try await MusicDataRequest.currentCountryCode
    var result:[Artist]=[]
    for start in stride(from:0,to:references.count,by:100) {
      try Task.checkCancellation()
      var url=URLComponents(string:"https://api.music.apple.com/v1/catalog/\(country)/artists")!
      url.queryItems=[.init(name:"ids",value:references.dropFirst(start).prefix(100).map(\.id).joined(separator:",")),.init(name:"extend",value:"inFavorites")]
      let request=URLRequest(url:url.url!)
      let response=try await MusicRead.perform{try await MusicDataRequest(urlRequest:request).response()}
      let expected=Set(references.dropFirst(start).prefix(100).map(\.id))
      let filtered=try ArtistFavoriteBridge.favorites(response.data,status:response.urlResponse.statusCode,expected:expected)
      result+=try JSONDecoder().decode(ArtistsPage.self,from:filtered).data
    }
    return result
  }
  static func catalog(_ artist:Artist) async throws -> Artist {
    guard artist.id.rawValue.hasPrefix("r.") else{return artist}
    let id=artist.id.rawValue
    guard id.range(of:#"^[A-Za-z0-9._-]+$"#,options:.regularExpression) != nil else{throw MusicPortError.emptyCollection}
    let url=URL(string:"https://api.music.apple.com/v1/me/library/artists/\(id)/catalog")!
    let response=try await MusicRead.perform{try await MusicDataRequest(urlRequest:URLRequest(url:url)).response()}
    let catalogID=try MusicFavoriteRequest.catalogID(from:response.data,status:response.urlResponse.statusCode)
    let request=MusicCatalogResourceRequest<Artist>(matching:\.id,equalTo:MusicItemID(catalogID))
    guard let found=try await MusicRead.perform({try await request.response()}).items.first else{throw MusicPortError.emptyCollection}
    return found
  }
}

@MainActor final class ArtistProfileStore:ObservableObject {
  @Published var artist:Artist?
  @Published var shelves:[AppleShelf]=[]
  @Published var busy=false
  @Published var error:String?
  func load(_ source:Artist) async {
    busy=true;error=nil;defer{busy=false}
    do {
      let value=try await AppleArtistService.catalog(source)
      let detail=try await MusicRead.perform{try await value.with([.albums,.topSongs,.singles,.compilationAlbums,.appearsOnAlbums,.featuredPlaylists,.similarArtists,.station,.latestRelease])}
      try Task.checkCancellation()
      artist=detail
      var result:[AppleShelf]=[]
      func add<T:MusicItem & Decodable & Sendable>(_ id:String,_ title:String,_ items:MusicItemCollection<T>?,map:@escaping @Sendable (T)->MusicBrowseItem?) {
        guard let items,!items.isEmpty else{return}
        result.append(.init(id:id,title:title,items:items.compactMap(map),load:{AppleDiscoveryService.batch(items,map:map)}))
      }
      if let latest=detail.latestRelease {result.append(.init(id:"latest",title:"Ultima uscita",items:[.album(latest)]))}
      add("top","Brani più ascoltati",detail.topSongs,map:MusicBrowseItem.song)
      add("albums","Album",detail.albums,map:MusicBrowseItem.album)
      add("singles","Singoli ed EP",detail.singles,map:MusicBrowseItem.album)
      add("compilations","Raccolte",detail.compilationAlbums,map:MusicBrowseItem.album)
      add("appears","Compare anche in",detail.appearsOnAlbums,map:MusicBrowseItem.album)
      add("playlists","Playlist in evidenza",detail.featuredPlaylists,map:MusicBrowseItem.playlist)
      add("similar","Artisti simili",detail.similarArtists,map:MusicBrowseItem.artist)
      shelves=result
    } catch {if !Task.isCancelled {self.error=error.localizedDescription}}
  }
}

/// Checks small groups on demand. Every source artist remains available through “Altri artisti”.
@MainActor final class ArtistReleaseStore:ObservableObject {
  @Published private(set) var albums:[Album]=[]
  @Published private(set) var busy=false
  @Published private(set) var checked=0
  @Published private(set) var total=0
  @Published private(set) var failures:[Artist]=[]
  private var remaining:[Artist]=[]
  private var revision=UUID()
  private var checkedIDs=Set<Artist.ID>()
  func reset(_ artists:[Artist]) {revision=UUID();remaining=BrowseHistory.merging(artists,[]);total=remaining.count;checked=0;checkedIDs=[];albums=[];failures=[];busy=false}
  var hasMore:Bool {!remaining.isEmpty}
  func retry() async {guard !busy else{return};remaining=BrowseHistory.merging(failures,remaining);failures=[];await more()}
  func more() async {
    guard !busy,!remaining.isEmpty else{return};busy=true;let token=revision
    defer{if token==revision {busy=false}}
    let selected=Array(remaining.prefix(12));remaining.removeFirst(selected.count)
    var completed=Set<Artist.ID>()
    // At most four concurrent reads; no account or write is performed outside MusicKit.
    for offset in stride(from:0,to:selected.count,by:4) {
      if Task.isCancelled || token != revision {break}
      let part=Array(selected.dropFirst(offset).prefix(4))
      let values=await withTaskGroup(of:(Artist,Album?,Bool).self) {group in
        for artist in part {group.addTask {
          do {let catalog=try await AppleArtistService.catalog(artist)
            let value=try await MusicRead.perform{try await catalog.with([.latestRelease])}
            return (artist,value.latestRelease,true)
          } catch {return (artist,nil,false)}
        }}
        var result:[(Artist,Album?,Bool)]=[];for await value in group {result.append(value)};return result
      }
      guard token==revision else{return}
      for (artist,album,success) in values {
        if Task.isCancelled {break}
        completed.insert(artist.id)
        if success {if let album {albums.append(album)}} else {failures.append(artist)}
      }
      checkedIDs.formUnion(completed);checked=checkedIDs.count
    }
    guard token==revision else{return}
    remaining=selected.filter{!completed.contains($0.id)}+remaining
    albums=DiscoveryPolicy.recent(albums,now:Date(),id:{$0.id.rawValue},date:{$0.releaseDate})
  }
}

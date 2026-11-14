import SwiftUI
@preconcurrency import MusicKit

enum BrowseArtworkResolver {
  static func resolve(_ key:String) async throws -> URL? {
    let identity=try BrowseArtworkRequest.identity(key)
    let country=try await MusicRead.perform{try await MusicDataRequest.currentCountryCode}
    func read(_ value:BrowseArtworkRequest.Identity,mapping:Bool=false) async throws -> MusicDataResponse {
      let request=try BrowseArtworkRequest.request(value,country:country,catalogMapping:mapping)
      do {return try await MusicRead.perform{try await MusicDataRequest(urlRequest:request).response()}}
      catch let error as MusicDataRequest.Error {throw BrowseArtworkRequest.Failure.http(error.status)}
    }
    if !(identity.library && identity.kind == .artists) {
      let own=try await read(identity)
      if let url=try BrowseArtworkRequest.artwork(own.data,status:own.urlResponse.statusCode,identity:identity) {return url}
    }
    guard identity.library else{return nil}
    let mapped=try await read(identity,mapping:true)
    guard let catalog=try BrowseArtworkRequest.catalogIdentity(mapped.data,status:mapped.urlResponse.statusCode,source:identity) else{return nil}
    let response=try await read(catalog)
    return try BrowseArtworkRequest.artwork(response.data,status:response.urlResponse.statusCode,identity:catalog)
  }
  static func fallback(_ key:String) async throws -> URL? {
    let identity=try BrowseArtworkRequest.identity(key)
    guard identity.kind == .songs else{return nil}
    return try await MusicArtworkResolver.publicArtwork(identity.id)
  }
}

struct BrowseCover:View {
  @EnvironmentObject var music:MusicLibraryModel
  let item:MusicBrowseItem
  var body:some View {ResolvedBrowseCover(store:music.browseArtwork,id:item.id,native:item.artwork?.url(width:600,height:600))}
}
private struct ResolvedBrowseCover:View {
  @ObservedObject var store:PlaybackArtwork
  let id:String
  let native:URL?
  var body:some View {
    YTPlayerArtwork(url:store.url(id:id,native:native),onLoaded:{store.imageLoaded(id:id,url:$0)},onFailure:{url,error in await store.imageFailed(id:id,url:url,error:error)})
      .aspectRatio(1,contentMode:.fit).clipped()
      .task(id:id+"|"+(native?.absoluteString ?? "")+"|"+store.resetID.uuidString) {
        store.remember(id:id,url:native,replace:false)
        await store.load(id:id)
      }
  }
}

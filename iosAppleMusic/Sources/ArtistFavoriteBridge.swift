import Foundation

enum ArtistFavoriteBridge {
  struct Reference:Decodable,Identifiable,Sendable {let id:String}
  static func favorites(_ data:Data,status:Int,expected:Set<String>) throws -> Data {
    guard status==200,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],
      let items=root["data"] as? [[String:Any]],items.count==expected.count,
      items.allSatisfy({$0["type"] as? String == "artists"}),
      Set(items.compactMap{$0["id"] as? String})==expected else{throw MusicFavoriteRequest.Failure.invalidResponse}
    return try MusicFavoriteRequest.favoritePage(data,status:status)
  }
  /// Only exact catalog relationships, including artists with no local song entry.
  static func references(_ data:Data,status:Int) throws -> Data {
    guard status==200,var root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let items=root["data"] as? [[String:Any]] else{throw MusicFavoriteRequest.Failure.invalidResponse}
    var output:[[String:String]]=[]
    for item in items {
      guard let relationships=item["relationships"] as? [String:Any],let catalog=relationships["catalog"] as? [String:Any],
        let values=catalog["data"] as? [[String:Any]] else{throw MusicFavoriteRequest.Failure.invalidResponse}
      // An explicit empty relationship is a local artist without a catalog match.
      for value in values {
        guard value["type"] as? String == "artists",let id=value["id"] as? String,!id.isEmpty,
          id.utf8.allSatisfy({(48...57).contains($0)}) else{throw MusicFavoriteRequest.Failure.invalidResponse}
        output.append(["id":id])
      }
    }
    root["data"]=output
    return try JSONSerialization.data(withJSONObject:root)
  }
}

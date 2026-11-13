import Foundation
import CoreFoundation
/// Public add-only Favorites API. A 202 is acceptance, never verified favorite state.
enum MusicFavoriteRequest {
  enum Failure:LocalizedError {case invalidResource,invalidResponse
    var errorDescription:String? {"Apple Music non ha confermato una risorsa utilizzabile per i Preferiti."}
  }
  static func request(type:String,id:String) throws -> URLRequest {
    guard ["songs","albums","artists","playlists"].contains(type),!id.isEmpty,id.count<=160,
      id.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0)}),
      !id.hasPrefix("i."),!id.hasPrefix("l."),!id.hasPrefix("p.") else {throw Failure.invalidResource}
    var url=URLComponents(string:"https://api.music.apple.com/v1/me/favorites")!
    url.queryItems=[.init(name:"ids[\(type)]",value:id)]
    var request=URLRequest(url:url.url!);request.httpMethod="POST";request.timeoutInterval=20
    return request
  }
  static func favoritePage(_ data:Data,status:Int) throws -> Data {
    guard status==200,var root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let items=root["data"] as? [[String:Any]] else {throw Failure.invalidResponse}
    var favorites:[[String:Any]]=[]
    for item in items {
      guard let attrs=item["attributes"] as? [String:Any],let state=attrs["inFavorites"] as? NSNumber,
        CFGetTypeID(state)==CFBooleanGetTypeID() else {throw Failure.invalidResponse}
      if state.boolValue {favorites.append(item)}
    }
    root["data"]=favorites
    return try JSONSerialization.data(withJSONObject:root)
  }
  static func state(from data:Data,status:Int) throws -> Bool? {
    guard status==200,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let items=root["data"] as? [[String:Any]],items.count==1 else {throw Failure.invalidResponse}
    guard let attributes=items[0]["attributes"] as? [String:Any],let value=attributes["inFavorites"] as? NSNumber,
      CFGetTypeID(value)==CFBooleanGetTypeID() else {return nil}
    return value.boolValue
  }
  static func catalogID(from data:Data,status:Int) throws -> String {
    guard status==200,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let items=root["data"] as? [[String:Any]],items.count==1,let id=items.first?["id"] as? String,!id.isEmpty else {throw Failure.invalidResponse}
    return id
  }
}

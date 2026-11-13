import Foundation
/// Explicit documented catalog request, bypassing MusicKit's ID filter translation.
enum MediaCatalogRequest {
  enum Failure:Error {case invalidRequest,invalidResponse}
  static func request(ids:[String],storefront:String) throws -> URLRequest {
    guard !ids.isEmpty,ids.count<=100,MediaCatalogBridge.catalogIDs(ids)==ids,
      (2...3).contains(storefront.count),storefront.utf8.allSatisfy({(65...90).contains($0)||(97...122).contains($0)}) else {throw Failure.invalidRequest}
    var parts=URLComponents(string:"https://api.music.apple.com/v1/catalog/\(storefront.lowercased())/songs")!
    parts.queryItems=[.init(name:"ids",value:ids.joined(separator:","))]
    var request=URLRequest(url:parts.url!,cachePolicy:.reloadIgnoringLocalCacheData)
    request.timeoutInterval=20
    return request
  }
  static func items<Item:Decodable>(_ type:Item.Type,data:Data,status:Int) throws -> [Item] {
    guard status==200,data.count<=5*1024*1024,
      let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let values=root["data"] as? [[String:Any]],root["next"]==nil else {throw Failure.invalidResponse}
    return try JSONDecoder().decode([Item].self,from:JSONSerialization.data(withJSONObject:values))
  }
}

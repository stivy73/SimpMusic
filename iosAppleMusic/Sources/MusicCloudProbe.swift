import Foundation

/// Reads one page only; does not alter, import or persist the user's library.
enum MusicCloudProbe {
  enum Resource: String, CaseIterable, Sendable { case songs, albums, playlists }
  struct Result: Equatable, Sendable {
    let firstPageCount: Int
    let hasMore: Bool
  }
  struct AlbumSearchPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let data: [Item]
    let next: String?
  }
  static func albumSearchRequest(term: String) -> URLRequest {
    var url = URLComponents(string:"https://api.music.apple.com/v1/me/library/search")!
    url.queryItems = [.init(name:"term",value:term),.init(name:"types",value:"library-albums"),.init(name:"limit",value:"25")]
    var request = URLRequest(url:url.url!,cachePolicy:.reloadIgnoringLocalCacheData)
    request.timeoutInterval = 20
    request.setValue("no-cache",forHTTPHeaderField:"Cache-Control")
    return request
  }
  static func albumSearchPage<Item: Decodable & Sendable>(_ type: Item.Type, data: Data, status: Int) throws -> AlbumSearchPage<Item> {
    guard status == 200 else { throw ProbeError.http(status) }
    guard data.count <= 5 * 1024 * 1024,
      let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
      root["errors"] == nil, let results = root["results"] as? [String:Any] else { throw ProbeError.invalidResponse }
    guard let albums = results["library-albums"] else {
      guard results.isEmpty else { throw ProbeError.invalidResponse }
      return .init(data:[],next:nil)
    }
    return try JSONDecoder().decode(AlbumSearchPage<Item>.self,from:JSONSerialization.data(withJSONObject:albums))
  }
  static func request(for resource: Resource) -> URLRequest {
    var request = URLRequest(url:URL(string:"https://api.music.apple.com/v1/me/library/\(resource.rawValue)?limit=1")!)
    request.timeoutInterval = 15
    return request
  }
  static func parse(_ data: Data, status: Int) throws -> Result {
    guard status == 200 else { throw ProbeError.http(status) }
    guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
          let items = root["data"] as? [[String:Any]],
          root["errors"] == nil else { throw ProbeError.invalidResponse }
    return Result(firstPageCount:items.count,hasMore:(root["next"] as? String)?.isEmpty == false)
  }
  enum ProbeError: LocalizedError {
    case http(Int), invalidResponse
    var errorDescription: String? {
      switch self {
      case .http(let code): "Verifica libreria cloud: risposta HTTP \(code)."
      case .invalidResponse: "La verifica cloud non ha restituito una lista valida."
      }
    }
  }
}

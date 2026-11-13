import Foundation

/// Full, atomic reads of the official iCloud Music Library API. No credentials here:
/// the app supplies a MusicDataRequest transport so MusicKit manages authorization.
struct MusicCloudLibrary: Sendable {
  struct Response: Sendable { let data: Data; let status: Int }
  struct Result<Item: Sendable>: Sendable { let items: [Item]; let pages: Int }
  let fetch: @Sendable (URLRequest) async throws -> Response
  private struct Page<Item: Decodable>: Decodable {
    let data: [Item]
    let next: String?
  }
  enum LoadError: LocalizedError {
    case invalidPage, invalidNext, repeatedPage, excessivePages, responseTooLarge, http(Int)
    var errorDescription: String? {
      switch self {
      case .http(let status): "La libreria cloud Apple ha risposto con HTTP \(status)."
      case .invalidNext, .repeatedPage, .excessivePages: "Apple ha restituito una paginazione della libreria non valida. L’elenco incompleto non è stato applicato."
      case .invalidPage, .responseTooLarge: "La risposta della libreria cloud Apple non è utilizzabile. L’elenco incompleto non è stato applicato."
      }
    }
  }
  func load<Item: Decodable & Identifiable & Sendable>(
    _ type: Item.Type, resource: MusicCloudProbe.Resource
  ) async throws -> Result<Item> where Item.ID: Hashable {
    try await load(type, path: "/v1/me/library/\(resource.rawValue)")
  }
  /// Read the owned album's tracks, retaining library IDs and playback context.
  /// Catalog album tracks and playlist contents do not prove library membership.
  func albumTracks<Item: Decodable & Identifiable & Sendable>(
    _ type: Item.Type, albumID: String
  ) async throws -> Result<Item> where Item.ID: Hashable {
    guard Self.libraryAlbumIDs([albumID]) == [albumID] else { throw LoadError.invalidPage }
    return try await load(type, path: "/v1/me/library/albums/\(albumID)/tracks", libraryTracks: true)
  }
  private func load<Item: Decodable & Identifiable & Sendable>(
    _ type: Item.Type, path: String, libraryTracks: Bool = false
  ) async throws -> Result<Item> where Item.ID: Hashable {
    var url = URL(string:"https://api.music.apple.com\(path)?limit=100")!
    var visited = Set<URL>()
    var ids = Set<Item.ID>()
    var items: [Item] = []
    var pages = 0
    while true {
      try Task.checkCancellation()
      guard pages < 1000 else { throw LoadError.excessivePages }
      guard visited.insert(url).inserted else { throw LoadError.repeatedPage }
      var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData)
      request.timeoutInterval = 20
      request.setValue("no-cache",forHTTPHeaderField:"Cache-Control")
      let response = try await fetch(request)
      try Task.checkCancellation()
      guard response.status == 200 else { throw LoadError.http(response.status) }
      guard response.data.count <= 5 * 1024 * 1024 else { throw LoadError.responseTooLarge }
      guard let root = try JSONSerialization.jsonObject(with:response.data) as? [String:Any],
            root["data"] is [[String:Any]], root["errors"] == nil else { throw LoadError.invalidPage }
      var data = response.data
      if libraryTracks {
        var filtered = root
        let rows = root["data"] as! [[String:Any]]
        guard rows.allSatisfy({ ["library-songs", "library-music-videos"].contains($0["type"] as? String ?? "") }) else { throw LoadError.invalidPage }
        filtered["data"] = rows.filter { $0["type"] as? String == "library-songs" }
        data = try JSONSerialization.data(withJSONObject: filtered)
      }
      let page = try JSONDecoder().decode(Page<Item>.self,from:data)
      for item in page.data where ids.insert(item.id).inserted { items.append(item) }
      pages += 1
      guard let next = page.next, !next.isEmpty else { break }
      url = try Self.nextURL(next,relativeTo:url,expectedPath:path)
    }
    return Result(items:items,pages:pages)
  }
  func searchAlbums<Item: Decodable & Identifiable & Sendable>(
    _ type: Item.Type, term: String
  ) async throws -> Result<Item> where Item.ID: Hashable {
    try await search(type,resource:.albums,term:term)
  }
  func search<Item:Decodable & Identifiable & Sendable>(
    _ type:Item.Type,resource:MusicCloudProbe.Resource,term:String
  ) async throws -> Result<Item> where Item.ID:Hashable {
    var components=URLComponents(string:"https://api.music.apple.com/v1/me/library/search")!
    let resourceType="library-"+resource.rawValue
    components.queryItems=[.init(name:"term",value:term),.init(name:"types",value:resourceType),.init(name:"limit",value:"25")]
    var url=components.url!
    var visited=Set<URL>(),seen=Set<Item.ID>();var values:[Item]=[];var pages=0
    while true {
      try Task.checkCancellation()
      guard pages<1000,visited.insert(url).inserted else {throw LoadError.repeatedPage}
      var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData);request.timeoutInterval=20
      let response=try await fetch(request);try Task.checkCancellation()
      guard response.status==200 else {throw LoadError.http(response.status)}
      guard response.data.count<=5*1024*1024,
        let root=try JSONSerialization.jsonObject(with:response.data) as? [String:Any],root["errors"]==nil,
        let results=root["results"] as? [String:Any] else {throw LoadError.invalidPage}
      let payload:Any
      if let result=results[resourceType] {payload=result}
      else {guard results.isEmpty else {throw LoadError.invalidPage};payload=["data":[]]}
      let page=try JSONDecoder().decode(Page<Item>.self,from:JSONSerialization.data(withJSONObject:payload))
      for item in page.data where seen.insert(item.id).inserted {values.append(item)}
      pages+=1
      guard let next=page.next,!next.isEmpty else {break}
      url=try Self.nextURL(next,relativeTo:url,expectedPath:"/v1/me/library/search")
      let query=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
      guard query.filter({$0.name=="term"}).map(\.value)==[term],query.filter({$0.name=="types"}).map(\.value)==[resourceType] else {throw LoadError.invalidNext}
    }
    return Result(items:values,pages:pages)
  }
  /// IDs are only those already returned by a personal-library search. Revalidate
  /// them with the current account before restoring any row after an app restart.
  func albumsByID<Item: Decodable & Identifiable & Sendable>(
    _ type: Item.Type, ids: [String], id: @Sendable (Item) -> String
  ) async throws -> [Item] where Item.ID: Hashable {
    let requested = Self.libraryAlbumIDs(ids)
    var values: [Item] = []
    for offset in stride(from:0,to:requested.count,by:100) {
      try Task.checkCancellation()
      let batch = Array(requested.dropFirst(offset).prefix(100))
      var url = URLComponents(string:"https://api.music.apple.com/v1/me/library/albums")!
      url.queryItems = [.init(name:"ids",value:batch.joined(separator:","))]
      var request = URLRequest(url:url.url!,cachePolicy:.reloadIgnoringLocalCacheData)
      request.timeoutInterval = 20; request.setValue("no-cache",forHTTPHeaderField:"Cache-Control")
      let response = try await fetch(request)
      try Task.checkCancellation()
      guard response.status == 200 else { throw LoadError.http(response.status) }
      guard response.data.count <= 5 * 1024 * 1024,
        let root = try JSONSerialization.jsonObject(with:response.data) as? [String:Any],
        root["data"] is [[String:Any]], root["errors"] == nil else { throw LoadError.invalidPage }
      let page = try JSONDecoder().decode(Page<Item>.self,from:response.data)
      guard page.next == nil || page.next == "", page.data.allSatisfy({Set(batch).contains(id($0))}) else { throw LoadError.invalidPage }
      values = Self.combining(values,local:page.data)
    }
    return values
  }
  static func libraryAlbumIDs(_ ids:[String]) -> [String] {
    var seen = Set<String>()
    return ids.filter {
      $0.hasPrefix("l.") && $0.count > 2 && $0.count <= 128 &&
      $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) } && seen.insert($0).inserted
    }
  }
  static func combining<Item: Identifiable>(_ cloud: [Item], local: [Item]) -> [Item] where Item.ID: Hashable {
    var ids = Set<Item.ID>()
    // Cloud metadata wins for a shared ID. Keep device-only songs and smart playlists.
    return (cloud + local).filter { ids.insert($0.id).inserted }
  }
  static func nextURL(_ value: String, relativeTo base: URL, expectedPath: String) throws -> URL {
    guard let url = URL(string:value,relativeTo:base)?.absoluteURL,
          let components = URLComponents(url:url,resolvingAgainstBaseURL:true),
          components.scheme == "https", components.host == "api.music.apple.com",
          components.user == nil, components.password == nil,
          components.port == nil || components.port == 443,
          components.fragment == nil, components.percentEncodedPath == expectedPath else { throw LoadError.invalidNext }
    return url
  }
}

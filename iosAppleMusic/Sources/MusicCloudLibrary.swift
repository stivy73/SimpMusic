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
    let path = "/v1/me/library/\(resource.rawValue)"
    var url = URL(string:"https://api.music.apple.com\(path)?limit=100")!
    var visited = Set<URL>()
    var ids = Set<Item.ID>()
    var items: [Item] = []
    var pages = 0
    while true {
      try Task.checkCancellation()
      guard pages < 1000 else { throw LoadError.excessivePages }
      guard visited.insert(url).inserted else { throw LoadError.repeatedPage }
      var request = URLRequest(url:url); request.timeoutInterval = 20
      let response = try await fetch(request)
      try Task.checkCancellation()
      guard response.status == 200 else { throw LoadError.http(response.status) }
      guard response.data.count <= 5 * 1024 * 1024 else { throw LoadError.responseTooLarge }
      guard let root = try JSONSerialization.jsonObject(with:response.data) as? [String:Any],
            root["data"] is [[String:Any]], root["errors"] == nil else { throw LoadError.invalidPage }
      let page = try JSONDecoder().decode(Page<Item>.self,from:response.data)
      for item in page.data where ids.insert(item.id).inserted { items.append(item) }
      pages += 1
      guard let next = page.next, !next.isEmpty else { break }
      url = try Self.nextURL(next,relativeTo:url,expectedPath:path)
    }
    return Result(items:items,pages:pages)
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

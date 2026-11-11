import Foundation

/// Reads one page only; does not alter, import or persist the user's library.
enum MusicCloudProbe {
  enum Resource: String, CaseIterable, Sendable { case songs, albums, playlists }
  struct Result: Equatable, Sendable {
    let firstPageCount: Int
    let hasMore: Bool
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

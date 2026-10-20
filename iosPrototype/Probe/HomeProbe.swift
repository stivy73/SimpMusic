import Foundation
import PrototypeCore
import YouTubeSDK

// Anonymous browse only: never read or log account cookies.
func probeHomeIfRequested(_ args: [String]) async throws -> Bool {
  guard args.first == "--home" else { return false }
  let discovery = HomeDiscovery(session: nil)
  let home = try await discovery.page(target: BrowseTarget(browseId: "FEmusic_home"))
  print(
    "Home: \(home.shelves.count) sections, \(home.shelves.reduce(0) { $0 + $1.items.count }) items")
  for shelf in home.shelves {
    print(
      "\(shelf.title): \(shelf.items.count) items; types: \(Set(shelf.items.map { $0.kind.rawValue }).sorted()); More: \(shelf.more != nil)"
    )
  }
  guard !home.shelves.isEmpty else { throw URLError(.cannotParseResponse) }
  if let token = home.continuation {
    let next = try await discovery.page(
      target: BrowseTarget(browseId: "FEmusic_home"), continuation: token)
    print(
      "Continuation: \(next.shelves.count) sections; next token present: \(next.continuation != nil)"
    )
  }
  let categories = try await discovery.page(
    target: BrowseTarget(browseId: "FEmusic_moods_and_genres"))
  print(
    "Categories: \(categories.categories.map { "\($0.title): \($0.items.count)" }.joined(separator: ", "))"
  )
  guard let category = categories.categories.first?.items.first else {
    throw URLError(.cannotParseResponse)
  }
  let detail = try await discovery.page(target: category.target)
  print(
    "Category \(category.title): \(detail.shelves.count) sections; \(detail.shelves.reduce(0) { $0 + $1.items.count }) items"
  )
  guard !detail.shelves.isEmpty else { throw URLError(.cannotParseResponse) }
  if let playlist = detail.shelves.flatMap(\.items).first(where: { $0.kind == .playlist }),
    let target = playlist.target
  {
    let tracks = try await discovery.page(target: target)
    print(
      "Playlist: \(tracks.shelves.flatMap(\.items).filter { $0.kind == .song }.count) tracks; continuation present: \(tracks.continuation != nil)"
    )
    guard tracks.shelves.contains(where: { !$0.items.isEmpty }) else {
      throw URLError(.cannotParseResponse)
    }
    if let token = tracks.continuation {
      let next = try await discovery.page(target: target, continuation: token)
      print("Playlist continuation: \(next.shelves.flatMap(\.items).count) tracks")
    }
  }
  let filtered = try await discovery.page(
    target: BrowseTarget(browseId: "FEmusic_home", params: HomeFilter.values[1].params))
  print("Relax filter: \(filtered.shelves.count) sections")
  return true
}

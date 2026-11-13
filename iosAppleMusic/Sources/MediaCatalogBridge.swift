import Foundation

/// Resolves exact catalog IDs obtained from MPMediaItem.playbackStoreID.
/// Never searches for substitutes by title and never changes the user's library.
enum MediaCatalogBridge {
  struct Result<Item: Sendable>: Sendable {
    let items: [Item]
    let requested: Int
    var unresolved: Int { requested - items.count }
  }
  enum BridgeError: Error { case unexpectedCatalogItem }
  static func catalogIDs(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { value in
      !value.isEmpty && value != "0" && value.utf8.allSatisfy { (48...57).contains($0) } && seen.insert(value).inserted
    }
  }
  static func resolve<Item: Sendable>(
    _ storeIDs: [String],
    id: @Sendable (Item) -> String,
    fetch: @Sendable ([String]) async throws -> [Item]
  ) async throws -> Result<Item> {
    let ids = catalogIDs(storeIDs)
    var found: [String:Item] = [:]
    for offset in stride(from:0,to:ids.count,by:100) {
      try Task.checkCancellation()
      let batch = Array(ids.dropFirst(offset).prefix(100))
      let allowed = Set(batch)
      let items = try await fetch(batch)
      try Task.checkCancellation()
      for item in items {
        let key = id(item)
        guard allowed.contains(key) else { throw BridgeError.unexpectedCatalogItem }
        if found[key] == nil { found[key] = item }
      }
    }
    // Publish only after every requested batch completes, retaining device order.
    return Result(items:ids.compactMap { found[$0] },requested:ids.count)
  }
}

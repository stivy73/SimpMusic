import Foundation

struct LibrarySectionState: Equatable, Sendable {
  enum Phase: Sendable { case idle, updating, ready, partial, failed }
  var phase: Phase = .idle
  var updatedAt: Date?
  var message: String?
  var unresolved = 0
  var needsRetry: Bool { phase == .partial || phase == .failed }
}

struct LibrarySyncActivity {
  struct Work { let id: UUID; let categories: Set<BrowseKind> }
  private var owners: [BrowseKind: UUID] = [:]
  var busy: Bool { !owners.isEmpty }
  func owns(_ kind: BrowseKind, work: UUID) -> Bool { owners[kind] == work }
  mutating func begin(_ requested: Set<BrowseKind>) -> Work {
    let work = Work(id: UUID(), categories: requested.subtracting(owners.keys))
    for kind in work.categories { owners[kind] = work.id }
    return work
  }
  @discardableResult mutating func finish(_ kind: BrowseKind, work: UUID) -> Bool {
    guard owners[kind] == work else { return false }
    owners.removeValue(forKey: kind); return true
  }
}

enum LibraryRead<Item: Sendable>: Sendable {
  case success([Item])
  case failure(String)
  var values: [Item] { if case .success(let values) = self { return values }; return [] }
  var failure: String? { if case .failure(let message) = self { return message }; return nil }
}

/// A failed source cannot erase the last usable snapshot. Only two successful
/// enumerations may remove old rows, including when the account is really empty.
enum LibrarySyncPolicy {
  static func reconcile<Item: Identifiable & Sendable>(
    previous: [Item], local: LibraryRead<Item>, cloud: LibraryRead<Item>,
    recovered: [Item] = [], unresolved: Int = 0, recoveryMessage: String? = nil,
    previousState: LibrarySectionState = .init(), now: Date = Date()
  ) -> (items: [Item], state: LibrarySectionState) where Item.ID: Hashable {
    let failures = [local.failure, cloud.failure].compactMap { $0 }
    let fresh = MusicCloudLibrary.combining(cloud.values, local: local.values + recovered)
    let missing = max(0, unresolved)
    let messages = failures + [recoveryMessage].compactMap { $0 }
    let incomplete = !messages.isEmpty || missing > 0
    let items = incomplete ? MusicCloudLibrary.combining(fresh, local: previous) : fresh
    let neitherSucceeded = local.failure != nil && cloud.failure != nil && recovered.isEmpty
    let phase: LibrarySectionState.Phase = neitherSucceeded ? .failed :
      (incomplete ? .partial : .ready)
    return (items, .init(phase: phase,
      updatedAt: neitherSucceeded ? previousState.updatedAt : now,
      message: messages.isEmpty ? nil : messages.joined(separator: "\n"), unresolved: missing))
  }
}

/// Metadata stays in memory and is used only to query the authorized personal
/// library. Never put titles or identifiers into the shared synchronization log.
struct LibraryTrackReference: Equatable, Sendable {
  var storeID: String
  var title: String
  var artist: String
  var album: String
  var track: Int = 0
  var disc: Int = 0
  var duration: Double = 0
}

struct LibrarySongIdentity: Sendable {
  var ids: Set<String>
  var title: String
  var artist: String
  var album: String
  var track: Int = 0
  var disc: Int = 0
  var duration: Double = 0

  static func key(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
  func matches(_ reference: LibraryTrackReference) -> Bool {
    if !reference.storeID.isEmpty && reference.storeID != "0" && ids.contains(reference.storeID) { return true }
    // Preserve editions, mixes and live versions. Do not fuzzy-match a catalog
    // replacement for a recording which Apple did not return.
    guard !title.isEmpty, !artist.isEmpty, !reference.title.isEmpty, !reference.artist.isEmpty,
      Self.key(title) == Self.key(reference.title), Self.key(artist) == Self.key(reference.artist),
      !reference.album.isEmpty, Self.key(album) == Self.key(reference.album) else { return false }
    if track > 0 && reference.track > 0 && track != reference.track { return false }
    if disc > 0 && reference.disc > 0 && disc != reference.disc { return false }
    if duration > 0 && reference.duration > 0 && abs(duration - reference.duration) > 2 { return false }
    return true
  }
}

enum LibrarySongRecovery {
  struct Group: Sendable { let term: String; let album: String }
  struct Result<Item: Sendable>: Sendable {
    let items: [Item]
    let unresolved: Int
    let albumReads: Int
    let searches: Int
    let catalogRequested: Int
    let failedReads: Int
  }
  static func missing<Item>(_ references: [LibraryTrackReference], in items: [Item],
    identity: (Item) -> LibrarySongIdentity) -> [LibraryTrackReference] {
    let identities = items.map(identity)
    let ids = Set(identities.flatMap(\.ids))
    let byTitle = Dictionary(grouping: identities, by: { LibrarySongIdentity.key($0.title) })
    return references.filter { reference in
      if reference.storeID != "0" && !reference.storeID.isEmpty && ids.contains(reference.storeID) { return false }
      return !(byTitle[LibrarySongIdentity.key(reference.title)] ?? []).contains { $0.matches(reference) }
    }
  }
  static func groups(_ references: [LibraryTrackReference]) -> [Group] {
    var seen = Set<String>()
    return references.compactMap { reference in
      let album = reference.album.trimmingCharacters(in: .whitespacesAndNewlines)
      let term = album.isEmpty ? reference.title.trimmingCharacters(in: .whitespacesAndNewlines) : album
      guard !term.isEmpty, seen.insert(LibrarySongIdentity.key(term)).inserted else { return nil }
      return Group(term: term, album: album)
    }
  }
  static func merging<Item: Identifiable>(_ preferred: [Item], _ additional: [Item],
    identity: (Item) -> LibrarySongIdentity) -> [Item] where Item.ID: Hashable {
    var itemIDs = Set<Item.ID>(), aliases = Set<String>()
    return (preferred + additional).filter { item in
      let ids = identity(item).ids
      guard !itemIDs.contains(item.id), ids.isDisjoint(with: aliases) else { return false }
      itemIDs.insert(item.id); aliases.formUnion(ids); return true
    }
  }
  static func recover<Item: Identifiable & Sendable>(
    references: [LibraryTrackReference], available: [Item],
    id: @Sendable (Item) -> String,
    identity: @Sendable (Item) -> LibrarySongIdentity,
    albumTracks: @Sendable (String) async throws -> [Item],
    search: @Sendable (String) async throws -> [Item],
    catalog: @Sendable ([String]) async throws -> [Item]
  ) async throws -> Result<Item> where Item.ID: Hashable {
    var items = available, albumReads = 0, searches = 0, failedReads = 0
    for group in groups(missing(references, in: items, identity: identity)) {
      try Task.checkCancellation()
      let outstanding = missing(references, in: items, identity: identity)
      guard groups(outstanding).contains(where: { LibrarySongIdentity.key($0.term) == LibrarySongIdentity.key(group.term) }) else { continue }
      if !group.album.isEmpty {
        do {
          let found = try await albumTracks(group.album)
          try Task.checkCancellation(); albumReads += 1
          items = merging(items, found, identity: identity)
        } catch { if Task.isCancelled || error is CancellationError { throw CancellationError() }; failedReads += 1 }
      }
      guard groups(missing(references, in: items, identity: identity)).contains(where: {
        LibrarySongIdentity.key($0.term) == LibrarySongIdentity.key(group.term)
      }) else { continue }
      do {
        let found = try await search(group.term)
        try Task.checkCancellation(); searches += 1
        items = merging(items, found, identity: identity)
      } catch { if Task.isCancelled || error is CancellationError { throw CancellationError() }; failedReads += 1 }
    }
    let ids = MediaCatalogBridge.catalogIDs(missing(references, in: items, identity: identity).map(\.storeID))
    if !ids.isEmpty {
      do {
        // Exact IDs only, and only after personal routes. This may legitimately
        // return nothing for imports, purchases or unavailable catalog editions.
        let result = try await MediaCatalogBridge.resolve(ids, id: id, fetch: catalog)
        try Task.checkCancellation()
        items = merging(items, result.items, identity: identity)
      } catch { if Task.isCancelled || error is CancellationError { throw CancellationError() }; failedReads += 1 }
    }
    return .init(items: items, unresolved: missing(references, in: items, identity: identity).count,
      albumReads: albumReads, searches: searches, catalogRequested: ids.count, failedReads: failedReads)
  }
}

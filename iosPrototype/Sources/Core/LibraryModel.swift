import Combine
import Foundation
import YouTubeSDK

public enum RemoteLibraryKind: String, CaseIterable, Sendable, Identifiable {
  case songs, likes, playlists, artists
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .songs: "Brani salvati"
    case .likes: "Mi piace"
    case .playlists: "Playlist"
    case .artists: "Artisti seguiti"
    }
  }
  public var browseID: String {
    switch self {
    case .songs: "FEmusic_liked_videos"
    case .likes: "VLLM"
    case .playlists: "FEmusic_liked_playlists"
    case .artists: "FEmusic_library_corpus_artists"
    }
  }
  public var itemKind: DiscoveryItem.Kind {
    switch self {
    case .songs, .likes: .song
    case .playlists: .playlist
    case .artists: .artist
    }
  }
}

public struct RemoteLibraryState: Sendable {
  public var items: [DiscoveryItem] = []
  public var loading = false
  public var loaded = false
  public var error: String?
}

/// Complete collection loading is atomic: an interrupted page must not turn an existing like off.
public enum RemoteLibraryCollection {
  public static func completed(
    kind: RemoteLibraryKind,
    fetch: @Sendable (String?) async throws -> HomePage
  ) async throws -> [DiscoveryItem] {
    var items: [DiscoveryItem] = []
    var seen = Set<String>()
    var tokens = Set<String>()
    var token: String?
    repeat {
      try Task.checkCancellation()
      let page = try await fetch(token)
      try Task.checkCancellation()
      for item in page.shelves.flatMap(\.items)
      where item.kind == kind.itemKind && seen.insert(item.id).inserted {
        items.append(item)
      }
      token = page.continuation
      if let token, !tokens.insert(token).inserted { throw LibraryError.repeatedContinuation }
    } while token != nil
    return items
  }
}

@MainActor
public final class LibraryModel: ObservableObject {
  @Published public private(set) var session: YouTubeSession?
  @Published public private(set) var albums: [LibraryAlbum] = []
  @Published public private(set) var loading = false
  @Published public var error: String?
  @Published public var showLogin = false
  @Published public private(set) var collections: [RemoteLibraryKind: RemoteLibraryState] = [:]
  @Published public private(set) var pendingLikes = Set<String>()
  @Published public var syncError: String?
  private var request: Task<Void, Never>?
  private var revision = UUID()
  private var accountRevision = UUID()
  private var collectionRequests: [RemoteLibraryKind: Task<Void, Never>] = [:]
  private var collectionRevisions: [RemoteLibraryKind: UUID] = [:]
  public typealias FetchCollection =
    @Sendable (YouTubeSession, RemoteLibraryKind) async throws -> [DiscoveryItem]
  public typealias RateSong = @Sendable (YouTubeSession, String, Bool) async throws -> Void
  private let fetchCollection: FetchCollection
  private let rateSong: RateSong

  private let save: @MainActor (YouTubeSession?) throws -> Void
  private let fetch: @Sendable (YouTubeSession) async throws -> [LibraryAlbum]

  public init(
    session: YouTubeSession?, save: @escaping @MainActor (YouTubeSession?) throws -> Void,
    fetch: @escaping @Sendable (YouTubeSession) async throws -> [LibraryAlbum],
    fetchCollection: @escaping FetchCollection = { session, kind in
      let discovery = HomeDiscovery(session: session)
      return try await RemoteLibraryCollection.completed(kind: kind) { token in
        try await discovery.libraryPage(kind: kind, continuation: token)
      }
    },
    rateSong: @escaping RateSong = { session, id, liked in
      try await YouTubeBrowse(session: session).setLiked(videoID: id, liked: liked)
    }
  ) {
    self.session = session
    self.save = save
    self.fetch = fetch
    self.fetchCollection = fetchCollection
    self.rateSong = rateSong
  }

  public func connect(_ value: YouTubeSession) {
    invalidate()
    do {
      try save(value)
      session = value
      showLogin = false
      refresh()
    } catch {
      session = nil
      self.error = "Impossibile salvare la sessione nel Portachiavi. Riprova."
    }
  }

  public func disconnect() {
    do {
      try save(nil)
      invalidate()
      session = nil
    } catch { self.error = "Impossibile rimuovere la sessione dal Portachiavi. Riprova." }
  }

  private func invalidate() {
    accountRevision = UUID()
    request?.cancel()
    for task in collectionRequests.values { task.cancel() }
    collectionRequests = [:]
    collectionRevisions = [:]
    collections = [:]
    pendingLikes = []
    syncError = nil
    revision = UUID()
    albums = []
    loading = false
    error = nil
  }

  public func refresh() {
    guard let session else { return }
    // Album refresh must not clear other collections or an in-flight like operation.
    request?.cancel()
    revision = UUID()
    error = nil
    loading = true
    let expected = revision
    request = Task {
      do {
        let result = try await fetch(session)
        try Task.checkCancellation()
        guard expected == revision else { return }
        albums = result
        loading = false
      } catch is CancellationError {} catch {
        guard expected == revision else { return }
        albums = []
        loading = false
        self.error = error.localizedDescription
      }
    }
  }

  public func reload() async {
    refresh()
    await request?.value
  }

  public func state(_ kind: RemoteLibraryKind) -> RemoteLibraryState {
    collections[kind] ?? RemoteLibraryState()
  }

  public func load(_ kind: RemoteLibraryKind, force: Bool = false) async {
    guard let session else { return }
    if kind == .likes && !pendingLikes.isEmpty { return }
    if state(kind).loading {
      await collectionRequests[kind]?.value
      return
    }
    if state(kind).loaded && !force { return }
    let expected = UUID()
    collectionRevisions[kind] = expected
    collections[kind, default: RemoteLibraryState()].loading = true
    collections[kind, default: RemoteLibraryState()].error = nil
    let task = Task {
      do {
        let items = try await fetchCollection(session, kind)
        try Task.checkCancellation()
        guard self.session == session, collectionRevisions[kind] == expected else { return }
        collections[kind] = RemoteLibraryState(items: items, loaded: true)
      } catch is CancellationError {} catch {
        guard self.session == session, collectionRevisions[kind] == expected else { return }
        collections[kind, default: RemoteLibraryState()].loading = false
        collections[kind, default: RemoteLibraryState()].error =
          "Impossibile sincronizzare \(kind.title.lowercased()). " + error.localizedDescription
      }
    }
    collectionRequests[kind] = task
    await task.value
  }

  public func isLiked(_ id: String) -> Bool {
    state(.likes).items.contains { $0.mediaId == id }
  }

  public func toggleLike(_ item: DiscoveryItem) async {
    guard item.kind == .song else { return }
    guard let session else {
      showLogin = true
      return
    }
    let accountRevision = self.accountRevision
    guard !pendingLikes.contains(item.mediaId) else { return }
    await load(.likes)
    guard self.accountRevision == accountRevision else { return }
    guard self.session == session, state(.likes).loaded, state(.likes).error == nil else {
      syncError = "Non posso verificare i Mi piace. Aggiorna la raccolta e riprova."
      return
    }
    // Recheck after the awaited fetch: two taps may both have been waiting for it.
    guard !pendingLikes.contains(item.mediaId) else { return }
    pendingLikes.insert(item.mediaId)
    let liked = !isLiked(item.mediaId)
    syncError = nil
    do {
      try await rateSong(session, item.mediaId, liked)
      guard self.accountRevision == accountRevision else { return }
      if liked {
        collections[.likes]?.items.insert(item, at: 0)
      } else {
        collections[.likes]?.items.removeAll { $0.mediaId == item.mediaId }
      }
    } catch {
      guard self.accountRevision == accountRevision else { return }
      syncError =
        "Mi piace non sincronizzato. Controlla la connessione o accedi nuovamente e riprova."
    }
    guard self.accountRevision == accountRevision else { return }
    pendingLikes.remove(item.mediaId)
  }
}

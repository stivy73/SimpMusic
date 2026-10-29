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
  @Published public private(set) var pendingFollows = Set<String>()
  @Published public var syncError: String?
  private var request: Task<Void, Never>?
  private var revision = UUID()
  private var accountRevision = UUID()
  private var collectionRequests: [RemoteLibraryKind: Task<Void, Never>] = [:]
  private var collectionRevisions: [RemoteLibraryKind: UUID] = [:]
  public typealias FetchCollection =
    @Sendable (YouTubeSession, RemoteLibraryKind) async throws -> [DiscoveryItem]
  public typealias RateSong = @Sendable (YouTubeSession, String, Bool) async throws -> Void
  public typealias FollowArtist = @Sendable (YouTubeSession, String, Bool) async throws -> Void
  private let fetchCollection: FetchCollection
  private let rateSong: RateSong
  private let followArtist: FollowArtist

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
    },
    followArtist: @escaping FollowArtist = { session, id, followed in
      try await YouTubeBrowse(session: session).setFollowed(artistID: id, followed: followed)
    }
  ) {
    self.session = session
    self.save = save
    self.fetch = fetch
    self.fetchCollection = fetchCollection
    self.rateSong = rateSong
    self.followArtist = followArtist
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
    pendingFollows = []
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
      } catch is CancellationError {
        if expected == revision { loading = false }
      } catch {
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
    if kind == .artists && !pendingFollows.isEmpty { return }
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
      } catch is CancellationError {
        guard self.session == session, collectionRevisions[kind] == expected else { return }
        collections[kind, default: RemoteLibraryState()].loading = false
      } catch {
        guard self.session == session, collectionRevisions[kind] == expected else { return }
        collections[kind, default: RemoteLibraryState()].loading = false
        collections[kind, default: RemoteLibraryState()].error =
          "Impossibile sincronizzare \(kind.title.lowercased()). " + error.localizedDescription
      }
    }
    collectionRequests[kind] = task
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }

  public func isLiked(_ id: String) -> Bool {
    state(.likes).items.contains { $0.mediaId == id }
  }

  public func isFollowed(_ id: String) -> Bool {
    state(.artists).items.contains { $0.mediaId == id }
  }

  public func toggleFollow(_ artist: DiscoveryItem) async {
    guard artist.kind == .artist else { return }
    guard let session else {
      showLogin = true
      return
    }
    let expected = accountRevision
    await load(.artists)
    guard expected == accountRevision, self.session == session else { return }
    guard state(.artists).loaded, state(.artists).error == nil else {
      syncError = "Non posso verificare gli artisti seguiti. Aggiorna la raccolta e riprova."
      return
    }
    guard !pendingFollows.contains(artist.mediaId) else { return }
    pendingFollows.insert(artist.mediaId)
    syncError = nil
    let followed = !isFollowed(artist.mediaId)
    do {
      try await followArtist(session, artist.mediaId, followed)
      guard expected == accountRevision else { return }
      if followed {
        collections[.artists]?.items.insert(artist, at: 0)
      } else {
        collections[.artists]?.items.removeAll { $0.mediaId == artist.mediaId }
      }
    } catch {
      guard expected == accountRevision else { return }
      syncError = "Modifica non confermata da YouTube Music. Riprova."
    }
    pendingFollows.remove(artist.mediaId)
  }

  public func toggleLike(_ item: DiscoveryItem) async {
    _ = await updateLike(item, desired: nil)
  }

  /// Explicit, idempotent writes are required when importing old local favourites.
  @discardableResult
  public func setLike(_ item: DiscoveryItem, liked: Bool) async -> Bool {
    await updateLike(item, desired: liked)
  }

  public func importLikes(
    _ items: [DiscoveryItem], confirmed: @MainActor (DiscoveryItem) -> Void
  ) async {
    guard let account = session else { return }
    var seen = Set<String>()
    for item in items where item.kind == .song && seen.insert(item.mediaId).inserted {
      guard !Task.isCancelled, session == account else { return }
      let success = await setLike(item, liked: true)
      guard !Task.isCancelled, session == account else { return }
      if success { confirmed(item) } else { return }
    }
  }

  private func updateLike(_ item: DiscoveryItem, desired: Bool?) async -> Bool {
    guard item.kind == .song, !Task.isCancelled else { return false }
    guard let session else {
      showLogin = true
      return false
    }
    let accountRevision = self.accountRevision
    guard !pendingLikes.contains(item.mediaId) else { return false }
    await load(.likes)
    guard self.accountRevision == accountRevision, !Task.isCancelled else { return false }
    guard self.session == session, state(.likes).loaded, state(.likes).error == nil else {
      syncError = "Non posso verificare i Mi piace. Aggiorna la raccolta e riprova."
      return false
    }
    // Recheck after the awaited fetch: two taps may both have been waiting for it.
    guard !pendingLikes.contains(item.mediaId) else { return false }
    let liked = desired ?? !isLiked(item.mediaId)
    if liked == isLiked(item.mediaId) { return true }
    pendingLikes.insert(item.mediaId)
    syncError = nil
    do {
      try await rateSong(session, item.mediaId, liked)
      guard self.accountRevision == accountRevision else { return false }
      if liked {
        collections[.likes]?.items.insert(item, at: 0)
      } else {
        collections[.likes]?.items.removeAll { $0.mediaId == item.mediaId }
      }
    } catch {
      guard self.accountRevision == accountRevision else { return false }
      syncError =
        "Mi piace non sincronizzato. Controlla la connessione o accedi nuovamente e riprova."
      pendingLikes.remove(item.mediaId)
      return false
    }
    guard self.accountRevision == accountRevision else { return false }
    pendingLikes.remove(item.mediaId)
    return true
  }
}

import Combine
import Foundation
import YouTubeSDK

public struct ArtistReleaseNotice: Codable, Identifiable, Equatable, Sendable {
  public var id: String { artist.mediaId + ":" + release.mediaId }
  public let artist: DiscoveryItem
  public let release: DiscoveryItem
  public let discovered: Date
}
public struct ArtistReleaseState: Codable, Sendable {
  public var enabled = false
  public var known: [String: Set<String>] = [:]
  public var notices: [ArtistReleaseNotice] = []
  public var lastCheck: Date?
  public init() {}
  /// The first successful check of each artist establishes a baseline, without historical alerts.
  public mutating func ingest(artist: DiscoveryItem, releases: [DiscoveryItem], now: Date = Date())
    -> [ArtistReleaseNotice]
  {
    var unique = Set<String>()
    let releases = releases.filter { $0.kind == .album && unique.insert($0.mediaId).inserted }
    guard !releases.isEmpty else { return [] }
    let old = known[artist.mediaId]
    known[artist.mediaId, default: []].formUnion(releases.map(\.mediaId))
    guard let old else { return [] }
    let fresh = releases.filter { !old.contains($0.mediaId) }.map {
      ArtistReleaseNotice(artist: artist, release: $0, discovered: now)
    }
    let existing = Set(notices.map(\.id))
    let added = fresh.filter { !existing.contains($0.id) }
    notices = Array((added + notices).prefix(200))
    return added
  }
}

@MainActor public final class ArtistReleases: ObservableObject {
  public typealias Fetch = @Sendable (YouTubeSession, DiscoveryItem) async throws -> [DiscoveryItem]
  @Published public private(set) var state = ArtistReleaseState()
  @Published public private(set) var busy = false
  @Published public private(set) var error: String?
  public private(set) var session: YouTubeSession?
  private let directory: URL
  private let fetch: Fetch
  private var revision = UUID()
  private var url: URL? {
    session.map {
      directory.appendingPathComponent(
        LocalFiles.key($0.identity + "|" + $0.accountIndex + "|" + ($0.delegatedID ?? "")) + ".json"
      )
    }
  }
  public init(
    directory: URL = LocalFiles.directory("ArtistReleases"),
    fetch: @escaping Fetch = { session, artist in
      let page = try await HomeDiscovery(session: session).page(
        target: BrowseTarget(browseId: artist.mediaId))
      // Only release shelves; recommended artists' albums must not become this artist's alerts.
      let releaseShelves = page.shelves.filter {
        let name = $0.title.folding(
          options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return ["album", "singol", "single", "uscit", "release"].contains { name.contains($0) }
      }
      return releaseShelves.flatMap(\.items).filter { $0.kind == .album }
    }
  ) {
    self.directory = directory
    self.fetch = fetch
  }
  public func configure(_ session: YouTubeSession?) {
    guard self.session != session else { return }
    revision = UUID()
    self.session = session
    busy = false
    error = nil
    state =
      url.flatMap { LocalFiles.read(ArtistReleaseState.self, from: $0) } ?? ArtistReleaseState()
  }
  public func setEnabled(_ enabled: Bool) {
    revision = UUID()
    busy = false
    state.enabled = enabled
    // Re-enabling starts from current releases, rather than notifying about a long inactive period.
    if enabled { state.known = [:] }
    save()
  }
  public func clearNotices() {
    state.notices = []
    save()
  }
  public func reconcile(artists: [DiscoveryItem]) {
    let followed = Set(artists.map(\.mediaId))
    state.known = state.known.filter { followed.contains($0.key) }
    state.notices.removeAll { !followed.contains($0.artist.mediaId) }
    save()
  }
  public func check(artists: [DiscoveryItem], force: Bool = false, now: Date = Date()) async
    -> [ArtistReleaseNotice]
  {
    guard !busy, state.enabled, let session,
      force || state.lastCheck.map({ now.timeIntervalSince($0) >= 6 * 3600 }) ?? true
    else { return [] }
    busy = true
    error = nil
    let expected = revision
    var added: [ArtistReleaseNotice] = []
    var failures = 0
    reconcile(artists: artists)
    for artist in artists where artist.kind == .artist {
      do {
        try Task.checkCancellation()
        let releases = try await fetch(session, artist)
        try Task.checkCancellation()
        guard revision == expected else { return [] }
        added += state.ingest(artist: artist, releases: releases, now: now)
        save()
      } catch is CancellationError {
        guard revision == expected else { return [] }
        busy = false
        return []
      } catch { failures += 1 }
    }
    guard revision == expected else { return [] }
    busy = false
    if failures == 0 {
      state.lastCheck = now
    } else {
      error = "Alcuni artisti non sono raggiungibili. Riprova per completare il controllo."
    }
    save()
    return added
  }
  private func save() {
    guard let url else { return }
    do { try LocalFiles.write(state, to: url) } catch {
      self.error = "Impossibile salvare gli avvisi delle nuove uscite."
    }
  }
}

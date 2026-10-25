import Combine
import Foundation
import YouTubeSDK

public enum MusicSearchScope: Hashable, Sendable, Identifiable {
  case all
  case category(MusicSearchFilter)
  public static var values: [Self] { [.all] + MusicSearchFilter.allCases.map(Self.category) }
  public var id: String {
    switch self {
    case .all: "all"
    case .category(let filter): filter.identifier
    }
  }
  public var title: String {
    switch self {
    case .all: "Tutto"
    case .category(let filter): filter.rawValue
    }
  }
  var filters: [MusicSearchFilter] {
    switch self {
    case .all: MusicSearchFilter.allCases
    case .category(let filter): [filter]
    }
  }
}

public struct MusicSearchPage: Sendable {
  public let items: [DiscoveryItem]
  public let continuation: String?
  public init(items: [DiscoveryItem], continuation: String? = nil) {
    self.items = items
    self.continuation = continuation
  }
  public static func decode(_ data: Data, filter: MusicSearchFilter) async throws -> Self {
    let page = try await HomePage(YouTubeMusicClient().decodeSearchPage(from: data))
    var seen = Set<String>()
    let items = page.shelves.flatMap(\.items).filter {
      $0.kind == filter.kind && seen.insert($0.id).inserted
    }
    return Self(items: items, continuation: page.continuation)
  }
}

public struct MusicSearchSection: Identifiable, Sendable {
  public let filter: MusicSearchFilter
  public var id: String { filter.identifier }
  public var items: [DiscoveryItem] = []
  public var continuation: String?
  public var loading = true
  public var loadingMore = false
  public var error: String?
  public var moreError: String?
  fileprivate var consumed = Set<String>()
}

/// The phone search is independent of the vehicle's last voice query and playback queue.
/// All categories load in parallel like Android searchAll, displaying fast responses immediately.
@MainActor
public final class MusicSearchModel: ObservableObject {
  public typealias Fetch =
    @Sendable (YouTubeSession?, String, MusicSearchFilter, String?) async throws -> MusicSearchPage
  @Published public var query = ""
  @Published public private(set) var submittedQuery = ""
  @Published public private(set) var scope = MusicSearchScope.all
  @Published public private(set) var sections: [MusicSearchSection] = []
  @Published public private(set) var loading = false
  @Published public private(set) var history: [String]
  private let fetch: Fetch?
  private let saveHistory: @MainActor ([String]) -> Void
  private var session: YouTubeSession?
  private var configured = false
  private var provider: HomeDiscovery?
  private var revision = UUID()
  private var request: Task<Void, Never>?
  private var moreRequests: [MusicSearchFilter: Task<Void, Never>] = [:]

  public init(
    history: [String] = UserDefaults.standard.stringArray(forKey: "musicSearchHistory") ?? [],
    saveHistory: @escaping @MainActor ([String]) -> Void = {
      UserDefaults.standard.set($0, forKey: "musicSearchHistory")
    },
    fetch: Fetch? = nil
  ) {
    self.history = Array(history.prefix(20))
    self.saveHistory = saveHistory
    self.fetch = fetch
  }

  public func configure(session: YouTubeSession?) {
    guard !configured || self.session != session else { return }
    configured = true
    self.session = session
    provider = HomeDiscovery(session: session)
    let previous = submittedQuery
    invalidate()
    if !previous.isEmpty { _ = submit(previous) }
  }
  private func invalidate() {
    revision = UUID()
    request?.cancel()
    for pending in moreRequests.values { pending.cancel() }
    moreRequests = [:]
    sections = []
    loading = false
  }
  public func clear() {
    invalidate()
    query = ""
    submittedQuery = ""
  }
  public func removeHistory(_ value: String? = nil) {
    if let value { history.removeAll { $0 == value } } else { history = [] }
    saveHistory(history)
  }
  @discardableResult
  public func select(_ scope: MusicSearchScope) -> Task<Void, Never>? {
    guard scope != self.scope else { return nil }
    self.scope = scope
    // A draft must not silently replace the submitted query when switching category.
    return submittedQuery.isEmpty ? nil : submit(submittedQuery)
  }
  @discardableResult
  public func submit(_ value: String? = nil) -> Task<Void, Never>? {
    let text = (value ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      clear()
      return nil
    }
    invalidate()
    query = text
    submittedQuery = text
    history.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
    history.insert(text, at: 0)
    history = Array(history.prefix(20))
    saveHistory(history)
    let expected = revision
    let account = session
    let provider = self.provider ?? HomeDiscovery(session: account)
    self.provider = provider
    let fetch = self.fetch
    let filters = scope.filters
    sections = filters.map { MusicSearchSection(filter: $0) }
    loading = true
    request = Task {
      await withTaskGroup(of: (MusicSearchFilter, Result<MusicSearchPage, Error>).self) { group in
        for filter in filters {
          group.addTask {
            do {
              let page: MusicSearchPage
              if let fetch {
                page = try await fetch(account, text, filter, nil)
              } else {
                page = try await provider.searchPage(query: text, filter: filter)
              }
              try Task.checkCancellation()
              return (filter, .success(page))
            } catch { return (filter, .failure(error)) }
          }
        }
        for await (filter, result) in group {
          guard expected == revision, !Task.isCancelled,
            let index = sections.firstIndex(where: { $0.filter == filter })
          else { continue }
          sections[index].loading = false
          switch result {
          case .success(let page): apply(page, to: index)
          case .failure(let error): sections[index].error = Self.message(error)
          }
        }
      }
      guard expected == revision else { return }
      loading = false
    }
    return request
  }

  @discardableResult
  public func retry(_ filter: MusicSearchFilter) -> Task<Void, Never>? {
    guard let index = sections.firstIndex(where: { $0.filter == filter }), !sections[index].loading
    else { return nil }
    return load(filter: filter, continuation: nil)
  }
  @discardableResult
  public func loadMore(_ filter: MusicSearchFilter) -> Task<Void, Never>? {
    guard let section = sections.first(where: { $0.filter == filter }), !section.loading,
      !section.loadingMore, let token = section.continuation
    else { return nil }
    return load(filter: filter, continuation: token)
  }
  private func load(filter: MusicSearchFilter, continuation: String?) -> Task<Void, Never>? {
    guard let index = sections.firstIndex(where: { $0.filter == filter }), !submittedQuery.isEmpty
    else { return nil }
    let expected = revision
    let text = submittedQuery
    let account = session
    let provider = self.provider ?? HomeDiscovery(session: account)
    let fetch = self.fetch
    moreRequests[filter]?.cancel()
    if continuation == nil {
      sections[index].loading = true
      sections[index].error = nil
    } else {
      sections[index].loadingMore = true
      sections[index].moreError = nil
    }
    let task = Task {
      do {
        let page: MusicSearchPage
        if let fetch {
          page = try await fetch(account, text, filter, continuation)
        } else {
          page = try await provider.searchPage(
            query: text, filter: filter, continuation: continuation)
        }
        try Task.checkCancellation()
        guard expected == revision, let index = sections.firstIndex(where: { $0.filter == filter })
        else { return }
        if let token = continuation {
          sections[index].consumed.insert(token)
        } else {
          sections[index].items = []
          sections[index].consumed = []
        }
        apply(page, to: index)
        sections[index].loading = false
        sections[index].loadingMore = false
      } catch {
        guard expected == revision, !Task.isCancelled,
          let index = sections.firstIndex(where: { $0.filter == filter })
        else { return }
        sections[index].loading = false
        sections[index].loadingMore = false
        if continuation == nil {
          sections[index].error = Self.message(error)
        } else {
          sections[index].moreError = Self.message(error)
        }
      }
    }
    moreRequests[filter] = task
    return task
  }
  private func apply(_ page: MusicSearchPage, to index: Int) {
    var seen = Set(sections[index].items.map(\.id))
    sections[index].items += page.items.filter {
      $0.kind == sections[index].filter.kind && seen.insert($0.id).inserted
    }
    sections[index].continuation = page.continuation
    sections[index].moreError = nil
    if let token = page.continuation, sections[index].consumed.contains(token) {
      sections[index].continuation = nil
      sections[index].moreError =
        "YouTube Music ha ripetuto una pagina. Ripeti la ricerca per aggiornare."
    }
  }
  private static func message(_ error: Error) -> String {
    if case LibraryError.authentication = error { return error.localizedDescription }
    return "Ricerca non disponibile. Controlla la connessione e riprova."
  }
}

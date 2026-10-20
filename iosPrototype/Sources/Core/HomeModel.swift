import Combine
import Foundation

@MainActor
public final class HomeModel: ObservableObject {
  public typealias Fetch =
    @Sendable (YouTubeSession?, BrowseTarget, String?) async throws -> HomePage
  @Published public private(set) var shelves: [HomeShelf] = []
  @Published public private(set) var categories: [HomeCategorySection] = []
  @Published public private(set) var loading = false
  @Published public private(set) var loadingMore = false
  @Published public private(set) var selectedFilter = HomeFilter.all
  @Published public private(set) var error: String?
  @Published public private(set) var categoryError: String?
  @Published public private(set) var continuationError: String?
  @Published public private(set) var continuation: String?
  private var session: YouTubeSession?
  private var configured = false
  private let target: BrowseTarget?
  private let fetch: Fetch?
  private var discovery: HomeDiscovery?
  private var revision = UUID()
  private var consumed = Set<String>()
  private var request: Task<Void, Never>?
  private var categoryRequest: Task<Void, Never>?
  private var nextRequest: Task<Void, Never>?

  public init(
    target: BrowseTarget? = nil,
    fetch: Fetch? = nil
  ) {
    self.target = target
    self.fetch = fetch
  }

  public func configure(session: YouTubeSession?) async {
    guard !configured || self.session != session else { return }
    configured = true
    self.session = session
    discovery = HomeDiscovery(session: session)
    selectedFilter = .all
    invalidate()
    categories = []
    categoryError = nil
    await refresh()
  }

  public func select(_ filter: HomeFilter) async {
    guard filter != selectedFilter else { return }
    selectedFilter = filter
    await refresh(loadCategories: false)
  }

  private func invalidate() {
    revision = UUID()
    request?.cancel()
    categoryRequest?.cancel()
    nextRequest?.cancel()
    shelves = []
    continuation = nil
    consumed = []
    loading = false
    loadingMore = false
    error = nil
    continuationError = nil
  }

  public func refresh(loadCategories: Bool = true) async {
    invalidate()
    loading = true
    let expected = revision
    let account = session
    let endpoint = target ?? BrowseTarget(browseId: "FEmusic_home", params: selectedFilter.params)
    if target == nil {
      // Categories are account-dependent too; do not leave another account's recommendations.
      if loadCategories || categories.isEmpty {
        categoryError = nil
        categoryRequest = Task {
          do {
            let page = try await fetchPage(
              account, BrowseTarget(browseId: "FEmusic_moods_and_genres"), nil)
            try Task.checkCancellation()
            guard expected == revision else { return }
            categories = page.categories
          } catch is CancellationError {} catch {
            guard expected == revision else { return }
            categoryError = "Impossibile caricare generi e stati d’animo. Riprova."
          }
        }
      }
    }
    request = Task {
      do {
        let page = try await fetchPage(account, endpoint, nil)
        try Task.checkCancellation()
        guard expected == revision else { return }
        append(page)
        continuation = page.continuation
        loading = false
      } catch is CancellationError {} catch {
        guard expected == revision else { return }
        loading = false
        self.error = Self.message(error)
      }
    }
    await request?.value
    await categoryRequest?.value
  }

  public func loadMore() async {
    guard !loading, !loadingMore, let token = continuation else { return }
    guard !consumed.contains(token) else {
      continuation = nil
      continuationError = "YouTube Music ha ripetuto una pagina. Aggiorna per riprovare."
      return
    }
    loadingMore = true
    continuationError = nil
    let expected = revision
    let account = session
    let endpoint = target ?? BrowseTarget(browseId: "FEmusic_home", params: selectedFilter.params)
    nextRequest = Task {
      do {
        let page = try await fetchPage(account, endpoint, token)
        try Task.checkCancellation()
        guard expected == revision else { return }
        consumed.insert(token)
        append(page)
        loadingMore = false
        if let next = page.continuation, consumed.contains(next) {
          continuation = nil
          continuationError = "YouTube Music ha ripetuto una pagina. Aggiorna per riprovare."
        } else {
          continuation = page.continuation
        }
      } catch is CancellationError {} catch {
        guard expected == revision else { return }
        loadingMore = false
        continuationError = "Le altre sezioni non sono state caricate. " + Self.message(error)
      }
    }
    await nextRequest?.value
  }

  private func append(_ page: HomePage) {
    for shelf in page.shelves {
      if let index = shelves.firstIndex(where: { $0.id == shelf.id }) {
        var seen = Set(shelves[index].items.map(\.id))
        shelves[index].items += shelf.items.filter { seen.insert($0.id).inserted }
      } else {
        shelves.append(shelf)
      }
    }
    for section in page.categories where !categories.contains(where: { $0.id == section.id }) {
      categories.append(section)
    }
  }

  private func fetchPage(_ session: YouTubeSession?, _ target: BrowseTarget, _ token: String?)
    async throws -> HomePage
  {
    if let fetch { return try await fetch(session, target, token) }
    // Parallel category loading must not replace the visitor used by the Home continuation.
    if target.browseId == "FEmusic_moods_and_genres" {
      return try await HomeDiscovery(session: session).page(target: target, continuation: token)
    }
    let provider = discovery ?? HomeDiscovery(session: session)
    discovery = provider
    return try await provider.page(target: target, continuation: token)
  }

  private static func message(_ error: Error) -> String {
    if let library = error as? LibraryError {
      if case .authentication = library { return library.localizedDescription }
    }
    return "Impossibile caricare la pagina di YouTube Music. Controlla la connessione e riprova."
  }
}

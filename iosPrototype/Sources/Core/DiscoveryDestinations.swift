import Combine
import Foundation
import YouTubeSDK

public enum DiscoveryDestination: String, CaseIterable, Identifiable, Sendable {
  case charts, podcasts, mixes
  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .charts: "Classifiche"
    case .podcasts: "Podcast"
    case .mixes: "Mix per te"
    }
  }
  public var symbol: String {
    switch self {
    case .charts: "chart.line.uptrend.xyaxis"
    case .podcasts: "mic.fill"
    case .mixes: "dot.radiowaves.left.and.right"
    }
  }
  public var browseID: String {
    switch self {
    case .charts: "FEmusic_charts"
    case .podcasts: "FEmusic_home"
    case .mixes: "FEmusic_mixed_for_you"
    }
  }
}

public struct DiscoveryCatalog: Sendable {
  let browse: YouTubeBrowse
  let parser = YouTubeMusicClient()
  public init(session: YouTubeSession?, transport: URLSession? = nil) {
    browse = YouTubeBrowse(session: session, transport: transport)
  }
  public func page(
    _ destination: DiscoveryDestination, country: String = "IT", continuation: String? = nil
  ) async throws -> HomePage {
    var params: String?
    if destination == .podcasts && continuation == nil {
      let home = try await browse.request(browseId: "FEmusic_home")
      params = try Self.podcastTarget(in: home).params
    }
    let data = try await browse.request(
      browseId: destination.browseID, params: params, token: continuation,
      country: destination == .charts ? country : nil)
    return try await HomePage(parser.decodeDiscoveryPage(from: data))
  }
  /// YouTube exposes Podcasts as a Home chip, not the obsolete FEmusic_podcasts endpoint.
  public static func podcastTarget(in data: Data) throws -> BrowseTarget {
    let root = try JSONSerialization.jsonObject(with: data)
    func find(_ node: Any) -> BrowseTarget? {
      if let object = node as? [String: Any] {
        if let chip = object["chipCloudChipRenderer"] as? [String: Any],
          let text = chip["text"] as? [String: Any], let runs = text["runs"] as? [[String: Any]],
          runs.compactMap({ $0["text"] as? String }).joined().lowercased().contains("podcast"),
          let navigation = chip["navigationEndpoint"] as? [String: Any],
          let endpoint = navigation["browseEndpoint"] as? [String: Any],
          endpoint["browseId"] as? String == "FEmusic_home",
          let params = endpoint["params"] as? String, !params.isEmpty
        {
          return BrowseTarget(browseId: "FEmusic_home", params: params)
        }
        for value in object.values { if let result = find(value) { return result } }
      } else if let values = node as? [Any] {
        for value in values { if let result = find(value) { return result } }
      }
      return nil
    }
    guard let target = find(root) else { throw LibraryError.malformed }
    return target
  }
}

@MainActor public final class DiscoveryCatalogModel: ObservableObject {
  public typealias Fetch =
    @Sendable (YouTubeSession?, DiscoveryDestination, String, String?) async throws -> HomePage
  @Published public private(set) var shelves: [HomeShelf] = []
  @Published public private(set) var loading = false
  @Published public private(set) var error: String?
  @Published public private(set) var continuation: String?
  public let destination: DiscoveryDestination
  public private(set) var country = "IT"
  private var session: YouTubeSession?
  private var configured = false
  private var revision = UUID()
  private var consumed = Set<String>()
  private let fetch: Fetch?
  private var catalog: DiscoveryCatalog?
  public init(destination: DiscoveryDestination, fetch: Fetch? = nil) {
    self.destination = destination
    self.fetch = fetch
  }
  public func configure(session: YouTubeSession?, country: String = "IT") async {
    guard !configured || self.session != session || self.country != country else { return }
    self.session = session
    catalog = DiscoveryCatalog(session: session)
    self.country = country
    configured = true
    await reload()
  }
  public func reload() async {
    revision = UUID()
    shelves = []
    continuation = nil
    consumed = []
    loading = false
    if destination == .mixes && session == nil {
      error = "Accedi a YouTube Music per i tuoi Mix personali."
      return
    }
    await load(first: true)
  }
  public func more() async {
    guard continuation != nil else { return }
    await load(first: false)
  }
  private func load(first: Bool) async {
    guard !loading else { return }
    loading = true
    error = nil
    let expected = revision
    let token = first ? nil : continuation
    do {
      let page: HomePage
      if let fetch {
        page = try await fetch(session, destination, country, token)
      } else {
        let provider = catalog ?? DiscoveryCatalog(session: session)
        catalog = provider
        page = try await provider.page(destination, country: country, continuation: token)
      }
      try Task.checkCancellation()
      guard revision == expected else { return }
      if let next = page.continuation, consumed.contains(next) || next == token {
        throw LibraryError.repeatedContinuation
      }
      if let token { consumed.insert(token) }
      for shelf in page.shelves {
        if let index = shelves.firstIndex(where: { $0.id == shelf.id }) {
          var seen = Set(shelves[index].items.map(\.id))
          shelves[index].items += shelf.items.filter { seen.insert($0.id).inserted }
        } else {
          shelves.append(shelf)
        }
      }
      continuation = page.continuation
      loading = false
    } catch {
      guard revision == expected else { return }
      loading = false
      if !(error is CancellationError) {
        self.error = "Non riesco a caricare \(destination.title.lowercased()). Riprova."
      }
    }
  }
}

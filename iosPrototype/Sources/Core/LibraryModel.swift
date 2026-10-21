import Combine
import Foundation

@MainActor
public final class LibraryModel: ObservableObject {
  @Published public private(set) var session: YouTubeSession?
  @Published public private(set) var albums: [LibraryAlbum] = []
  @Published public private(set) var loading = false
  @Published public var error: String?
  @Published public var showLogin = false
  private var request: Task<Void, Never>?
  private var revision = UUID()

  private let save: @MainActor (YouTubeSession?) throws -> Void
  private let fetch: @Sendable (YouTubeSession) async throws -> [LibraryAlbum]

  public init(
    session: YouTubeSession?, save: @escaping @MainActor (YouTubeSession?) throws -> Void,
    fetch: @escaping @Sendable (YouTubeSession) async throws -> [LibraryAlbum]
  ) {
    self.session = session
    self.save = save
    self.fetch = fetch
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
    request?.cancel()
    revision = UUID()
    albums = []
    loading = false
    error = nil
  }

  public func refresh() {
    guard let session else { return }
    invalidate()
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
}

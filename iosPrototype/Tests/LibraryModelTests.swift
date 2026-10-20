import XCTest

@testable import PrototypeCore

@MainActor
final class LibraryModelTests: XCTestCase {
  private func account(_ id: String) -> YouTubeSession {
    YouTubeSession(cookies: "SAPISID=dummy", identity: id, clientVersion: "test")
  }
  func testSignedOutDoesNotRequestAndLogoutClearsAlbums() async {
    let model = LibraryModel(
      session: nil, save: { _ in },
      fetch: { _ in
        [LibraryAlbum(id: "album", title: "Album", artist: "Artista", artwork: nil)]
      })
    await model.reload()
    XCTAssertFalse(model.loading)
    XCTAssertTrue(model.albums.isEmpty)
    model.connect(account("A"))
    await model.reload()
    XCTAssertEqual(model.albums.count, 1)
    model.disconnect()
    XCTAssertNil(model.session)
    XCTAssertTrue(model.albums.isEmpty)
    await model.reload()
    XCTAssertTrue(model.albums.isEmpty)
  }
  func testAccountSwitchRejectsOldInFlightResults() async throws {
    let model = LibraryModel(
      session: account("old"), save: { _ in },
      fetch: { session in
        if session.identity == "old" { try? await Task.sleep(for: .milliseconds(100)) }
        return [LibraryAlbum(id: session.identity, title: "Album", artist: "Artista", artwork: nil)]
      })
    model.refresh()
    await Task.yield()
    model.connect(account("new"))
    await model.reload()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(model.session?.identity, "new")
    XCTAssertEqual(model.albums.map(\.id), ["new"])
    XCTAssertFalse(model.loading)
  }
  func testRefreshFailureClearsPreviousResults() async {
    let model = LibraryModel(
      session: account("old"), save: { _ in },
      fetch: { session in
        if session.identity == "expired" { throw LibraryError.authentication }
        return [LibraryAlbum(id: "old", title: "Album", artist: "Artista", artwork: nil)]
      })
    await model.reload()
    XCTAssertEqual(model.albums.count, 1)
    model.connect(account("expired"))
    await model.reload()
    XCTAssertTrue(model.albums.isEmpty)
    XCTAssertNotNil(model.error)
  }
  func testSignedOutNeverCallsNetworkAndLogoutRejectsLateResponse() async throws {
    actor Counter {
      var count = 0
      func increment() { count += 1 }
    }
    let counter = Counter()
    let model = LibraryModel(
      session: nil, save: { _ in },
      fetch: { _ in
        await counter.increment()
        // Simulate a transport which completes despite cancellation.
        try? await Task.sleep(for: .milliseconds(100))
        return [LibraryAlbum(id: "late", title: "Album", artist: "Artista", artwork: nil)]
      })
    await model.reload()
    let signedOutCalls = await counter.count
    XCTAssertEqual(signedOutCalls, 0)
    model.connect(account("A"))
    while await counter.count == 0 { await Task.yield() }
    model.disconnect()
    try await Task.sleep(for: .milliseconds(150))
    XCTAssertNil(model.session)
    XCTAssertTrue(model.albums.isEmpty)
    XCTAssertFalse(model.loading)
    XCTAssertNil(model.error)
    await model.reload()
    let finalCalls = await counter.count
    XCTAssertEqual(finalCalls, 1)
  }

}

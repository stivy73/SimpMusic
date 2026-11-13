import XCTest
@testable import LyricsContract

private struct SyncSong: Identifiable, Sendable {
  let id: String
  var aliases: Set<String> = []
  var title = "Song"
  var artist = "Artist"
  var album = "Album"
  var duration = 180.0
  var identity: LibrarySongIdentity { .init(ids: aliases.union([id]), title: title, artist: artist, album: album, duration: duration) }
}
private actor RecoveryCalls {
  var albums = 0, searches = 0, catalog = 0
  func album(_ items: [SyncSong]) -> [SyncSong] { albums += 1; return items }
  func search(_ items: [SyncSong]) -> [SyncSong] { searches += 1; return items }
  func catalog(_ items: [SyncSong]) -> [SyncSong] { catalog += 1; return items }
  func counts() -> [Int] { [albums, searches, catalog] }
}
final class LibrarySyncTests: XCTestCase {
  func testCategoryCanRetryWhileOthersLoadAndOldCleanupCannotCancelNewRetry() {
    var activity = LibrarySyncActivity()
    let initial = activity.begin(Set(BrowseKind.allCases))
    XCTAssertEqual(initial.categories.count, 4)
    XCTAssertTrue(activity.begin([.songs]).categories.isEmpty)
    activity.finish(.albums, work: initial.id)
    let retry = activity.begin([.albums])
    XCTAssertEqual(retry.categories, [.albums])
    XCTAssertFalse(activity.finish(.albums, work: initial.id))
    XCTAssertTrue(activity.begin([.albums]).categories.isEmpty)
    for kind in initial.categories { activity.finish(kind, work: initial.id) }
    XCTAssertTrue(activity.busy)
    XCTAssertTrue(activity.finish(.albums, work: retry.id)); XCTAssertFalse(activity.busy)
  }
  func testFourteenDeviceTracksRecoverFromOwnedAlbumEvenWhenCatalogHasNone() async throws {
    let references = (1...14).map { LibraryTrackReference(storeID: String($0), title: "Song \($0)", artist: "Artist", album: "Album") }
    let owned = (1...14).map { SyncSong(id: "i.\($0)", title: "Song \($0)") }
    let calls = RecoveryCalls()
    let result = try await LibrarySongRecovery.recover(references: references, available: [], id: { $0.id }, identity: { $0.identity },
      albumTracks: { _ in await calls.album(owned) }, search: { _ in await calls.search([]) }, catalog: { _ in await calls.catalog([]) })
    XCTAssertEqual(result.items.map(\.id), owned.map(\.id))
    XCTAssertEqual(result.unresolved, 0)
    let counts = await calls.counts(); XCTAssertEqual(counts, [1, 0, 0])
    let published = LibrarySyncPolicy.reconcile(previous: [SyncSong](), local: .success([]), cloud: .success([]), recovered: result.items, unresolved: result.unresolved)
    XCTAssertEqual(published.state.phase, .ready); XCTAssertEqual(published.items.count, 14)
  }
  func testRecoveryCompletesNonemptyPartialLibraryWithoutDuplicatingExistingSongs() async throws {
    let references = (1...14).map { LibraryTrackReference(storeID: String($0), title: "Song \($0)", artist: "Artist", album: "Album") }
    let native = (1...7).map { SyncSong(id: String($0), title: "Song \($0)") }
    let personal = (1...14).map { SyncSong(id: "i.\($0)", aliases: [String($0)], title: "Song \($0)") }
    let result = try await LibrarySongRecovery.recover(references: references, available: native, id: { $0.id }, identity: { $0.identity },
      albumTracks: { _ in personal }, search: { _ in XCTFail("Already recovered"); return [] }, catalog: { _ in XCTFail("Already recovered"); return [] })
    XCTAssertEqual(result.items.count, 14); XCTAssertEqual(result.unresolved, 0)
  }
  func testUploadWithoutCatalogIDIsRecoveredByPersonalMetadataWithoutInventingSongIDs() async throws {
    let references = [LibraryTrackReference(storeID: "", title: "Import", artist: "My Artist", album: "My Album")]
    let result = try await LibrarySongRecovery.recover(references: references, available: [SyncSong](), id: { $0.id }, identity: { $0.identity },
      albumTracks: { _ in throw URLError(.timedOut) }, search: { _ in [SyncSong(id: "i.actual", title: "Import", artist: "My Artist", album: "My Album")] },
      catalog: { _ in XCTFail("No public ID for upload"); return [] })
    XCTAssertEqual(result.items.map(\.id), ["i.actual"]); XCTAssertEqual(result.unresolved, 0)
  }
  func testUnresolvedDeviceTracksRemainPartialEvenWithTwoSuccessfulEmptyEnumerations() async throws {
    let references = [LibraryTrackReference(storeID: "42", title: "Missing", artist: "Artist", album: "Album")]
    let result = try await LibrarySongRecovery.recover(references: references, available: [SyncSong](), id: { $0.id }, identity: { $0.identity },
      albumTracks: { _ in [] }, search: { _ in [] }, catalog: { _ in [] })
    let published = LibrarySyncPolicy.reconcile(previous: [SyncSong](), local: .success([]), cloud: .success([]), recovered: result.items, unresolved: result.unresolved)
    XCTAssertEqual(result.unresolved, 1); XCTAssertEqual(published.state.phase, .partial)
    XCTAssertTrue(published.state.needsRetry)
  }
  func testEditionAndDurationDifferencesDoNotCountAsRecoveredRecording() {
    let original = LibraryTrackReference(storeID: "0", title: "Song", artist: "Artist", album: "Album", duration: 180)
    XCTAssertTrue(SyncSong(id: "i.correct").identity.matches(original))
    XCTAssertFalse(SyncSong(id: "i.live", title: "Song (Live)").identity.matches(original))
    XCTAssertFalse(SyncSong(id: "i.deluxe", album: "Album Deluxe").identity.matches(original))
    XCTAssertFalse(SyncSong(id: "i.long", duration: 240).identity.matches(original))
  }
  func testCatalogCannotInjectUnrequestedTrack() async throws {
    let result = try await LibrarySongRecovery.recover(references: [.init(storeID: "42", title: "", artist: "", album: "")], available: [SyncSong](), id: { $0.id }, identity: { $0.identity },
      albumTracks: { _ in [] }, search: { _ in [] }, catalog: { _ in [SyncSong(id: "99")] })
    XCTAssertTrue(result.items.isEmpty); XCTAssertEqual(result.unresolved, 1); XCTAssertEqual(result.failedReads, 1)
  }
  func testCatalogRecoveryIsLimitedToUnresolvedIDs() async throws {
    let references = [LibraryTrackReference(storeID: "1", title: "Song", artist: "Artist", album: "Album"), .init(storeID: "2", title: "Other", artist: "Artist", album: "Other")]
    let result = try await LibrarySongRecovery.recover(references: references, available: [SyncSong(id: "1")], id: { $0.id }, identity: { $0.identity },
      albumTracks: { _ in [] }, search: { _ in [] }, catalog: { ids in XCTAssertEqual(ids, ["2"]); return [SyncSong(id: "2", title: "Other", album: "Other")] })
    XCTAssertEqual(result.items.map(\.id), ["1", "2"]); XCTAssertEqual(result.unresolved, 0)
  }
  func testFailurePreservesLastSnapshotAndReportsPartialInsteadOfEmpty() {
    let result = LibrarySyncPolicy.reconcile(previous: [SyncSong(id: "old")], local: .success([]), cloud: .failure("Offline"))
    XCTAssertEqual(result.items.map(\.id), ["old"]); XCTAssertEqual(result.state.phase, .partial)
    XCTAssertEqual(result.state.message, "Offline")
  }
  func testTwoSuccessfulReadsRemoveDeletedRowsAndAllowGenuinelyEmptyLibrary() {
    let old = [SyncSong(id: "removed")]
    let removed = LibrarySyncPolicy.reconcile(previous: old, local: .success([]), cloud: .success([SyncSong(id: "new")]))
    XCTAssertEqual(removed.items.map(\.id), ["new"]); XCTAssertEqual(removed.state.phase, .ready)
    let empty = LibrarySyncPolicy.reconcile(previous: old, local: .success([]), cloud: .success([]))
    XCTAssertTrue(empty.items.isEmpty); XCTAssertEqual(empty.state.phase, .ready)
  }
  func testEmptyEnumerationsCannotEraseSnapshotWhileDeviceRecoveryIsIncomplete() {
    let result = LibrarySyncPolicy.reconcile(previous: [SyncSong(id: "i.existing")], local: .success([]), cloud: .success([]), unresolved: 14)
    XCTAssertEqual(result.items.map(\.id), ["i.existing"])
    XCTAssertEqual(result.state.phase, .partial); XCTAssertEqual(result.state.unresolved, 14)
  }
  func testTotalFailureDoesNotChangeLastSuccessTimeOrEraseRows() {
    let time = Date(timeIntervalSince1970: 123)
    let result = LibrarySyncPolicy.reconcile(previous: [SyncSong(id: "old")], local: .failure("Local"), cloud: .failure("Cloud"), previousState: .init(phase: .ready, updatedAt: time))
    XCTAssertEqual(result.state.phase, .failed); XCTAssertEqual(result.state.updatedAt, time); XCTAssertEqual(result.items.count, 1)
  }
  func testCanceledRecoveryCannotBecomeSuccessfulEmptyRead() async {
    do {
      _ = try await LibrarySongRecovery.recover(references: [.init(storeID: "42", title: "Song", artist: "Artist", album: "Album")], available: [SyncSong](), id: { $0.id }, identity: { $0.identity },
        albumTracks: { _ in throw CancellationError() }, search: { _ in XCTFail("Canceled"); return [] }, catalog: { _ in XCTFail("Canceled"); return [] })
      XCTFail("Cancellation must propagate")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
}

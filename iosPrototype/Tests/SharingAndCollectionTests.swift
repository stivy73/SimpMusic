import Foundation
import XCTest

@testable import PrototypeCore

@MainActor final class SharingAndCollectionTests: XCTestCase {
  func testYouTubePermalinksStripTrackingAndKeepExactVideo() {
    for link in [
      "https://music.youtube.com/watch?v=dQw4w9WgXcQ&si=privateToken",
      "https://youtu.be/dQw4w9WgXcQ?t=12", "https://www.youtube.com/shorts/dQw4w9WgXcQ",
      "https://youtube.com/live/dQw4w9WgXcQ",
    ] {
      XCTAssertEqual(SharedMusicTarget.parse([link]), .video("dQw4w9WgXcQ"))
    }
    XCTAssertEqual(
      SharedMusicTarget.parse([
        "https://music.youtube.com/playlist?list=OLAK5uy_sample123&si=secret"
      ]), .playlist("OLAK5uy_sample123"))
  }
  func testNowPlayingUsesSameTitleAndArtistAsAndroid() {
    XCTAssertEqual(
      SharedMusicTarget.parse(["\"Heroes\" di David Bowie\nhttps://www.google.com/search?q=Heroes"]
      ), .search("Heroes David Bowie"))
    XCTAssertEqual(
      SharedMusicTarget.parse([
        "Old and Wise by The Alan Parsons Project\nhttps://www.google.com/search?q=music"
      ]), .search("Old and Wise The Alan Parsons Project"))
    XCTAssertEqual(
      SharedMusicTarget.parse(["“Dreams” by Fleetwood Mac"]), .search("Dreams Fleetwood Mac"))
    XCTAssertEqual(SharedMusicTarget.parse(["Titolo di Artista"]), .search("Titolo di Artista"))
  }
  func testDuplicateProvidersAndURLMetadataDoNotPolluteTheQuery() {
    XCTAssertEqual(
      SharedMusicTarget.parse([
        "Heroes David Bowie", "Heroes David Bowie",
        "https://open.spotify.com/track/123?token=secret",
      ]), .search("Heroes David Bowie"))
    XCTAssertEqual(SharedMusicTarget.parse(["Wild Side\nLou Reed"]), .search("Wild Side Lou Reed"))
    XCTAssertNil(SharedMusicTarget.parse(["https://open.spotify.com/track/123?token=secret"]))
  }
  func testMalformedAndUnsupportedURLsNeverBecomePlayableIDs() {
    for text in [
      "", "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
      "https://youtube.com@evil.example/watch?v=dQw4w9WgXcQ",
      "https://user:pass@youtube.com/watch?v=dQw4w9WgXcQ",
      "https://youtube.com:999/watch?v=dQw4w9WgXcQ", "https://youtu.be/../private",
      "https://youtube.com/watch?v=bad", String(repeating: "x", count: 301),
    ] {
      XCTAssertNil(SharedMusicTarget.parse([text]), text)
    }
    XCTAssertFalse(SharedMusicTarget.search(String(repeating: "x", count: 301)).valid)
  }
  func testInboxPersistsSeparateRequestsAndAcknowledgesOneAtATime() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let inbox = SharedMusicInbox(directory: folder)
    let a = SharedMusicRequest(target: .video("dQw4w9WgXcQ"), date: Date(timeIntervalSince1970: 1))
    let b = SharedMusicRequest(
      target: .search("Heroes David Bowie"), date: Date(timeIntervalSince1970: 2))
    try inbox.save(a)
    try inbox.save(b)
    XCTAssertEqual(SharedMusicInbox(directory: folder).pending(), [a, b])
    try inbox.remove(a.id)
    XCTAssertEqual(inbox.pending(), [b])
    let stored = try String(
      contentsOf: inbox.directory.appendingPathComponent(b.id.uuidString + ".json"), encoding: .utf8
    )
    for secret in ["cookie", "apiKey", "https://", "privateToken"] {
      XCTAssertFalse(stored.contains(secret))
    }
  }
  func testInboxIsBoundedRejectsCorruptionAndInvalidPayloads() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let inbox = SharedMusicInbox(directory: folder)
    for n in 0..<24 {
      try inbox.save(
        .init(target: .search("Brano \(n)"), date: Date(timeIntervalSince1970: Double(n))))
    }
    XCTAssertEqual(inbox.pending().count, 20)
    XCTAssertEqual(inbox.pending().first?.target, .search("Brano 4"))
    try Data("broken".utf8).write(
      to: inbox.directory.appendingPathComponent(UUID().uuidString + ".json"))
    let invalid = SharedMusicRequest(target: .video("invalid"))
    try JSONEncoder().encode(invalid).write(
      to: inbox.directory.appendingPathComponent(invalid.id.uuidString + ".json"))
    XCTAssertThrowsError(try inbox.save(invalid))
    XCTAssertEqual(inbox.pending().count, 20)
  }
  func testCollectionOrderingIsNaturalStableAndLeavesInputUntouched() {
    let values = ["Zeta", "Brano 10", "Brano 2", "Échos", "Alpha", "Alpha"]
    var value = CollectionPresentation()
    XCTAssertEqual(value.sorted(values, title: { $0 }, artist: { _ in "" }), values)
    value.order = .title
    XCTAssertEqual(
      value.sorted(values, title: { $0 }, artist: { _ in "" }),
      ["Alpha", "Alpha", "Brano 2", "Brano 10", "Échos", "Zeta"])
    value.descending = true
    XCTAssertEqual(
      value.sorted(values, title: { $0 }, artist: { _ in "" }),
      ["Zeta", "Échos", "Brano 10", "Brano 2", "Alpha", "Alpha"])
    XCTAssertEqual(values.first, "Zeta")
  }
  func testArtistSortUsesTitleForTiesAndPreservesStableIdentity() {
    let tracks = [("B", "Artista"), ("A", "Artista"), ("C", "Zeta")]
    var value = CollectionPresentation()
    value.order = .artist
    XCTAssertEqual(
      value.sorted(tracks, title: { $0.0 }, artist: { $0.1 }).map { $0.0 }, ["A", "B", "C"])
    value.order = .original
    value.descending = true
    XCTAssertEqual(
      value.sorted(tracks, title: { $0.0 }, artist: { $0.1 }).map { $0.0 }, ["C", "A", "B"])
  }
  func testAlphabetHandlesAccentsWhitespaceNumbersAndNonLatinText() {
    XCTAssertEqual(CollectionPresentation.letter("  Échos"), "E")
    XCTAssertEqual(CollectionPresentation.letter("123"), "#")
    XCTAssertEqual(CollectionPresentation.letter(""), "#")
    XCTAssertEqual(CollectionPresentation.letter("宇多田"), "宇")
    var value = CollectionPresentation()
    value.order = .artist
    XCTAssertEqual(value.indexKey(title: "Zulu", artist: "Álvaro"), "A")
  }
  func testDisplayPreferencesPersistIndependentlyAndCorruptDataFallsBack() {
    let name = "nn-collection-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = CollectionPreferences(defaults: defaults)
    var saved = CollectionPresentation(layout: .list)
    saved.order = .artist
    saved.alphabeticalIndex = true
    store.save(saved, collection: "albums")
    XCTAssertEqual(CollectionPreferences(defaults: defaults).load("albums", layout: .grid), saved)
    XCTAssertEqual(store.load("artists", layout: .grid), CollectionPresentation(layout: .grid))
    defaults.set(Data("broken".utf8), forKey: "collectionPresentation.albums")
    XCTAssertEqual(store.load("albums", layout: .grid), CollectionPresentation(layout: .grid))
  }
}

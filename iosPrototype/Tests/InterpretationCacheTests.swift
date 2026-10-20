import Foundation
import XCTest

@testable import PrototypeCore

final class InterpretationCacheTests: XCTestCase {
  func testIdentityIncludesModelSourceAndSong() throws {
    let key = try InterpretationCache.key(model: "m", title: "t", artist: "a", lyrics: "words")
    XCTAssertEqual(
      key, try InterpretationCache.key(model: "m", title: "t", artist: "a", lyrics: " words \n"))
    XCTAssertNotEqual(
      key, try InterpretationCache.key(model: "other", title: "t", artist: "a", lyrics: "words"))
    XCTAssertNotEqual(
      key, try InterpretationCache.key(model: "m", title: "t", artist: "a", lyrics: "manual lyrics")
    )
    XCTAssertNotEqual(
      key, try InterpretationCache.key(model: "m", title: "t2", artist: "a", lyrics: "words"))
    XCTAssertNotEqual(
      key, try InterpretationCache.key(model: "m", title: "t", artist: "a2", lyrics: "words"))
    XCTAssertThrowsError(
      try InterpretationCache.key(model: "m", title: "t", artist: "a", lyrics: " "))
  }
  func testPersistenceAndExpiry() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let key = try InterpretationCache.key(model: "m", title: "t", artist: "a", lyrics: "source")
    let cache = InterpretationCache(directory: dir)
    await cache.store("Interpretazione completa.", key: key)
    let second = InterpretationCache(directory: dir)
    let value = await second.read(key)
    XCTAssertEqual(value, "Interpretazione completa.")
    let expired = InterpretationCache(directory: dir, lifetime: -1)
    let stale = await expired.read(key)
    XCTAssertNil(stale)
    try Data([0xff]).write(to: dir.appendingPathComponent(key + ".txt"))
    let corrupt = await second.read(key)
    XCTAssertNil(corrupt)
  }
  func testBoundedAndEmptyCacheEntries() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = InterpretationCache(directory: dir, capacity: 2)
    let keys = try (0..<3).map {
      try InterpretationCache.key(model: "m", title: String($0), artist: "a", lyrics: "source")
    }
    for key in keys { await cache.store("Complete text.", key: key) }
    let files = try FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: nil)
    XCTAssertEqual(files.count, 2)
    await cache.store(" ", key: keys[0])
    await cache.store("Invalid path", key: "../outside")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
  }
}

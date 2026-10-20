import Foundation
import XCTest

@testable import PrototypeCore

final class CarPlayContentTests: XCTestCase {
  func testAlbumArtistContextDoesNotIncludeTypeAndYear() {
    XCTAssertEqual(AlbumTrackMetadata.artist(from: "Album • Eddie Vedder • 2007"), "Eddie Vedder")
    XCTAssertEqual(AlbumTrackMetadata.artist(from: "Bartek Dabrowski · 2020"), "Bartek Dabrowski")
    XCTAssertEqual(
      AlbumTrackMetadata.artist(from: "The Alan Parsons Project"), "The Alan Parsons Project")
    XCTAssertNil(AlbumTrackMetadata.artist(from: "Album • 2020"))
    XCTAssertNil(AlbumTrackMetadata.artist(from: nil))
  }
  func testEveryAlbumIsReachableExactlyOnceAcrossLargeLibrary() {
    var indices: [Int] = []
    var offset = 0
    repeat {
      let page = CarPlayPage(count: 513, offset: offset, capacity: 8)
      XCTAssertLessThanOrEqual(page.range.count, 8)
      indices += page.range
      guard let next = page.next else { break }
      XCTAssertEqual(CarPlayPage(count: 513, offset: next, capacity: 8).previous, offset)
      offset = next
    } while true
    XCTAssertEqual(indices, Array(0..<513))
  }
  func testEmptyAndShrinkingLibraryClampThePage() {
    XCTAssertEqual(CarPlayPage(count: 0, offset: 100, capacity: 8).range, 0..<0)
    let shrunk = CarPlayPage(count: 9, offset: 500, capacity: 8)
    XCTAssertEqual(shrunk.range, 8..<9)
    XCTAssertNil(shrunk.next)
    XCTAssertEqual(CarPlayPage(count: 3, offset: -1, capacity: 8).range, 0..<3)
  }
  func testAlbumCoverIsPreferredAndVideoFallbackDoesNotReplaceIt() throws {
    let cover = try XCTUnwrap(URL(string: "https://lh3.googleusercontent.com/album"))
    let urls = ArtworkSource.candidates(primary: cover, videoID: "ZmzqqdVFw8g")
    XCTAssertEqual(urls.first, cover)
    XCTAssertEqual(urls.count, 2)
    XCTAssertEqual(
      ArtworkSource.candidates(primary: nil, videoID: "ZmzqqdVFw8g").first?.host, "i.ytimg.com")
  }
  func testInvalidVideoIDDoesNotProduceAnArtworkRequest() {
    for id in ["", "../../etc/a", "bad?id=1234", "ànvalid1234"] {
      XCTAssertTrue(ArtworkSource.candidates(primary: nil, videoID: id).isEmpty)
    }
    XCTAssertTrue(ArtworkSource.candidates(primary: URL(string: "file:///tmp/cover")).isEmpty)
  }
}

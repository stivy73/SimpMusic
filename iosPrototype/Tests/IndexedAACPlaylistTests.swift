import Foundation
import XCTest

@testable import PrototypeCore

final class IndexedAACPlaylistTests: XCTestCase {
  private let origin = URL(string: "https://fixture.googlevideo.com/audio?sig=test%2Bvalue")!

  private func word(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }

  private func box(_ name: String, _ body: Data) -> Data {
    word(UInt32(body.count + 8)) + Data(name.utf8) + body
  }

  private var initialization: Data {
    box("ftyp", Data("dash".utf8) + word(0) + Data("iso6".utf8)) + box("moov", box("mvex", Data()))
  }

  private func index(
    version: UInt8 = 0, references: [(size: UInt32, ticks: UInt32)] = [(100, 5500), (200, 4750)],
    timescale: UInt32 = 1000, firstOffset: UInt32 = 0, declaredCount: UInt16? = nil
  ) -> Data {
    var body = Data([version, 0, 0, 0]) + word(1) + word(timescale)
    if version == 1 { body += word(0) }
    body += word(0) // earliest_presentation_time
    if version == 1 { body += word(0) }
    body += word(firstOffset)
    body += word(UInt32(declaredCount ?? UInt16(references.count)))
    for reference in references {
      body += word(reference.size) + word(reference.ticks) + word(0x9000_0000)
    }
    return box("sidx", body)
  }

  func testBothIndexVersionsRespectInitAndMediaOffsetsAndPreserveOrigin() throws {
    for version in [UInt8(0), 1] {
      let padding = box("free", Data(repeating: 0, count: 4))
      let prefix = initialization + padding + index(version: version, firstOffset: 7)
      let mediaStart = prefix.count + 7
      let length = Int64(mediaStart + 300)
      let data = try XCTUnwrap(IndexedAACPlaylist.make(
        prefix: prefix + Data(repeating: 0, count: 15), url: origin, length: length, duration: 10.25))
      let manifest = String(decoding: data, as: UTF8.self)
      let expectedMap = "#EXT-X-MAP:URI=\"\(origin.absoluteString)\",BYTERANGE=\"\(initialization.count)@0\""
      XCTAssertTrue(manifest.contains(expectedMap))
      XCTAssertTrue(manifest.contains("#EXT-X-TARGETDURATION:6\n"))
      XCTAssertTrue(manifest.contains("#EXTINF:5.5,\n#EXT-X-BYTERANGE:100@\(mediaStart)\n\(origin.absoluteString)\n"))
      XCTAssertTrue(manifest.contains("#EXTINF:4.75,\n#EXT-X-BYTERANGE:200@\(mediaStart + 100)\n\(origin.absoluteString)\n"))
      XCTAssertTrue(manifest.hasSuffix("#EXT-X-ENDLIST\n"))
    }
  }

  func testCompleteHourLongIndexSupportsLastShortFragmentAndRoundedCatalogDuration() throws {
    let fullSegments = Array(repeating: (size: UInt32(160_000), ticks: UInt32(10_000)), count: 384)
    let prefix = initialization + index(references: fullSegments + [(12_000, 790)])
    let lastOffset = prefix.count + 384 * 160_000
    let data = try XCTUnwrap(IndexedAACPlaylist.make(
      prefix: prefix, url: origin, length: Int64(lastOffset + 12_000), duration: 3841))
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    XCTAssertEqual(lines.filter { $0.hasPrefix("#EXTINF:") }.count, 385)
    XCTAssertTrue(lines.contains("#EXT-X-BYTERANGE:12000@\(lastOffset)"))
  }

  func testTruncatedHeadersTablesAndInvalidBoxOrderingFallBack() {
    let sidx = index(version: 1)
    let valid = initialization + sidx
    for byteCount in 0..<valid.count {
      XCTAssertNil(IndexedAACPlaylist.make(
        prefix: Data(valid.prefix(byteCount)), url: origin, length: Int64(valid.count + 300),
        duration: 10.25), "Accepted prefix truncated at \(byteCount) bytes")
    }
    for prefix in [sidx, box("ftyp", Data()) + sidx,
                   box("ftyp", Data()) + box("moov", box("mvhd", Data())) + sidx,
                   initialization + index(declaredCount: 3),
                   initialization + index(version: 2)] {
      XCTAssertNil(IndexedAACPlaylist.make(
        prefix: prefix, url: origin, length: Int64(prefix.count + 300), duration: 10.25))
    }
  }

  func testRequiresCompleteFileAndDurationCoverage() {
    let prefix = initialization + index()
    let length = Int64(prefix.count + 300)
    for invalidLength in [length - 1, length + 1, 0] {
      XCTAssertNil(IndexedAACPlaylist.make(prefix: prefix, url: origin, length: invalidLength, duration: 10.25))
    }
    for duration in [300, 0, .nan, .infinity] {
      XCTAssertNil(IndexedAACPlaylist.make(prefix: prefix, url: origin, length: length, duration: duration))
    }
  }

  func testRejectsNestedEmptyAndUnusableReferences() {
    for sidx in [index(references: [(0x8000_0001, 10_250)]), index(references: []),
                 index(references: [(0, 10_250)]), index(references: [(300, 0)]),
                 index(timescale: 0), index(firstOffset: UInt32.max)] {
      let prefix = initialization + sidx
      XCTAssertNil(IndexedAACPlaylist.make(
        prefix: prefix, url: origin, length: Int64(prefix.count + 300), duration: 10.25))
    }
  }

  func testRejectsUntrustedOriginsAndOversizedPlaylistExpansion() {
    let prefix = initialization + index()
    for address in ["http://fixture.googlevideo.com/audio", "https://googlevideo.com.example.org/audio"] {
      XCTAssertNil(IndexedAACPlaylist.make(prefix: prefix, url: URL(string: address)!,
        length: Int64(prefix.count + 300), duration: 10.25))
    }
    let longOrigin = origin.appending(queryItems: [URLQueryItem(name: "padding", value: String(repeating: "x", count: 7000))])
    let manySegments = initialization + index(references: Array(repeating: (size: 2, ticks: 1000), count: 640))
    XCTAssertNil(IndexedAACPlaylist.make(
      prefix: manySegments, url: longOrigin, length: Int64(manySegments.count + 1280), duration: 640))
  }
}

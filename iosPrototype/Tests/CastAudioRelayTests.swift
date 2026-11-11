import XCTest

@testable import PrototypeCore

final class CastAudioRelayTests: XCTestCase {
  @MainActor func testRanges() throws {
    XCTAssertEqual(try CastAudioRelay.bounds(nil, length: 100), 0..<100)
    XCTAssertEqual(try CastAudioRelay.bounds("bytes=10-19", length: 100), 10..<20)
    XCTAssertEqual(try CastAudioRelay.bounds("bytes=90-", length: 100), 90..<100)
    XCTAssertEqual(try CastAudioRelay.bounds("bytes=-12", length: 100), 88..<100)
    XCTAssertEqual(try CastAudioRelay.bounds("bytes=90-200", length: 100), 90..<100)
    for invalid in ["bytes=100-", "bytes=8-4", "bytes=0-1,3-4", "bytes=-0", "bytes=x-y"] {
      XCTAssertThrowsError(try CastAudioRelay.bounds(invalid, length: 100))
    }
  }
  @MainActor func testRelayServesExactBytesAcrossBlocksAndRejectsWrongToken() async throws {
    let data = Data((0..<400000).map { UInt8($0 % 251) })
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let relay = CastAudioRelay()
    defer { relay.stop() }
    let url = try await relay.start(source: nil, file: file)
    var request = URLRequest(url: url, timeoutInterval: 5)
    request.setValue("bytes=130000-270000", forHTTPHeaderField: "Range")
    let (received, response) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 206)
    XCTAssertEqual(received, data.subdata(in: 130000..<270001))
    request = URLRequest(
      url: url.deletingLastPathComponent().appendingPathComponent("wrong"), timeoutInterval: 5)
    let (_, rejected) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 404)
    request = URLRequest(url: url, timeoutInterval: 5)
    request.setValue("bytes=400000-", forHTTPHeaderField: "Range")
    let (_, invalid) = try await URLSession.shared.data(for: request)
    XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode, 416)
    request = URLRequest(url: url, timeoutInterval: 5)
    request.httpMethod = "HEAD"
    let (head, info) = try await URLSession.shared.data(for: request)
    XCTAssertEqual(head.count, 0)
    let (full, fullInfo) = try await URLSession.shared.data(from: url)
    XCTAssertEqual(full, data)
    XCTAssertEqual((fullInfo as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertEqual(
      (info as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length"), "400000")
  }
}

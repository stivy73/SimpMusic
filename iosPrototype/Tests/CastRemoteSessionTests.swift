import Foundation
import XCTest
@testable import PrototypeCore

final class CastRemoteSessionTests: XCTestCase {
  func testCastFrameMatchesProtobufFieldsAndNetworkLength() throws {
    let json = Data(#"{"type":"GET_STATUS","requestId":7}"#.utf8)
    let framed = try CastWire.frame(source: "phone", destination: "receiver-0", namespace: CastWire.receiver, json: json)
    XCTAssertEqual(framed.prefix(4).reduce(0) { $0 << 8 | Int($1) }, framed.count - 4)
    XCTAssertEqual(Array(framed.dropFirst(4).prefix(2)), [8, 0])
    let decoded = try CastWire.decode(Data(framed.dropFirst(4)))
    XCTAssertEqual(decoded.namespace, CastWire.receiver)
    XCTAssertEqual(decoded.json, json)
  }
  func testLargePayloadUsesMultibyteLengths() throws {
    let json = try JSONSerialization.data(withJSONObject: ["title": String(repeating: "Canzone è ", count: 1000)])
    let frame = try CastWire.frame(source: "test", destination: "transport-123", namespace: CastWire.media, json: json)
    XCTAssertEqual(try CastWire.decode(Data(frame.dropFirst(4))).json, json)
  }
  func testMalformedAndOversizedFramesAreRejected() {
    for bytes in [Data(), Data([18, 127, 1]), Data([255, 255, 255]), Data([13, 1, 2, 3, 4])] {
      XCTAssertThrowsError(try CastWire.decode(bytes))
    }
    XCTAssertThrowsError(try CastWire.decode(Data(repeating: 0, count: CastWire.limit + 1)))
    XCTAssertThrowsError(try CastWire.frame(source: "test", destination: "test", namespace: "test", json: Data(repeating: 0, count: CastWire.limit)))
  }
  func testControlConnectionsAreLimitedToLANAddresses() {
    for address in ["192.168.1.20", "10.0.0.2", "172.16.1.5", "172.31.2.4", "169.254.10.20", "fd12::1", "fe80::1"] {
      XCTAssertTrue(CastWire.localAddress(address), address)
    }
    for address in ["8.8.8.8", "127.0.0.1", "0.0.0.0", "172.32.1.2", "https://192.168.1.20", "example.com", "192.168.1.20.evil.test", "192.168.1.999", "::1"] {
      XCTAssertFalse(CastWire.localAddress(address), address)
    }
  }
  func testAttributesRoundTripDoesNotContainAccountOrAudioCredentials() throws {
    let value = CastRemoteState(id: "session", receiverSession: "receiver", host: "192.168.1.20", port: 8009,
      certificate: Data(repeating: 1, count: 32), deviceName: "Salotto", trackID: "song",
      title: "Canzone", artist: "Artista", artwork: URL(string: "https://i.ytimg.com/vi/song/default.jpg"),
      duration: 240, position: 60, timestamp: Date(timeIntervalSince1970: 1234), playback: "PLAYING", volume: 0.5)
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(CastRemoteState.self, from: data), value)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    for secret in ["cookie", "sapisid", "googlevideo", "apiKey", "audio.m4a"] { XCTAssertFalse(json.contains(secret)) }
  }
  func testRemoteCommandsRequireAnExistingCertificatePin() async {
    let state = CastRemoteState(id: "session", receiverSession: "receiver", host: "192.168.1.20", port: 8009,
      certificate: Data(), deviceName: "Salotto", trackID: "song", title: "Canzone", artist: "Artista", artwork: nil,
      duration: 240, position: 60, timestamp: Date(), playback: "PLAYING", volume: 0.5)
    let channel = CastDeviceChannel(host: state.host, port: state.port, pin: nil)
    do {
      _ = try await channel.perform("PLAY", state: state)
      XCTFail("An unpinned control connection must never be opened")
    } catch CastRemoteError.invalidDevice {} catch { XCTFail("Unexpected failure: \(error)") }
  }
}

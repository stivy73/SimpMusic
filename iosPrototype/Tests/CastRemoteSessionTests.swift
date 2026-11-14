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
    for address in ["192.168.1.20", "10.0.0.2", "172.16.1.5", "172.31.2.4", "169.254.10.20", "fd12::1", "fe80::1", "FD12::A", "FE80::A"] {
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

  func testPauseUsesStatusQueryWhenReceiverOnlyBroadcastsItsNewState() async throws {
    let receiver = CastReceiverTranscript()
    let channel = channel(receiver)
    let next = try await channel.perform("PAUSE", state: remoteState())
    XCTAssertEqual(next.playback, "PAUSED")
    let commands = await receiver.mediaCommands
    XCTAssertEqual(commands, ["GET_STATUS", "PAUSE", "GET_STATUS"])
    let closed = await receiver.closed
    XCTAssertTrue(closed)
  }

  func testCurrentMediaSessionDoesNotRequireCustomMetadataToBeEchoed() async throws {
    let receiver = CastReceiverTranscript(omitMetadata: true)
    let next = try await channel(receiver).perform("PAUSE", state: remoteState())
    XCTAssertEqual(next.playback, "PAUSED")
  }

  func testCommandCannotPauseAReplacedMediaSession() async throws {
    let receiver = CastReceiverTranscript(mediaID: 99)
    do {
      _ = try await channel(receiver).perform("PAUSE", state: remoteState())
      XCTFail("Must not pause another sender's media")
    } catch CastRemoteError.changedSession {}
    let commands = await receiver.mediaCommands
    XCTAssertEqual(commands, ["GET_STATUS"])
    let closed = await receiver.closed
    XCTAssertTrue(closed)
  }

  func testIgnoredPauseIsNotReportedAsSuccessOrRepeated() async throws {
    let receiver = CastReceiverTranscript(ignorePause: true)
    do {
      _ = try await channel(receiver).perform("PAUSE", state: remoteState())
      XCTFail("A written command is not proof of paused playback")
    } catch CastRemoteError.notConfirmed {}
    let commands = await receiver.mediaCommands
    XCTAssertEqual(commands.filter { $0 == "PAUSE" }.count, 1)
    XCTAssertEqual(commands.filter { $0 == "GET_STATUS" }.count, 4)
  }

  func testChangedReceiverCertificatePreventsAllCommands() async throws {
    let receiver = CastReceiverTranscript(certificate: Data(repeating: 9, count: 32))
    do {
      _ = try await channel(receiver).perform("PAUSE", state: remoteState())
      XCTFail("The receiver certificate must match the selected device")
    } catch CastRemoteError.invalidDevice {}
    let commands = await receiver.mediaCommands
    XCTAssertTrue(commands.isEmpty)
  }

  func testPlayAndSeekAreConfirmedWithoutDirectCommandReplies() async throws {
    let receiver = CastReceiverTranscript()
    let paused = try await channel(receiver).perform("PAUSE", state: remoteState())
    let playing = try await channel(receiver).perform("PLAY", state: paused)
    XCTAssertEqual(playing.playback, "PLAYING")
    let sought = try await channel(receiver).perform("SEEK", value: 75, state: playing)
    XCTAssertEqual(sought.position, 75)
  }

  private func channel(_ receiver: CastReceiverTranscript) -> CastDeviceChannel {
    CastDeviceChannel(host: "192.168.1.20", port: 8009, pin: Data(repeating: 1, count: 32), connection: receiver)
  }
  private func remoteState() -> CastRemoteState {
    CastRemoteState(id: "session", receiverSession: "receiver", host: "192.168.1.20", port: 8009,
      certificate: Data(repeating: 1, count: 32), deviceName: "Test", trackID: "song", title: "Song",
      artist: "Artist", artwork: nil, duration: 240, position: 60, timestamp: Date(), playback: "PLAYING",
      volume: 0.5, mediaSessionID: 42)
  }
}

/// Cast protocol scenario: media commands broadcast status with requestId 0,
/// GET_STATUS responds with its requestId, and heartbeat frames may interleave.
private actor CastReceiverTranscript: CastByteConnection {
  private var bytes = Data()
  private let omitMetadata: Bool
  private let mediaID: Int
  private let ignorePause: Bool
  private let certificate: Data
  private var playback = "PLAYING"
  private var position = 60.0
  private(set) var mediaCommands: [String] = []
  private(set) var closed = false
  init(omitMetadata: Bool = false, mediaID: Int = 42, ignorePause: Bool = false,
    certificate: Data = Data(repeating: 1, count: 32)) {
    self.omitMetadata = omitMetadata; self.mediaID = mediaID; self.ignorePause = ignorePause
    self.certificate = certificate
  }
  func open(host: String, port: UInt16, pin: Data?) async throws -> Data {
    closed = false; return certificate
  }
  func close() { closed = true }
  func read(_ count: Int) async throws -> Data {
    guard bytes.count >= count else { throw CastRemoteError.disconnected }
    let result = Data(bytes.prefix(count)); bytes.removeFirst(count); return result
  }
  func write(_ frame: Data) async throws {
    let message = try CastWire.decode(Data(frame.dropFirst(4)))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: message.json) as? [String: Any])
    let type = json["type"] as? String ?? ""
    let id = json["requestId"] as? Int ?? 0
    if message.namespace == CastWire.receiver, type == "GET_STATUS" {
      try enqueue(CastWire.receiver, ["requestId": id, "type": "RECEIVER_STATUS", "status": [
        "applications": [["appId": "CC1AD845", "sessionId": "receiver", "transportId": "receiver-transport"]]]])
    } else if message.namespace == CastWire.media {
      mediaCommands.append(type)
      if type == "PAUSE", !ignorePause { playback = "PAUSED" }
      if type == "PLAY" { playback = "PLAYING" }
      if type == "SEEK" { position = json["currentTime"] as? Double ?? position }
      if type != "GET_STATUS" { try enqueue(CastWire.heartbeat, ["type": "PING"]) }
      var status: [String: Any] = ["mediaSessionId": mediaID, "playerState": playback, "currentTime": position]
      if !omitMetadata { status["media"] = ["metadata": ["notenarrateTrackID": "song"]] }
      try enqueue(CastWire.media, ["type": "MEDIA_STATUS", "requestId": type == "GET_STATUS" ? id : 0, "status": [status]])
    }
  }
  private func enqueue(_ namespace: String, _ json: [String: Any]) throws {
    bytes.append(try CastWire.frame(source: "receiver-0", destination: "test", namespace: namespace,
      json: JSONSerialization.data(withJSONObject: json)))
  }
}

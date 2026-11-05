import Network
import XCTest

@testable import PrototypeCore

/// Real TLS sockets on loopback. Physical peer-to-peer Wi-Fi/CarPlay remain a separate device check.
final class PassengerTransportTests: XCTestCase {
  @MainActor private func eventually(_ predicate: () -> Bool, timeout: Double = 12) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
      if predicate() { return true }
      try? await Task.sleep(for: .milliseconds(40))
    }
    return predicate()
  }
  @MainActor private func connect(
    _ host: PassengerLink, _ guest: PassengerLink, wrongCode: Bool = false
  ) async throws {
    host.startHosting()
    let listening = await eventually { host.listeningPort != nil }
    XCTAssertTrue(listening, host.error ?? "Listener unavailable")
    let invitation = try XCTUnwrap(host.invitation)
    let port = try XCTUnwrap(host.listeningPort)
    let invite =
      wrongCode
      ? try PassengerInvitation(sessionID: invitation.sessionID, code: PassengerInvitation().code)
      : invitation
    guest.connect(invitation: invite, endpoint: .hostPort(host: .ipv4(.loopback), port: port))
  }
  @MainActor func testTLSRequiresApprovalThenReceiptsQueueAndHostState() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    var received: [PassengerSelection] = []
    host.onSelection = { request in
      received.append(request)
      return .init(requestID: request.id, success: true, message: "Aggiunto")
    }
    try await connect(host, guest)
    let discovered = await eventually { host.peers.count == 1 }
    XCTAssertTrue(discovered)
    XCTAssertFalse(guest.canSend)
    guest.submit(action: .playNow, tracks: [.init(id: "abcdefghijk", title: "T", artist: "A")])
    XCTAssertTrue(received.isEmpty)
    host.approve(try XCTUnwrap(host.peers.first?.id))
    let approved = await eventually { guest.canSend }
    XCTAssertTrue(approved, guest.error ?? "Not approved")
    guest.submit(action: .enqueue, tracks: [.init(id: "abcdefghijk", title: "T", artist: "A")])
    let acknowledged = await eventually { guest.receipt?.success == true }
    XCTAssertTrue(acknowledged, guest.error ?? "No receipt")
    XCTAssertEqual(received.count, 1)
    XCTAssertEqual(received.first?.action, .enqueue)
    host.publish(.init(title: "Nell’auto", artist: "Artista", playing: true, queueCount: 50))
    let published = await eventually { guest.playback.queueCount == 50 }
    XCTAssertTrue(published)
    host.remove(try XCTUnwrap(host.peers.first?.id))
    let removed = await eventually { guest.mode == .idle }
    XCTAssertTrue(removed)
    guest.submit(action: .playNow, tracks: [.init(id: "abcdefghijk", title: "T", artist: "A")])
    XCTAssertEqual(received.count, 1)
  }
  @MainActor func testWrongInvitationCannotAuthenticate() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    try await connect(host, guest, wrongCode: true)
    let rejected = await eventually { guest.mode == .idle && guest.error != nil }
    XCTAssertTrue(rejected)
    XCTAssertTrue(host.peers.isEmpty)
  }
  @MainActor func testRepeatedWireRequestIsAcknowledgedWithoutExecutingTwice() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    var calls = 0
    host.onSelection = { request in
      calls += 1
      return .init(requestID: request.id, success: true, message: "OK")
    }
    try await connect(host, guest)
    let joined = await eventually { !host.peers.isEmpty }
    XCTAssertTrue(joined)
    let hostPeer = try XCTUnwrap(host.peers.first?.id)
    host.approve(hostPeer)
    let approved = await eventually { guest.canSend }
    XCTAssertTrue(approved)
    // Obtain the single guest connection ID through the host-independent connection accessor.
    let id = try XCTUnwrap(guest.connectionID)
    let request = PassengerSelection(
      sessionID: try XCTUnwrap(host.invitation?.sessionID), action: .playNow,
      tracks: [.init(id: "abcdefghijk", title: "T", artist: "A")])
    guest.send(.selection(request), to: id)
    let first = await eventually { calls == 1 }
    XCTAssertTrue(first)
    guest.send(.selection(request), to: id)
    try? await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(calls, 1)
    // Replaying a foreign session ID never reaches the music callback.
    let foreign = PassengerSelection(sessionID: UUID(), action: .playNow, tracks: request.tracks)
    guest.send(.selection(foreign), to: id)
    let rejected = await eventually { guest.mode == .idle }
    XCTAssertTrue(rejected)
    XCTAssertEqual(calls, 1)
  }
  @MainActor func testHostStopInvalidatesInvitationAndDisconnectsAllGuests() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    try await connect(host, guest)
    let joined = await eventually { !host.peers.isEmpty }
    XCTAssertTrue(joined)
    host.approve(try XCTUnwrap(host.peers.first?.id))
    let approved = await eventually { guest.canSend }
    XCTAssertTrue(approved)
    let old = host.invitation
    host.stop()
    let stopped = await eventually { guest.mode == .idle }
    XCTAssertTrue(stopped)
    host.startHosting()
    XCTAssertNotEqual(host.invitation, old)
    XCTAssertTrue(host.peers.isEmpty)
  }
}

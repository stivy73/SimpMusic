import Network
import XCTest

@testable import PrototypeCore

/// Real TLS sockets on loopback. Physical peer-to-peer Wi-Fi/CarPlay remain a separate device check.
final class PassengerTransportTests: XCTestCase {
  @MainActor func testListenerRecoveryKeepsQRAndReconnectsWithoutRestartingSession() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    try await connect(host, guest)
    let joined = await eventually { host.peers.count == 1 }
    XCTAssertTrue(joined)
    host.approve(try XCTUnwrap(host.peers.first?.id))
    let connected = await eventually { guest.canSend }
    XCTAssertTrue(connected)
    let invite = try XCTUnwrap(host.invitation)
    host.resumeHosting(force: true)
    let listening = await eventually { host.listeningPort != nil }
    XCTAssertTrue(listening)
    XCTAssertEqual(host.invitation, invite)
    host.publish(.init(title: "Dopo ripristino", queueCount: 17))
    let stillConnected = await eventually { guest.playback.queueCount == 17 }
    XCTAssertTrue(stillConnected, "Listener restart must preserve established TCP connections")
    guest.stop()
    let removed = await eventually { host.peers.isEmpty }
    XCTAssertTrue(removed)
    guest.connect(
      invitation: invite,
      endpoint: .hostPort(host: .ipv4(.loopback), port: try XCTUnwrap(host.listeningPort)))
    let rejoined = await eventually { host.peers.count == 1 }
    XCTAssertTrue(rejoined)
    XCTAssertFalse(guest.canSend)
    host.approve(try XCTUnwrap(host.peers.first?.id))
    let reapproved = await eventually { guest.canSend }
    XCTAssertTrue(reapproved)
  }

  @MainActor func testSameQRCanBeScannedAgainAfterDisconnectUsingBonjour() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    host.startHosting()
    let listening = await eventually { host.listeningPort != nil }
    XCTAssertTrue(listening)
    let qr = try XCTUnwrap(host.invitation).text
    for _ in 0..<2 {
      guest.join(text: qr, name: "Passeggero")
      let joined = await eventually({ host.peers.count == 1 }, timeout: 20)
      XCTAssertTrue(joined, guest.error ?? "Bonjour discovery failed")
      host.approve(try XCTUnwrap(host.peers.first?.id))
      let connected = await eventually { guest.canSend }
      XCTAssertTrue(connected)
      host.remove(try XCTUnwrap(host.peers.first?.id))
      let disconnected = await eventually { guest.mode == .idle }
      XCTAssertTrue(disconnected)
      let removed = await eventually { host.peers.isEmpty }
      XCTAssertTrue(removed)
      host.resumeHosting(force: true)
      let recovered = await eventually { host.listeningPort != nil }
      XCTAssertTrue(recovered)
      XCTAssertEqual(host.invitation?.text, qr)
    }
  }
  @MainActor func testQRDiscoversBonjourServiceAfterAutomaticNameSuffix() async throws {
    let host = PassengerLink()
    let guest = PassengerLink()
    defer {
      host.stop()
      guest.stop()
    }
    host.serviceNameOverride = { $0.serviceName + " (2)" }
    host.startHosting()
    let ready = await eventually { host.listeningPort != nil }
    XCTAssertTrue(ready)
    guest.join(text: try XCTUnwrap(host.invitation).text, name: "Passeggero")
    let found = await eventually({ host.peers.count == 1 }, timeout: 12)
    XCTAssertTrue(
      found, "QR must identify the same TLS session even after Bonjour renames its advertisement")
    if found {
      host.approve(try XCTUnwrap(host.peers.first?.id))
      let connected = await eventually { guest.canSend }
      XCTAssertTrue(connected)
    }
  }

  @MainActor func testConnectionDiagnosticsDoNotContainInvitationSecretsOrMusic() {
    let host = PassengerLink()
    defer { host.stop() }
    host.startHosting()
    host.publish(.init(title: "Private song title", artist: "Private artist"))
    let report = host.diagnosticReport
    XCTAssertFalse(report.contains(host.invitation!.code))
    XCTAssertFalse(report.contains(host.invitation!.text))
    XCTAssertFalse(report.contains("Private song title"))
    XCTAssertFalse(report.contains("Private artist"))
    XCTAssertTrue(report.contains("apertura sessione"))
  }

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

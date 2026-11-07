import Foundation
import XCTest

@testable import PrototypeCore

final class PassengerBluetoothTests: XCTestCase {
  private func pair(_ invite: PassengerInvitation = PassengerInvitation()) throws
    -> (PassengerBluetoothChannel, PassengerBluetoothChannel)
  {
    let host = PassengerBluetoothChannel(invitation: invite, role: .host)
    let guest = PassengerBluetoothChannel(invitation: invite, role: .guest)
    XCTAssertNil(try guest.start())
    let proof = try guest.receive(XCTUnwrap(host.start()))
    XCTAssertFalse(proof.ready)
    let confirmation = try host.receive(XCTUnwrap(proof.response))
    XCTAssertTrue(confirmation.ready)
    XCTAssertTrue(try guest.receive(XCTUnwrap(confirmation.response)).ready)
    return (host, guest)
  }

  func testMutualAuthenticationEncryptsInBothDirectionsAndHidesMetadata() throws {
    let (host, guest) = try pair()
    let message = try PassengerMessage(.hello("Private passenger name")).encoded()
    let encrypted = try guest.seal(message)
    XCTAssertNil(encrypted.range(of: Data("Private passenger name".utf8)))
    XCTAssertEqual(try host.receive(encrypted).payload, message)
    let approved = try PassengerMessage(.approved).encoded()
    let reply = try host.seal(approved)
    XCTAssertEqual(try guest.receive(reply).payload, approved)
    XCTAssertThrowsError(try host.receive(reply), "Reflection must fail with directional keys")
  }

  func testWrongQRAndDifferentSessionCannotAuthenticate() throws {
    let invite = PassengerInvitation()
    for wrong in [
      try PassengerInvitation(sessionID: invite.sessionID, code: PassengerInvitation().code),
      PassengerInvitation(),
    ] {
      let host = PassengerBluetoothChannel(invitation: invite, role: .host)
      let guest = PassengerBluetoothChannel(invitation: wrong, role: .guest)
      _ = try guest.start()
      let proof = try guest.receive(XCTUnwrap(host.start()))
      XCTAssertThrowsError(try host.receive(XCTUnwrap(proof.response)))
    }
  }

  func testReplayedHandshakeCannotAuthenticateANewConnection() throws {
    let invite = PassengerInvitation()
    let first = PassengerBluetoothChannel(invitation: invite, role: .host)
    let guest = PassengerBluetoothChannel(invitation: invite, role: .guest)
    _ = try guest.start()
    let oldProof = try guest.receive(XCTUnwrap(first.start())).response
    let second = PassengerBluetoothChannel(invitation: invite, role: .host)
    _ = try second.start()
    XCTAssertThrowsError(try second.receive(XCTUnwrap(oldProof)))
  }

  func testReplaysAlteredPacketsAndSkippedCountersAreRejected() throws {
    let (host, guest) = try pair()
    let first = try guest.seal(Data("first".utf8))
    let second = try guest.seal(Data("second".utf8))
    XCTAssertThrowsError(try host.receive(second))
    var tampered = first
    tampered[tampered.count - 1] ^= 1
    XCTAssertThrowsError(try host.receive(tampered))
    XCTAssertEqual(try host.receive(first).payload, Data("first".utf8))
    XCTAssertThrowsError(try host.receive(first))
    XCTAssertEqual(try host.receive(second).payload, Data("second".utf8))
  }

  func testSameQRUsesFreshEncryptionForEveryConnection() throws {
    let invite = PassengerInvitation()
    let (_, guest1) = try pair(invite)
    let (host2, guest2) = try pair(invite)
    let old = try guest1.seal(Data("selection".utf8))
    let fresh = try guest2.seal(Data("selection".utf8))
    XCTAssertNotEqual(old, fresh)
    XCTAssertThrowsError(try host2.receive(old))
    XCTAssertEqual(try host2.receive(fresh).payload, Data("selection".utf8))
  }

  func testUnauthenticatedOversizedAndMalformedMessagesAreRejected() throws {
    let unready = PassengerBluetoothChannel(invitation: PassengerInvitation(), role: .guest)
    XCTAssertThrowsError(try unready.seal(Data([1])))
    _ = try unready.start()
    XCTAssertThrowsError(try unready.receive(Data([2, 1])))
    XCTAssertThrowsError(try unready.receive(Data([1, 1, 0])))
    let (_, ready) = try pair()
    XCTAssertThrowsError(try ready.seal(Data()))
    XCTAssertThrowsError(try ready.seal(Data(count: PassengerBluetoothChannel.maximumPayload + 1)))
  }

  func testBLEFragmentationAndBackpressurePreserve500TrackSelection() throws {
    let invite = PassengerInvitation()
    let (host, guest) = try pair(invite)
    let tracks = (0..<500).map {
      PassengerTrack(id: "abcdefghijk", title: "Brano \($0)", artist: "Artista")
    }
    let selection = PassengerSelection(
      sessionID: invite.sessionID, action: .enqueue, tracks: tracks)
    let frame = try PassengerMessage(.selection(selection)).encoded()
    let packet = try PassengerFrameBuffer.encode(guest.seal(frame))
    var queue = PassengerBluetoothQueue()
    try queue.append(packet)
    var radioBuffer = PassengerFrameBuffer()
    var decrypted = Data()
    // The minimum BLE payload (20 bytes) with a retry before each successful write.
    while let chunk = queue.next(maximum: 20) {
      XCTAssertEqual(queue.next(maximum: 20), chunk)
      for incoming in try radioBuffer.append(chunk) {
        decrypted = try XCTUnwrap(host.receive(incoming).payload)
      }
      queue.consume(chunk.count)
    }
    XCTAssertEqual(queue.count, 0)
    XCTAssertEqual(decrypted, frame)
    var applicationBuffer = PassengerFrameBuffer()
    let applicationFrames = try applicationBuffer.append(decrypted)
    guard
      case .selection(let received) = try PassengerMessage.decode(
        XCTUnwrap(applicationFrames.first)
      ).body
    else {
      return XCTFail("Selection must survive encryption and BLE fragmentation")
    }
    XCTAssertEqual(received.tracks.count, 500)
    XCTAssertEqual(received.id, selection.id)
    XCTAssertNoThrow(try received.validate(sessionID: invite.sessionID))
  }

  func testOutputQueueBoundsAndPacketBoundaries() throws {
    var queue = PassengerBluetoothQueue()
    try queue.append(Data([1, 2, 3]))
    try queue.append(Data([4, 5]))
    XCTAssertEqual(queue.next(maximum: 2), Data([1, 2]))
    queue.consume(2)
    XCTAssertEqual(queue.next(maximum: 2), Data([3]))
    queue.consume(1)
    XCTAssertEqual(queue.next(maximum: 20), Data([4, 5]))
    queue.consume(2)
    XCTAssertNil(queue.next(maximum: 20))
    try queue.append(Data(count: PassengerBluetoothQueue.maximum))
    XCTAssertThrowsError(try queue.append(Data([1])))
  }

  @MainActor func testNoBonjourFallbackRequiresApprovalAndReconnectsWithSameQR() async throws {
    let bus = BluetoothTestBus()
    let host = PassengerLink()
    let guest = PassengerLink()
    host.bluetoothFactory = { BluetoothTestTransport(bus: bus) }
    guest.bluetoothFactory = { BluetoothTestTransport(bus: bus) }
    guest.bluetoothFallbackDelay = 0
    // The browser cannot recognize this service, as in the reported car-network failure.
    host.serviceNameOverride = { _ in "Not a discoverable NoteNarrate service" }
    defer {
      host.stop()
      guest.stop()
    }
    var applied = 0
    host.onSelection = { request in
      applied += 1
      return .init(requestID: request.id, success: true, message: "OK")
    }
    host.startHosting()
    let qr = try XCTUnwrap(host.invitation).text
    for _ in 0..<2 {
      guest.join(text: qr, name: "Tommy")
      let joined = await eventually { host.peers.count == 1 }
      XCTAssertTrue(joined)
      XCTAssertFalse(guest.canSend)
      guest.submit(action: .playNow, tracks: [.init(id: "abcdefghijk", title: "T", artist: "A")])
      XCTAssertEqual(applied, 0)
      host.approve(try XCTUnwrap(host.peers.first?.id))
      let approved = await eventually { guest.canSend }
      XCTAssertTrue(approved)
      host.activateForCarPlay()
      XCTAssertTrue(guest.canSend, "Wi-Fi listener restart must not cancel Bluetooth")
      host.publish(.init(title: "Current", playing: true, queueCount: 50))
      XCTAssertEqual(guest.playback.queueCount, 50)
      host.remove(try XCTUnwrap(host.peers.first?.id))
      XCTAssertEqual(guest.mode, .idle)
      XCTAssertTrue(host.peers.isEmpty)
      XCTAssertEqual(host.invitation?.text, qr)
    }
    guest.join(text: qr, name: "Tommy")
    let joined = await eventually { host.peers.count == 1 }
    XCTAssertTrue(joined)
    host.approve(try XCTUnwrap(host.peers.first?.id))
    guest.submit(action: .enqueue, tracks: [.init(id: "abcdefghijk", title: "T", artist: "A")])
    XCTAssertEqual(applied, 1)
    XCTAssertEqual(guest.receipt?.success, true)
    XCTAssertFalse(guest.diagnosticReport.contains("Tommy"))
    XCTAssertFalse(host.diagnosticReport.contains(try XCTUnwrap(host.invitation?.code)))
  }

  @MainActor private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<100 {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
  }

  @MainActor func testWiFiConnectionCancelsDelayedBluetoothSearch() async throws {
    let bus = BluetoothTestBus()
    let host = PassengerLink()
    let guest = PassengerLink()
    host.bluetoothFactory = { BluetoothTestTransport(bus: bus) }
    guest.bluetoothFactory = { BluetoothTestTransport(bus: bus) }
    guest.bluetoothFallbackDelay = 0.1
    defer {
      host.stop()
      guest.stop()
    }
    host.startHosting()
    let listening = await eventually { host.listeningPort != nil }
    XCTAssertTrue(listening)
    let invite = try XCTUnwrap(host.invitation)
    guest.join(text: invite.text, name: "Guest")
    guest.connect(
      invitation: invite,
      endpoint: .hostPort(host: .ipv4(.loopback), port: try XCTUnwrap(host.listeningPort)))
    let joined = await eventually { host.peers.count == 1 }
    XCTAssertTrue(joined)
    host.approve(try XCTUnwrap(host.peers.first?.id))
    let approved = await eventually { guest.canSend }
    XCTAssertTrue(approved)
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(bus.joinAttempts, 0)
    XCTAssertEqual(host.peers.count, 1)
    XCTAssertTrue(guest.status.contains("Wi-Fi"))
  }
}

/// Tests the production PassengerLink routing and real crypto with a deterministic radio
/// adapter. This does not claim to test the Core Bluetooth driver or physical CarPlay.
@MainActor private final class BluetoothTestBus {
  var hosts: [UUID: BluetoothTestTransport] = [:]
  var joinAttempts = 0
  struct Pair {
    var host: BluetoothTestTransport
    var guest: BluetoothTestTransport
    var hostChannel: PassengerBluetoothChannel
    var guestChannel: PassengerBluetoothChannel
  }
  var pairs: [UUID: Pair] = [:]
}

@MainActor private final class BluetoothTestTransport: PassengerBluetoothTransport {
  var onReady: ((UUID) -> Bool)?
  var onData: ((UUID, Data) -> Void)?
  var onClose: ((UUID) -> Void)?
  var onDiagnostic: ((String) -> Void)?
  let bus: BluetoothTestBus
  var invitation: PassengerInvitation?
  init(bus: BluetoothTestBus) { self.bus = bus }
  func host(_ invite: PassengerInvitation) {
    invitation = invite
    bus.hosts[invite.sessionID] = self
  }
  func join(_ invite: PassengerInvitation) {
    bus.joinAttempts += 1
    guard let host = bus.hosts[invite.sessionID], let hostInvite = host.invitation else { return }
    do {
      let id = UUID()
      let h = PassengerBluetoothChannel(invitation: hostInvite, role: .host)
      let g = PassengerBluetoothChannel(invitation: invite, role: .guest)
      _ = try g.start()
      let proof = try g.receive(XCTUnwrap(h.start()))
      let confirmation = try h.receive(XCTUnwrap(proof.response))
      _ = try g.receive(XCTUnwrap(confirmation.response))
      bus.pairs[id] = .init(host: host, guest: self, hostChannel: h, guestChannel: g)
      guard host.onReady?(id) == true, onReady?(id) == true else {
        close(id)
        return
      }
    } catch { onDiagnostic?("Bluetooth: invito non valido") }
  }
  func send(_ data: Data, to id: UUID) -> Bool {
    guard let pair = bus.pairs[id] else { return false }
    do {
      if pair.host === self {
        let event = try pair.guestChannel.receive(pair.hostChannel.seal(data))
        if let payload = event.payload { pair.guest.onData?(id, payload) }
      } else {
        let event = try pair.hostChannel.receive(pair.guestChannel.seal(data))
        if let payload = event.payload { pair.host.onData?(id, payload) }
      }
      return true
    } catch {
      close(id)
      return false
    }
  }
  func close(_ id: UUID) {
    guard let pair = bus.pairs.removeValue(forKey: id) else { return }
    pair.host.onClose?(id)
    pair.guest.onClose?(id)
  }
  func stop() {
    for id in Array(bus.pairs.keys) {
      if bus.pairs[id]?.host === self || bus.pairs[id]?.guest === self { close(id) }
    }
    if let invitation, bus.hosts[invitation.sessionID] === self {
      bus.hosts.removeValue(forKey: invitation.sessionID)
    }
    invitation = nil
  }
}

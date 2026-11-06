import CryptoKit
import Foundation

/// The QR authenticates both ends independently of Bluetooth pairing. A fresh challenge from
/// each end derives new directional keys on every connection; AEAD counters reject replays.
/// Only encrypted PassengerMessage frames cross the radio after this handshake.
final class PassengerBluetoothChannel {
  enum Role { case host, guest }
  struct Event {
    var response: Data?
    var ready = false
    var payload: Data?
  }
  private enum Phase { case initial, challenge, proof, confirmation, ready }
  private let role: Role
  private let invitation: PassengerInvitation
  private var phase = Phase.initial
  private var hostNonce = Data()
  private var guestNonce = Data()
  private var sendKey: SymmetricKey?
  private var receiveKey: SymmetricKey?
  private var sent: UInt64 = 0
  private var received: UInt64 = 0
  static let maximumPayload = PassengerFrameBuffer.maximum - 128

  init(invitation: PassengerInvitation, role: Role) {
    self.invitation = invitation
    self.role = role
  }

  func start() throws -> Data? {
    guard phase == .initial else { throw PassengerError.malformed }
    if role == .guest {
      phase = .challenge
      return nil
    }
    hostNonce = Self.nonce()
    phase = .proof
    return Data([1, 1]) + hostNonce
  }

  func receive(_ packet: Data) throws -> Event {
    guard packet.count >= 2, packet[packet.startIndex] == 1 else {
      throw PassengerError.malformed
    }
    let kind = packet[packet.startIndex + 1]
    let body = Data(packet.dropFirst(2))
    switch (phase, kind) {
    case (.challenge, 1):
      guard body.count == 32 else { throw PassengerError.malformed }
      hostNonce = body
      guestNonce = Self.nonce()
      deriveKeys()
      phase = .confirmation
      return Event(response: Data([1, 2]) + guestNonce + proof("guest"))
    case (.proof, 2):
      guard body.count == 64 else { throw PassengerError.malformed }
      guestNonce = Data(body.prefix(32))
      guard validProof(Data(body.suffix(32)), label: "guest") else {
        throw PassengerError.notApproved
      }
      deriveKeys()
      phase = .ready
      return Event(response: Data([1, 3]) + proof("host"), ready: true)
    case (.confirmation, 3):
      guard body.count == 32, validProof(body, label: "host") else {
        throw PassengerError.notApproved
      }
      phase = .ready
      return Event(ready: true)
    case (.ready, 4):
      guard body.count >= 8 + 28, body.count <= Self.maximumPayload + 36,
        let receiveKey, received < UInt64.max
      else { throw PassengerError.malformed }
      let sequence = body.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
      guard sequence == received else { throw PassengerError.malformed }
      let direction = role == .host ? "guest" : "host"
      let sealed = try AES.GCM.SealedBox(combined: body.dropFirst(8))
      let plaintext = try AES.GCM.open(
        sealed, using: receiveKey, authenticating: context(direction) + Self.counter(sequence))
      guard !plaintext.isEmpty, plaintext.count <= Self.maximumPayload else {
        throw PassengerError.malformed
      }
      received += 1
      return Event(payload: plaintext)
    default: throw PassengerError.malformed
    }
  }

  func seal(_ data: Data) throws -> Data {
    guard phase == .ready, let sendKey, sent < UInt64.max,
      !data.isEmpty, data.count <= Self.maximumPayload
    else { throw PassengerError.malformed }
    let direction = role == .host ? "host" : "guest"
    // Directional keys are fresh per connection. No nonce is reused under a key.
    let nonce = try AES.GCM.Nonce(
      data: Data([0, 0, 0, role == .host ? 1 : 2]) + Self.counter(sent))
    let box = try AES.GCM.seal(
      data, using: sendKey, nonce: nonce,
      authenticating: context(direction) + Self.counter(sent))
    guard let combined = box.combined else { throw PassengerError.malformed }
    let packet = Data([1, 4]) + Self.counter(sent) + combined
    sent += 1
    return packet
  }

  private func context(_ label: String) -> Data {
    Data(("NoteNarrate.Passenger.BLE.v1:" + invitation.sessionID.uuidString + ":" + label).utf8)
  }
  private func proof(_ label: String) -> Data {
    Data(
      HMAC<SHA256>.authenticationCode(
        for: context(label) + hostNonce + guestNonce, using: SymmetricKey(data: invitation.key)))
  }
  private func validProof(_ data: Data, label: String) -> Bool {
    HMAC<SHA256>.isValidAuthenticationCode(
      data, authenticating: context(label) + hostNonce + guestNonce,
      using: SymmetricKey(data: invitation.key))
  }
  private func deriveKeys() {
    func key(_ label: String) -> SymmetricKey {
      HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: invitation.key), salt: hostNonce + guestNonce,
        info: context(label), outputByteCount: 32)
    }
    sendKey = key(role == .host ? "host" : "guest")
    receiveKey = key(role == .host ? "guest" : "host")
  }
  private static func nonce() -> Data {
    SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
  }
  private static func counter(_ value: UInt64) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
  }
}

import XCTest

@testable import PrototypeCore

final class PassengerSessionTests: XCTestCase {
  func testBonjourNamesAcceptOnlyUUIDAndNumericCollisionSuffix() {
    let invitation = PassengerInvitation()
    XCTAssertEqual(
      PassengerInvitation.advertisedSession(invitation.serviceName)?.id, invitation.sessionID)
    XCTAssertEqual(
      PassengerInvitation.advertisedSession(invitation.serviceName + " (2)")?.id,
      invitation.sessionID)
    for suffix in [" (x)", " garbage", " (2)evil", " (1234567)"] {
      XCTAssertNil(PassengerInvitation.advertisedSession(invitation.serviceName + suffix))
    }
  }
  private let track = PassengerTrack(id: "abcdefghijk", title: "Brano", artist: "Artista")
  func testInvitationRoundTripAndRotation() throws {
    let first = PassengerInvitation()
    let second = PassengerInvitation()
    XCTAssertEqual(try PassengerInvitation(text: first.text), first)
    XCTAssertEqual(
      try PassengerInvitation(sessionID: first.sessionID, code: first.displayCode.lowercased()),
      first)
    XCTAssertEqual(first.key.count, 32)
    XCTAssertNotEqual(first.code, second.code)
    XCTAssertFalse(first.serviceName.contains(first.code))
    for value in [
      "notenarrate://passenger/not-a-uuid#ABC", "https://example.com/#" + first.code,
      first.text + "?token=secret",
      "notenarrate://user@passenger/" + first.sessionID.uuidString + "#" + first.code,
    ] {
      XCTAssertThrowsError(try PassengerInvitation(text: value))
    }
  }
  func testSelectionRejectsCrossSessionStaleFutureAndForeignURLs() throws {
    let invitation = PassengerInvitation()
    var request = PassengerSelection(
      sessionID: invitation.sessionID, action: .playNow, tracks: [track])
    XCTAssertNoThrow(try request.validate(sessionID: invitation.sessionID))
    XCTAssertThrowsError(try request.validate(sessionID: UUID()))
    for seconds in [-91.0, 91.0] {
      request.created = Date().addingTimeInterval(seconds)
      XCTAssertThrowsError(try request.validate(sessionID: invitation.sessionID))
    }
    for badID in ["https://127.0.0.1/secrets", "..", "abc defghij", "あいうえおabcdef"] {
      let request = PassengerSelection(
        sessionID: invitation.sessionID, action: .enqueue,
        tracks: [.init(id: badID, title: "T", artist: "A")])
      XCTAssertThrowsError(try request.validate(sessionID: invitation.sessionID))
    }
  }
  func testLargeCollectionIsAtomicAndDoesNotSilentlyTruncate() throws {
    let id = UUID()
    for count in [0, 501] {
      let value = PassengerSelection(
        sessionID: id, action: .enqueue, tracks: Array(repeating: track, count: count))
      XCTAssertThrowsError(try value.validate(sessionID: id))
    }
    let unicode = PassengerTrack(
      id: track.id, title: String(repeating: "🎵", count: 200),
      artist: String(repeating: "語", count: 200))
    let value = PassengerSelection(
      sessionID: id, action: .enqueue, tracks: Array(repeating: unicode, count: 500))
    XCTAssertNoThrow(try value.validate(sessionID: id))
    let framed = try PassengerMessage(.selection(value)).encoded()
    XCTAssertLessThan(framed.count, PassengerFrameBuffer.maximum)
    var buffer = PassengerFrameBuffer()
    let messages = try buffer.append(framed)
    guard case .selection(let result) = try PassengerMessage.decode(XCTUnwrap(messages.first)).body
    else { return XCTFail() }
    XCTAssertEqual(result.tracks.count, 500)
    XCTAssertEqual(result.tracks.first?.title.count, 160)
  }
  func testFragmentedAndCoalescedTCPFrames() throws {
    let a = Data("uno".utf8)
    let b = Data("due".utf8)
    let bytes = try PassengerFrameBuffer.encode(a) + PassengerFrameBuffer.encode(b)
    var buffer = PassengerFrameBuffer()
    var received: [Data] = []
    for byte in bytes { received += try buffer.append(Data([byte])) }
    XCTAssertEqual(received, [a, b])
    var joined = PassengerFrameBuffer()
    XCTAssertEqual(try joined.append(bytes), [a, b])
  }
  func testOversizedZeroAndUnknownVersionAreRejected() throws {
    for bytes in [Data([255, 255, 255, 255]), Data([0, 0, 0, 0])] {
      var buffer = PassengerFrameBuffer()
      XCTAssertThrowsError(try buffer.append(bytes))
    }
    var value = PassengerMessage(.approved)
    value.version = 10
    XCTAssertThrowsError(try PassengerMessage.decode(JSONEncoder().encode(value)))
  }
  func testLedgerNeverEvictsActionableRequestsAndExpiresSafely() {
    var ledger = PassengerRequestLedger()
    let start = Date()
    let first = PassengerReceipt(requestID: UUID(), success: true, message: "OK")
    ledger.remember(first, now: start)
    for _ in 1..<2048 {
      ledger.remember(.init(requestID: UUID(), success: true, message: "OK"), now: start)
    }
    XCTAssertFalse(ledger.hasCapacity(now: start.addingTimeInterval(180)))
    XCTAssertEqual(ledger.reply(for: first.requestID), first)
    XCTAssertTrue(ledger.hasCapacity(now: start.addingTimeInterval(182)))
    XCTAssertNil(ledger.reply(for: first.requestID))
  }
}

import XCTest
@testable import PrototypeCore

final class CastVolumeControlTests: XCTestCase {
  func testFirstPressAdjustsReceiverRelativelyWithoutJumpingToPhoneVolume() {
    var control = CastVolumeControl()
    control.begin(phone: 0.75, receiver: 0.2)
    XCTAssertEqual(control.phoneChanged(to: 0.8125, now: 1)!, 0.2625, accuracy: 0.0001)
  }

  func testRapidPressesAccumulateWhileOldReceiverRepliesArrive() {
    var control = CastVolumeControl()
    control.begin(phone: 0.5, receiver: 0.2)
    _ = control.phoneChanged(to: 0.5625, now: 1)
    control.receive(0.2, now: 1.1)
    XCTAssertEqual(control.phoneChanged(to: 0.625, now: 1.2)!, 0.325, accuracy: 0.0001)
    control.receive(0.2625, now: 1.3)
    XCTAssertEqual(control.receiverVolume, 0.325, accuracy: 0.0001)
    control.receive(0.325, now: 1.4)
    control.receive(0.4, now: 1.5)
    XCTAssertEqual(control.receiverVolume, 0.4)
  }

  func testSliderChangeBecomesTheBaseForTheNextButtonPress() {
    var control = CastVolumeControl()
    control.begin(phone: 0.5, receiver: 0.2)
    _ = control.request(0.8, now: 1)
    XCTAssertEqual(control.phoneChanged(to: 0.4375, now: 1.1)!, 0.7375, accuracy: 0.0001)
    // No receiver response: show its actual level after the pending window.
    control.receive(0.5, now: 4)
    XCTAssertEqual(control.receiverVolume, 0.5)
  }

  func testDisconnectAndReconnectionDoNotReplayOldVolumeChanges() {
    var control = CastVolumeControl()
    XCTAssertNil(control.phoneChanged(to: 0.5, now: 1))
    control.begin(phone: 0.5, receiver: 0.2)
    control.end()
    XCTAssertNil(control.phoneChanged(to: 0.75, now: 2))
    XCTAssertNil(control.request(1, now: 2))
    control.begin(phone: 0.75, receiver: 0.4)
    XCTAssertNil(control.phoneChanged(to: 0.75, now: 3))
    XCTAssertEqual(control.phoneChanged(to: 0.8125, now: 4)!, 0.4625, accuracy: 0.0001)
  }

  func testLimitsAndLargePhoneChangesDoNotProduceVolumeJumps() {
    var control = CastVolumeControl()
    control.begin(phone: 0.95, receiver: 0.99)
    XCTAssertEqual(control.phoneChanged(to: 1, now: 1), 1)
    XCTAssertTrue(control.phoneAtLimit)
    XCTAssertNil(control.phoneChanged(to: 1, now: 2))
    control.begin(phone: 0.5, receiver: 0)
    XCTAssertNil(control.phoneChanged(to: 0.4375, now: 3))
    XCTAssertEqual(control.phoneChanged(to: 0.9, now: 4), 0.0625)
  }

  func testInvalidReadingsCannotChangeTheReceiver() {
    var control = CastVolumeControl()
    control.begin(phone: 0.5, receiver: 0.2)
    XCTAssertNil(control.phoneChanged(to: .nan, now: 1))
    XCTAssertNil(control.request(.infinity, now: 1))
    control.receive(.nan, now: 1)
    XCTAssertEqual(control.receiverVolume, 0.2)
    XCTAssertEqual(control.phoneVolume, 0.5)
  }
}

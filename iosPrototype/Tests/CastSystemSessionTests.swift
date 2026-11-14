import Foundation
import XCTest
@testable import PrototypeCore

@MainActor
final class CastSystemSessionTests: XCTestCase {
  func testBackgroundRegistrationDoesNotSuppressWorkingLegacyCard() async throws {
    let driver = Driver()
    let controller = CastSystemSessionController(driver: driver)
    try await controller.publish(state(), foreground: false, now: 100)
    XCTAssertTrue(controller.registered)
    XCTAssertFalse(controller.isPrimary)
    XCTAssertFalse(controller.suppressesLegacy)
    XCTAssertEqual(driver.started.first?.promotions, 0)
  }

  func testIdenticalStatePromotesImmediatelyWhenAppBecomesForeground() async throws {
    let driver = Driver()
    let controller = CastSystemSessionController(driver: driver)
    try await controller.publish(state(), foreground: false, now: 100)
    try await controller.publish(state(), foreground: true, now: 100.1)
    XCTAssertTrue(controller.isPrimary)
    XCTAssertEqual(driver.started.count, 1)
    XCTAssertEqual(driver.started.first?.promotions, 1)
  }

  func testLegacyClearsBeforePromotionAndIsNotClearedAfterSuccessfulHandoff() async throws {
    let driver = Driver(); var legacy = true; var events: [String] = []
    driver.onPromote = { XCTAssertFalse(legacy); events.append("promote") }
    let controller = CastSystemSessionController(driver: driver,
      beginHandoff: { legacy = false; events.append("clear") },
      finishHandoff: { success in if !success { legacy = true }; events.append("finish") })
    try await controller.publish(state(), foreground: true, now: 100)
    XCTAssertEqual(events, ["clear", "promote", "finish"])
    XCTAssertTrue(controller.suppressesLegacy)
    XCTAssertFalse(legacy)
  }

  func testFailedPromotionRestoresLegacyAndNeverClaimsSystemPrimary() async throws {
    let driver = Driver(); driver.failPromotion = true; var legacy = true
    let controller = CastSystemSessionController(driver: driver,
      beginHandoff: { legacy = false }, finishHandoff: { success in if !success { legacy = true } })
    try await controller.publish(state(), foreground: true, now: 100)
    XCTAssertTrue(legacy)
    XCTAssertTrue(controller.registered)
    XCTAssertFalse(controller.suppressesLegacy)
    XCTAssertNotNil(controller.lastError)
  }

  func testReturningFromPromotionWithoutFocusStillRestoresLegacy() async throws {
    let driver = Driver(); driver.acceptFocus = false; var legacy = true
    let controller = CastSystemSessionController(driver: driver,
      beginHandoff: { legacy = false }, finishHandoff: { success in if !success { legacy = true } })
    try await controller.publish(state(), foreground: true, now: 100)
    XCTAssertFalse(controller.isPrimary)
    XCTAssertTrue(legacy)
  }

  func testAppRestartAdoptsExistingMatchingSessionWithOpaqueHandleID() async throws {
    let driver = Driver()
    let foreign = Handle(id: "opaque-foreign", attributesID: "another-session")
    let existing = Handle(id: "opaque-existing", attributesID: "receiver")
    driver.existing = [foreign, existing]
    let controller = CastSystemSessionController(driver: driver)
    try await controller.publish(state(), foreground: true, now: 100)
    XCTAssertEqual(controller.sessionID, "opaque-existing")
    XCTAssertTrue(controller.isPrimary)
    XCTAssertEqual(driver.started.count, 0)
    XCTAssertEqual(foreign.updates, 0)
    XCTAssertEqual(foreign.ends, 0)
  }

  func testLostFocusAndExplicitRecoveryDoNotReloadOrRestartMediaSession() async throws {
    let driver = Driver()
    let controller = CastSystemSessionController(driver: driver)
    try await controller.publish(state(), foreground: true, now: 100)
    let handle = try XCTUnwrap(driver.started.first)
    handle.isPrimary = false
    XCTAssertFalse(controller.suppressesLegacy)
    try await controller.publish(state(), foreground: true, now: 103)
    XCTAssertTrue(controller.isPrimary)
    try await controller.publish(state(), foreground: true, forcePromotion: true, now: 103.1)
    XCTAssertEqual(driver.started.count, 1)
    XCTAssertEqual(handle.promotions, 3)
    XCTAssertEqual(handle.ends, 0)
  }

  func testInvalidCachedHandleReleasesFallbackAndCanRecover() async throws {
    let driver = Driver()
    let controller = CastSystemSessionController(driver: driver)
    try await controller.publish(state(), foreground: true, now: 100)
    let handle = try XCTUnwrap(driver.started.first)
    handle.failUpdate = true
    do {
      try await controller.publish(state(), foreground: true, now: 103)
      XCTFail("A failed update must release legacy suppression")
    } catch Failure.unavailable {}
    XCTAssertFalse(controller.suppressesLegacy)
    XCTAssertEqual(handle.ends, 1)
    try await controller.publish(state(), foreground: true, now: 104)
    XCTAssertTrue(controller.isPrimary)
    XCTAssertEqual(driver.started.count, 2)
    await controller.end()
    XCTAssertFalse(controller.registered)
    XCTAssertFalse(controller.suppressesLegacy)
    XCTAssertNil(controller.sessionID)
  }

  private func state() -> CastRemoteState {
    CastRemoteState(id: "receiver", receiverSession: "receiver", host: "192.168.1.20", port: 8009,
      certificate: Data(repeating: 1, count: 32), deviceName: "Test", trackID: "song", title: "Song",
      artist: "Artist", artwork: nil, duration: 240, position: 60,
      timestamp: Date(timeIntervalSince1970: 1000), playback: "PLAYING", volume: 0.5, mediaSessionID: 42)
  }

  private enum Failure: Error { case unavailable }
  private final class Driver: CastSystemSessionDriver {
    var existing: [Handle] = []
    var started: [Handle] = []
    var failPromotion = false
    var acceptFocus = true
    var onPromote: () -> Void = {}
    func sessions() async throws -> [any CastSystemSessionHandle] { existing + started }
    func start(_ state: CastRemoteState) async throws -> any CastSystemSessionHandle {
      let handle = Handle(id: UUID().uuidString, attributesID: state.id)
      handle.failPromotion = failPromotion; handle.acceptFocus = acceptFocus
      handle.onPromote = onPromote; started.append(handle); return handle
    }
  }
  private final class Handle: CastSystemSessionHandle {
    let id: String
    let attributesID: String
    var isPrimary = false
    var failPromotion = false
    var failUpdate = false
    var acceptFocus = true
    var onPromote: () -> Void = {}
    var promotions = 0; var updates = 0; var ends = 0
    init(id: String, attributesID: String) { self.id = id; self.attributesID = attributesID }
    func update(_ state: CastRemoteState) async throws {
      guard state.id == attributesID else { throw CastSystemSessionError.differentAttributes }
      guard !failUpdate, ends == 0 else { throw Failure.unavailable }
      updates += 1
    }
    func promote() async throws {
      promotions += 1; onPromote()
      if failPromotion { throw Failure.unavailable }
      isPrimary = acceptFocus
    }
    func end() async throws { ends += 1; isPrimary = false }
  }
}

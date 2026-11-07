import Foundation
import XCTest

@testable import PrototypeCore

final class AudioWarmupTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  private let network = UUID()
  private let accountRevision = UUID()
  private var session: YouTubeSession {
    YouTubeSession(
      cookies: "SAPISID=fixture", accountIndex: "1", delegatedID: "brand",
      identity: "account", clientVersion: "test")
  }
  private func context(
    session: YouTubeSession?, quality: AudioQuality = .high,
    network: UUID? = nil, accountRevision: UUID? = nil
  ) -> AudioWarmupContext {
    AudioWarmupContext(
      session: session, quality: quality, networkRevision: network ?? self.network,
      accountRevision: accountRevision ?? self.accountRevision)
  }
  private func usable(
    _ prepared: AudioWarmupContext, current: AudioWarmupContext? = nil,
    age: Double = 1, url: URL? = nil
  ) -> Bool {
    AudioWarmupValidity.usable(
      preparedAt: now.addingTimeInterval(-age), now: now, sourceURL: url,
      context: prepared, current: current ?? prepared)
  }

  func testCompleteSessionMustMatchIncludingCookiesAndAccountSelection() {
    let original = context(session: session)
    XCTAssertTrue(usable(original, current: context(session: session)))
    let changed = [
      YouTubeSession(cookies: "SAPISID=changed", accountIndex: "1", delegatedID: "brand", identity: "account", clientVersion: "test"),
      YouTubeSession(cookies: "SAPISID=fixture", accountIndex: "2", delegatedID: "brand", identity: "account", clientVersion: "test"),
      YouTubeSession(cookies: "SAPISID=fixture", accountIndex: "1", delegatedID: "other", identity: "account", clientVersion: "test"),
      YouTubeSession(cookies: "SAPISID=fixture", accountIndex: "1", delegatedID: nil, identity: "account", clientVersion: "test"),
      YouTubeSession(cookies: "SAPISID=fixture", accountIndex: "1", delegatedID: "brand", identity: "other", clientVersion: "test"),
      YouTubeSession(cookies: "SAPISID=fixture", accountIndex: "1", delegatedID: "brand", identity: "account", clientVersion: "new"),
    ]
    for value in changed { XCTAssertFalse(usable(original, current: context(session: value))) }
    XCTAssertFalse(usable(original, current: context(session: nil)))
    XCTAssertFalse(usable(context(session: nil), current: original))
    XCTAssertTrue(usable(context(session: nil)))
  }

  func testQualityNetworkAndAccountRevisionMustMatch() {
    let original = context(session: session)
    XCTAssertFalse(usable(original, current: context(session: session, quality: .normal)))
    XCTAssertFalse(usable(original, current: context(session: session, quality: .saver)))
    XCTAssertFalse(usable(original, current: context(session: session, network: UUID())))
    // Reauthentication to the same selected account still invalidates old preparation.
    XCTAssertFalse(usable(original, current: context(session: session, accountRevision: UUID())))
  }

  func testTTLIncludesBoundariesAndRejectsFutureOrNonfinitePreparation() {
    let original = context(session: session)
    XCTAssertTrue(usable(original, age: 0))
    XCTAssertTrue(usable(original, age: 120))
    XCTAssertFalse(usable(original, age: 120.001))
    XCTAssertFalse(usable(original, age: -0.001))
    XCTAssertFalse(usable(original, age: .infinity))
    XCTAssertFalse(usable(original, age: .nan))
  }

  func testSignedExpiryRequiresThirtySecondSafetyMargin() {
    let original = context(session: session)
    func url(_ expiry: String) -> URL {
      URL(string: "https://example.org/audio?expire=" + expiry)!
    }
    XCTAssertTrue(usable(original, url: url("2000000030")))
    XCTAssertTrue(usable(original, url: url("2000000060")))
    XCTAssertFalse(usable(original, url: url("2000000029.99")))
    XCTAssertFalse(usable(original, url: url("1999999999")))
    for invalid in ["", "unknown", "nan", "inf", "-inf"] {
      XCTAssertFalse(usable(original, url: url(invalid)))
    }
    XCTAssertFalse(usable(original, url: URL(string: "https://example.org/audio?expire=2000000060&expire=2000000090")))
    XCTAssertFalse(usable(original, age: 121, url: url("2000000900")))
  }

  func testLocalAndUnknownExpiryStillUseBoundedTTL() {
    let original = context(session: session)
    for url in [nil, URL(fileURLWithPath: "/tmp/fixture.m4a"), URL(string: "https://example.org/audio?signature=fixture")] {
      XCTAssertTrue(usable(original, age: 120, url: url))
      XCTAssertFalse(usable(original, age: 121, url: url))
    }
  }
}

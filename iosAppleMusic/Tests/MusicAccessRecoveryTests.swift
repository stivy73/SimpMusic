import XCTest
@testable import LyricsContract
private enum AccessFixtureError: Error { case developer, permission, refresh }
private actor AccessFixture {
  var operations = 0
  var renewals = 0
  func run(failure: AccessFixtureError, always: Bool = false) throws -> Int {
    operations += 1
    if always || operations == 1 { throw failure }
    return 7
  }
  func renew(fail: Bool = false) throws { renewals += 1; if fail { throw AccessFixtureError.refresh } }
  func counts() -> [Int] { [operations,renewals] }
}
final class MusicAccessRecoveryTests: XCTestCase {
  private func recovery(_ fixture: AccessFixture, failRefresh: Bool = false) -> MusicAccessRecovery {
    .init(isDeveloperTokenFailure:{ if case AccessFixtureError.developer = $0 { return true }; return false },
          renewDeveloperToken:{ try await fixture.renew(fail:failRefresh) })
  }
  func testDeveloperTokenFailureRefreshesAndRetries() async throws {
    let fixture = AccessFixture()
    let result = try await recovery(fixture).perform { try await fixture.run(failure:.developer) }
    XCTAssertEqual(result,7)
    let counts = await fixture.counts(); XCTAssertEqual(counts,[2,1])
  }
  func testPermissionFailureNeverRefreshes() async {
    let fixture = AccessFixture()
    do { _ = try await recovery(fixture).perform { try await fixture.run(failure:.permission) }; XCTFail() }
    catch { XCTAssertTrue(error is AccessFixtureError) }
    let counts = await fixture.counts(); XCTAssertEqual(counts,[1,0])
  }
  func testPersistentFailureStopsAfterOneRetry() async {
    let fixture = AccessFixture()
    do { _ = try await recovery(fixture).perform { try await fixture.run(failure:.developer,always:true) }; XCTFail() }
    catch { XCTAssertTrue(error is AccessFixtureError) }
    let counts = await fixture.counts(); XCTAssertEqual(counts,[2,1])
  }
  func testFailedRenewalDoesNotRepeatRequest() async {
    let fixture = AccessFixture()
    do { _ = try await recovery(fixture,failRefresh:true).perform { try await fixture.run(failure:.developer) }; XCTFail() }
    catch { XCTAssertTrue(error is AccessFixtureError) }
    let counts = await fixture.counts(); XCTAssertEqual(counts,[1,1])
  }
}

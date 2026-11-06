import XCTest
@testable import PrototypeCore

final class GeminiBillingErrorTests: XCTestCase {
  func testDepletedCreditsAreRecognizedWithoutRetainingProviderMessage() throws {
    let body = try JSONSerialization.data(withJSONObject: ["error": ["status": "RESOURCE_EXHAUSTED", "message": "Your prepayment credits are depleted. private-project-and-key"]])
    let error = GeminiAPIError(status: 429, body: body)
    XCTAssertTrue(error.creditExhausted)
    XCTAssertTrue(error.localizedDescription.contains("Credito API Gemini esaurito"))
    XCTAssertFalse(error.localizedDescription.contains("private-project-and-key"))
    XCTAssertFalse(error.diagnostic.contains("private-project-and-key"))
  }
  func testOrdinaryRateLimitDoesNotClaimFundsAreCertainlyExhausted() {
    let error = GeminiAPIError(status: 429, body: Data())
    XCTAssertFalse(error.creditExhausted)
    XCTAssertTrue(error.localizedDescription.contains("potrebbe"))
  }
  func testPaymentRequiredIsExplicitWithoutProviderBody() {
    let error = GeminiAPIError(status: 402, body: Data())
    XCTAssertTrue(error.creditExhausted)
    XCTAssertTrue(error.localizedDescription.contains("Credito API Gemini esaurito"))
  }
}

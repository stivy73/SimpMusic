import XCTest
@testable import LyricsContract
final class LicensedLyricsTests:XCTestCase {
  func document(id:String="song-1",text:String="Un testo autorizzato",expires:Date = .now.addingTimeInterval(300),uses:[String]=["aiInterpretation"])->LicensedLyricsDocument {
    .init(appleMusicID:id,text:text,provider:"Licensed provider fixture",copyright:"Copyright rights holder",sourceURL:URL(string:"https://example.org/license")!,expiresAt:expires,permittedUses:uses)
  }
  func testExplicitRightsAndMatchingTrackAccepted() throws { XCTAssertNoThrow(try document().validate(for:"song-1")) }
  func testExpiredOrUnlicensedOrWrongTrackRejected() {
    XCTAssertThrowsError(try document(expires:.distantPast).validate(for:"song-1"))
    XCTAssertThrowsError(try document(uses:["display"]).validate(for:"song-1"))
    XCTAssertThrowsError(try document(id:"other").validate(for:"song-1"))
    XCTAssertThrowsError(try document(text:" ").validate(for:"song-1"))
  }
  func testOversizedTextRejected() {
    XCTAssertThrowsError(try document(text:String(repeating:"x",count:100_001)).validate(for:"song-1"))
  }
  func testInsecureEndpointFailsBeforeNetwork() async {
    do { _ = try await LicensedLyricsService(endpoint:URL(string:"http://localhost/lyrics")).lyrics(id:"song-1",title:"Song",artist:"Artist");XCTFail("Expected invalid configuration") }
    catch { guard case LyricsServiceError.notConfigured = error else { return XCTFail("Unexpected error: \(error)") } }
  }
  func testMissingEndpointFailsWithoutSendingRequest() async {
    do { _ = try await LicensedLyricsService(endpoint:nil).lyrics(id:"song-1",title:"Song",artist:"Artist");XCTFail("Expected unavailable configuration") }
    catch { XCTAssertTrue(error is LyricsServiceError) }
  }
}

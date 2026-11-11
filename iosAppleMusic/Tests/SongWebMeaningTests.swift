import XCTest
@testable import LyricsContract

final class SongWebMeaningTests: XCTestCase {
    func fixture(uri: String = "https://example.org/intervista", supported: Bool = true, finish: String = "STOP") -> [String: Any] {
        ["candidates": [["finishReason": finish, "content": ["parts": [["text": "Parla di speranza."]]],
          "groundingMetadata": ["searchEntryPoint": ["renderedContent": "<div>Google</div>"],
            "groundingChunks": [["web": ["uri": uri, "title": "Intervista"]]],
            "groundingSupports": [["segment": ["text": supported ? "Parla di speranza." : "Altro"], "groundingChunkIndices": [0]]]]]]]
    }
    func testGroundedMeaningKeepsSourcesAndSuggestions() {
        let result = SongWebMeaning.parse(fixture())
        XCTAssertEqual(result.text, "Parla di speranza.")
        XCTAssertEqual(result.evidence?.sources.first?.passage, result.text)
        XCTAssertEqual(result.evidence?.suggestionsHTML, "<div>Google</div>")
    }
    func testMissingSourcesProducesSpokenFallback() {
        XCTAssertEqual(SongWebMeaning.parse([:]).text, SongWebMeaning.unavailable)
        XCTAssertNil(SongWebMeaning.parse(fixture(supported: false)).evidence)
        XCTAssertNil(SongWebMeaning.parse(fixture(finish: "MAX_TOKENS")).evidence)
    }
    func testUnsafeSourceURLsRejected() {
        for uri in ["http://example.org", "javascript:alert(1)", "https://user:secret@example.org", "https://example.org:8080"] {
            XCTAssertNil(SongWebMeaning.parse(fixture(uri: uri)).evidence)
        }
    }
    func testGoogleRedirectSourceAccepted() {
        XCTAssertNotNil(SongWebMeaning.parse(fixture(uri: "https://vertexaisearch.cloud.google.com/grounding-api-redirect/test")).evidence)
    }
    func testThoughtPartsAreNotNarrated() {
        var value = fixture()
        var candidates = value["candidates"] as! [[String: Any]]
        candidates[0]["content"] = ["parts": [["text":"Pensiero privato", "thought":true],["text":"Parla di speranza."]]]
        value["candidates"] = candidates
        XCTAssertEqual(SongWebMeaning.parse(value).text,"Parla di speranza.")
    }
    func testMissingSuggestionsOrRefusalIsNotAnInterpretation() {
        var value = fixture()
        var candidates = value["candidates"] as! [[String: Any]]
        var grounding = candidates[0]["groundingMetadata"] as! [String:Any]
        grounding.removeValue(forKey:"searchEntryPoint")
        candidates[0]["groundingMetadata"] = grounding
        value["candidates"] = candidates
        XCTAssertNil(SongWebMeaning.parse(value).evidence)
        candidates[0]["content"] = ["parts":[["text":"FONTI_INSUFFICIENTI"]]]
        value["candidates"] = candidates
        XCTAssertEqual(SongWebMeaning.parse(value).text,SongWebMeaning.unavailable)
    }
    func testInvalidKeyOrModelDoesNotSendRequest() async {
        for (model,key) in [("gemini-3.8-flash",""),("../other?key=x","fixture")] {
            do { _ = try await SongWebMeaning().explain(title:"Brano",artist:"Artista",model:model,key:key);XCTFail("Expected rejection") }
            catch { XCTAssertTrue(error is MeaningContentError) }
        }
    }
}

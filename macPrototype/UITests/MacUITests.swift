import XCTest

final class MacUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  private func elapsedSeconds(_ element: XCUIElement) -> Int {
    if let raw = element.value as? String,
      let seconds = Int(raw.components(separatedBy: " ").first ?? "")
    {
      return seconds
    }
    let clock = element.label.split(separator: ":").compactMap { Int($0) }
    return clock.reduce(0) { $0 * 60 + $1 }
  }

  @MainActor
  private func openReferenceSong(_ app: XCUIApplication) {
    app.typeKey("2", modifierFlags: .command)
    let field = app.textFields["mac-search-field"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.click()
    field.typeText("Old and Wise The Alan Parsons Project")
    app.buttons["mac-search-submit"].click()
    let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "song-"))
      .firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 35))
    first.click()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    let playing = {
      XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"), object: toggle)
    }
    if XCTWaiter.wait(for: [playing()], timeout: 15) != .completed {
      toggle.click()
      XCTAssertEqual(XCTWaiter.wait(for: [playing()], timeout: 40), .completed)
    }
  }

  @MainActor
  func testPlaybackSurvivesNavigationAndWindowMinimization() {
    let app = XCUIApplication()
    app.launchArguments.append("--test-isolated")
    app.launch()
    openReferenceSong(app)
    let time = app.descendants(matching: .any).matching(identifier: "playback-elapsed").firstMatch
    XCTAssertTrue(time.waitForExistence(timeout: 5))
    let start = elapsedSeconds(time)
    app.buttons["close-player"].click()
    XCTAssertTrue(app.buttons["mini-playback-toggle"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["mini-playback-toggle"].value as? String, "Riproduzione attiva")
    app.typeKey("3", modifierFlags: .command)
    app.typeKey("m", modifierFlags: .command)
    // Allow actual media time to advance with no visible window.
    Thread.sleep(forTimeInterval: 5)
    app.activate()
    app.typeKey("0", modifierFlags: .command)
    app.typeKey("4", modifierFlags: .command)
    XCTAssertTrue(time.waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "Riproduzione attiva")
    let advance = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        self.elapsedSeconds(time) >= start + 4
      }, object: time)
    XCTAssertEqual(XCTWaiter.wait(for: [advance], timeout: 10), .completed, time.debugDescription)
    app.buttons["toggle-lyrics"].click()
    XCTAssertTrue(app.buttons["toggle-lyrics"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "NoteNarrate Mac player"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["playback-toggle"].click()
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
  }

  @MainActor
  func testNativeNarrationPausesAndResumesMusic() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-meaning"]
    app.launchArguments.append("--test-isolated")
    app.launch()
    openReferenceSong(app)
    app.buttons["Significato della canzone"].click()
    XCTAssertTrue(app.staticTexts["meaning-text"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
    let resumed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"),
      object: app.buttons["playback-toggle"])
    XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 30), .completed)
    app.buttons["close-meaning"].click()
    app.typeKey(.space, modifierFlags: .command)
  }

  @MainActor
  func testStreamingNarrationFinishesAndReplaysCachedAudio() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-stream-meaning"]
    app.launchArguments.append("--test-isolated")
    app.launch()
    openReferenceSong(app)
    app.buttons["Significato della canzone"].click()
    XCTAssertTrue(app.staticTexts["meaning-text"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
    let resumed = {
      XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"),
        object: app.buttons["playback-toggle"])
    }
    XCTAssertEqual(XCTWaiter.wait(for: [resumed()], timeout: 25), .completed)
    let replay = app.buttons["Leggi interpretazione"]
    XCTAssertTrue(replay.waitForExistence(timeout: 5))
    replay.click()
    let reading = app.buttons["Interrompi lettura"]
    XCTAssertTrue(reading.waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
    XCTAssertEqual(XCTWaiter.wait(for: [resumed()], timeout: 25), .completed)
    app.buttons["close-meaning"].click()
    app.typeKey(.space, modifierFlags: .command)
  }
}

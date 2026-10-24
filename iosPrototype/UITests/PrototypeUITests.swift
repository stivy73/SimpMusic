import XCTest

final class PrototypeUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  @MainActor
  private func selectTab(_ label: String, symbol: String, in app: XCUIApplication) {
    let standard = app.tabBars.buttons[label]
    if standard.exists {
      standard.tap()
    } else {
      // Duo exposes native vertical tabs outside the TabBar accessibility container.
      let vertical = app.descendants(matching: .any).matching(
        NSPredicate(
          format: "label == %@ AND (elementType == %d OR elementType == %d)",
          label, XCUIElement.ElementType.button.rawValue,
          XCUIElement.ElementType.popUpButton.rawValue)
      ).firstMatch
      XCTAssertTrue(vertical.waitForExistence(timeout: 10))
      vertical.tap()
    }
  }

  @MainActor
  private func searchReferenceSong(in app: XCUIApplication) {
    selectTab("Cerca", symbol: "magnifyingglass", in: app)
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("Old and Wise The Alan Parsons Project\n")
  }

  @MainActor
  private func findReferenceSong(in app: XCUIApplication) -> XCUIElement {
    let song = app.buttons["song-ZmzqqdVFw8g"]
    let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "song-"))
      .firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 30))
    // YouTube may reorder or replace the recording in live search results.
    return song.exists ? song : first
  }

  @MainActor
  private func waitForPlayback(_ toggle: XCUIElement) {
    let playing = {
      XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"), object: toggle)
    }
    // Let autoplay settle before tapping: a tap during startup can pause it.
    if XCTWaiter.wait(for: [playing()], timeout: 15) != .completed {
      if toggle.value as? String != "Riproduzione attiva" { toggle.tap() }
      XCTAssertEqual(XCTWaiter.wait(for: [playing()], timeout: 45), .completed)
    }
  }

  @MainActor
  func testPlayerKeepsLyricsQueueAndPlaybackAcrossResize() {
    let app = XCUIApplication()
    app.launch()
    searchReferenceSong(in: app)
    let song = findReferenceSong(in: app)
    song.tap()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 15))
    waitForPlayback(toggle)
    app.buttons["Altre opzioni"].tap()
    app.buttons["Aggiungi o modifica il testo"].coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
    ).tap()
    let editor = app.textViews["manual-lyrics-editor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 10))
    editor.tap()
    editor.typeText("Un ricordo che resta: testo di prova del layout adattivo.")
    app.buttons["Fine"].tap()
    let lyrics = app.staticTexts["song-lyrics"]
    XCTAssertTrue(lyrics.waitForExistence(timeout: 10))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(lyrics.waitForExistence(timeout: 10))
    XCTAssertTrue(lyrics.label.contains("testo di prova del layout adattivo"))
    XCTAssertTrue(app.buttons["show-queue"].exists)
    XCUIDevice.shared.orientation = .portrait
    XCTAssertTrue(lyrics.waitForExistence(timeout: 10))
    app.buttons["close-player"].tap()
    let mini = app.buttons["open-player"]
    XCTAssertTrue(mini.waitForExistence(timeout: 10))
    mini.tap()
    XCTAssertTrue(lyrics.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "Riproduzione attiva")
    toggle.tap()
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Player adattivo con testo conservato"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testLiveHomeFiltersGenresAndCategoryNavigation() {
    let app = XCUIApplication()
    app.launch()
    let relax = app.buttons["home-filter-relax"]
    XCTAssertTrue(relax.waitForExistence(timeout: 10))
    let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "home-item-"))
      .firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 45))
    let firstScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    firstScreenshot.name = "Home YouTube Music"
    firstScreenshot.lifetime = .keepAlways
    add(firstScreenshot)
    relax.tap()
    XCTAssertEqual(relax.value as? String, "Selezionato")
    XCTAssertTrue(item.waitForExistence(timeout: 45))
    app.buttons["home-filter-all"].tap()
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "ready"), object: app.staticTexts["home-status"]
    )
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
    let scroll = app.scrollViews["home-scroll"]
    let category = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "home-category-")
    ).firstMatch
    for _ in 0..<16 {
      if category.exists && category.isHittable && (180..<700).contains(category.frame.midY) {
        break
      }
      scroll.swipeUp()
    }
    XCTAssertTrue(category.waitForExistence(timeout: 20))
    XCTAssertTrue(category.isHittable)
    let categoryScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    categoryScreenshot.name = "Generi e stati d’animo"
    categoryScreenshot.lifetime = .keepAlways
    add(categoryScreenshot)
    category.tap()
    XCTAssertTrue(item.waitForExistence(timeout: 45))
    let detailScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    detailScreenshot.name = "Categoria YouTube Music"
    detailScreenshot.lifetime = .keepAlways
    add(detailScreenshot)
    let playlist = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "home-item-playlist:")
    ).firstMatch
    if playlist.exists && playlist.isHittable {
      playlist.tap()
      XCTAssertTrue(item.waitForExistence(timeout: 45))
      let track = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "home-item-song:")
      ).firstMatch
      XCTAssertTrue(track.waitForExistence(timeout: 20))
      track.tap()
      let toggle = app.buttons["playback-toggle"]
      XCTAssertTrue(toggle.waitForExistence(timeout: 10))
      waitForPlayback(toggle)
      let elapsed = app.staticTexts["playback-elapsed"]
      let progressed = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          (Double(elapsed.value as? String ?? "") ?? 0) >= 2
        }, object: elapsed)
      XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 45), .completed)
      app.buttons["close-player"].tap()
      XCTAssertEqual(app.buttons["mini-playback-toggle"].value as? String, "Riproduzione attiva")
      app.buttons["mini-playback-toggle"].tap()
    }
  }

  @MainActor
  func testLiveSearchAndPlayback() {
    let app = XCUIApplication()
    app.launch()
    searchReferenceSong(in: app)
    let song = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "song-"))
      .firstMatch
    XCTAssertTrue(song.waitForExistence(timeout: 30))
    song.tap()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    let playing = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 60), .completed)
    let elapsed = app.staticTexts["playback-elapsed"]
    let progressed = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        let seconds = Double(elapsed.value as? String ?? "") ?? 0
        return seconds >= 3
      }, object: elapsed)
    XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 60), .completed)
    XCTAssertFalse(app.staticTexts["playback-error"].exists)
    let slider = app.sliders.firstMatch
    XCTAssertTrue(slider.waitForExistence(timeout: 5))
    slider.adjust(toNormalizedSliderPosition: 0.8)
    let seekTime = Double(elapsed.value as? String ?? "") ?? 0
    let continued = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        let current = Double(elapsed.value as? String ?? "") ?? 0
        return current >= seekTime + 2
      }, object: elapsed)
    XCTAssertEqual(XCTWaiter.wait(for: [continued], timeout: 30), .completed)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Player iOS"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    toggle.tap()
    let paused = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "In pausa"), object: toggle)
    XCTAssertEqual(XCTWaiter.wait(for: [paused], timeout: 10), .completed)
    XCTAssertTrue(app.buttons["Significato della canzone"].exists)
    app.buttons["return-to-library"].tap()
    let settings = app.tabBars.buttons["Impostazioni"]
    let reachable = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hittable == true"), object: settings)
    XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 10), .completed)
    settings.tap()
    XCTAssertTrue(app.secureTextFields["gemini-key"].waitForExistence(timeout: 10))
  }
  @MainActor
  func testRotationAndReopeningPreservePausedPosition() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    let app = XCUIApplication()
    app.launch()
    searchReferenceSong(in: app)
    let song = findReferenceSong(in: app)
    XCTAssertTrue(song.exists)
    song.tap()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: toggle)
        ], timeout: 60), .completed)
    waitForPlayback(toggle)
    let initial = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    initial.name = "Player pronto"
    initial.lifetime = .keepAlways
    add(initial)
    app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.4)
    let elapsed = app.staticTexts["playback-elapsed"]
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (Double(elapsed.value as? String ?? "") ?? 0) > 20 },
            object: elapsed)
        ], timeout: 20), .completed)
    toggle.tap()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "In pausa"), object: toggle)
        ], timeout: 10), .completed)
    let before = Double(elapsed.value as? String ?? "") ?? 0
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              let frame = app.windows.firstMatch.frame
              return frame.width > frame.height
            }, object: app)
        ], timeout: 15), .completed)
    XCTAssertTrue(toggle.isHittable)
    XCTAssertEqual(toggle.value as? String, "In pausa")
    XCTAssertEqual(Double(elapsed.value as? String ?? "") ?? 0, before, accuracy: 2)
    let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    landscape.name = "Player adattivo landscape"
    landscape.lifetime = .keepAlways
    add(landscape)
    app.buttons["close-player"].tap()
    XCTAssertTrue(app.buttons["open-player"].waitForExistence(timeout: 10))
    app.buttons["open-player"].tap()
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              toggle.isEnabled && toggle.value as? String == "In pausa"
                && abs((Double(elapsed.value as? String ?? "") ?? 0) - before) <= 2
            }, object: toggle)
        ], timeout: 30), .completed)
    XCUIDevice.shared.orientation = .portrait
    XCTAssertTrue(app.buttons["return-to-library"].isHittable)
    app.buttons["return-to-library"].tap()
    XCTAssertTrue(app.buttons["Accedi a YouTube Music"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testNativeSpeechPausesThenResumesMusic() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--test-meaning", "--test-native-audio"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"), object: toggle)
        ], timeout: 60), .completed)
    app.swipeUp()
    app.buttons["Significato della canzone"].tap()
    XCTAssertTrue(app.staticTexts["meaning-text"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.buttons["Interrompi lettura"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.buttons["Leggi interpretazione"].waitForExistence(timeout: 30))
    app.buttons["close-meaning"].tap()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"), object: toggle)
        ], timeout: 20), .completed)
    toggle.tap()
    app.buttons["Significato della canzone"].tap()
    XCTAssertTrue(app.buttons["Interrompi lettura"].waitForExistence(timeout: 20))
    app.buttons["Interrompi lettura"].tap()
    app.buttons["close-meaning"].tap()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "In pausa"), object: toggle)
        ], timeout: 10), .completed)
  }

  @MainActor
  func testArtworkVideoLyricsAndQueue() {
    let app = XCUIApplication()
    app.launch()
    searchReferenceSong(in: app)
    let song = findReferenceSong(in: app)
    XCTAssertTrue(song.exists)
    song.tap()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    waitForPlayback(toggle)
    let artwork = app.descendants(matching: .any).matching(identifier: "player-artwork").firstMatch
    XCTAssertTrue(artwork.waitForExistence(timeout: 5))
    let elapsed = app.staticTexts["playback-elapsed"]
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              (Double(elapsed.value as? String ?? "") ?? 0) > 3
            }, object: elapsed)
        ], timeout: 30), .completed)
    toggle.tap()
    let before = Double(elapsed.value as? String ?? "") ?? 0
    // iOS audio no longer relies on WebKit. Video remains an explicit external action.
    XCTAssertTrue(app.buttons["toggle-video"].exists)
    XCTAssertEqual(toggle.value as? String, "In pausa")
    XCTAssertEqual(Double(elapsed.value as? String ?? "") ?? 0, before, accuracy: 2)
    XCTAssertEqual(toggle.value as? String, "In pausa")
    app.buttons["Altre opzioni"].tap()
    app.buttons["Aggiungi o modifica il testo"].tap()
    let editor = app.textViews["manual-lyrics-editor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("Un ricordo attraversa la notte.\nUna nuova strada ci aspetta.")
    app.buttons["Fine"].tap()
    XCTAssertTrue(app.staticTexts["song-lyrics"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["song-lyrics"].label.contains("Un ricordo"))
    app.buttons["show-queue"].tap()
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-"))
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
    XCTAssertGreaterThan(rows.count, 1)
    rows.element(boundBy: 1).tap()
    waitForPlayback(toggle)
    XCTAssertFalse(app.staticTexts["song-lyrics"].label.contains("Un ricordo"))
    toggle.tap()
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Player copertina testo e controlli Android"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testSignedOutLibraryAndLoginSheet() {
    let app = XCUIApplication()
    app.launch()
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    XCTAssertTrue(app.buttons["Accedi a YouTube Music"].waitForExistence(timeout: 10))
    app.buttons["Accedi a YouTube Music"].tap()
    XCTAssertTrue(app.buttons["Usa questo account"].waitForExistence(timeout: 15))
    // An ephemeral session can show Google's cookie choices before the music page.
    let reject = app.webViews.buttons.matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Rifiuta tutto", "Reject all")
    ).firstMatch
    if reject.waitForExistence(timeout: 15) {
      for _ in 0..<8 {
        if reject.isHittable { break }
        app.webViews.firstMatch.swipeUp()
      }
      reject.tap()
    }
    let status = app.staticTexts["login-browser-status"]
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "ready"), object: status)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
    XCTAssertTrue(app.buttons["Usa questo account"].isEnabled)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "YouTube Music login supported"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["Annulla"].tap()
    XCTAssertTrue(app.buttons["Accedi a YouTube Music"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testStreamingSpeechRotationCompletionAndStop() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--test-stream-meaning"]
    app.launch()
    XCTAssertTrue(app.buttons["home-filter-all"].waitForExistence(timeout: 10))
    let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    home.name = "NoteNarrate Home"
    home.lifetime = .keepAlways
    add(home)
    searchReferenceSong(in: app)
    let song = findReferenceSong(in: app)
    XCTAssertTrue(song.exists)
    song.tap()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    waitForPlayback(toggle)
    app.buttons["Significato della canzone"].tap()
    let stop = app.buttons["Interrompi lettura"]
    XCTAssertTrue(stop.waitForExistence(timeout: 15))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(stop.exists)
    XCTAssertTrue(app.buttons["Leggi interpretazione"].waitForExistence(timeout: 25))
    XCUIDevice.shared.orientation = .portrait
    // The same interpretation reuses cached audio; no new generation is needed.
    app.buttons["Leggi interpretazione"].tap()
    XCTAssertTrue(stop.waitForExistence(timeout: 15))
    stop.tap()
    app.buttons["close-meaning"].tap()
    waitForPlayback(toggle)
    toggle.tap()
  }

  @MainActor
  func testMinimizingKeepsMusicPlayingAcrossTabs() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-native-audio"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    waitForPlayback(toggle)
    let elapsed = app.staticTexts["playback-elapsed"]
    let before = Double(elapsed.value as? String ?? "") ?? 0
    app.buttons["close-player"].tap()
    let mini = app.buttons["mini-playback-toggle"]
    XCTAssertTrue(mini.waitForExistence(timeout: 10))
    XCTAssertEqual(mini.value as? String, "Riproduzione attiva")
    XCTAssertTrue(app.buttons["open-player"].isHittable)
    XCTAssertFalse(app.buttons["close-player"].isHittable)
    let minimized = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    minimized.name = "Player ridotto dopo animazione"
    minimized.lifetime = .keepAlways
    add(minimized)
    selectTab("Home", symbol: "house.fill", in: app)
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    selectTab("Cerca", symbol: "magnifyingglass", in: app)
    XCTAssertEqual(mini.value as? String, "Riproduzione attiva")
    app.buttons["open-player"].tap()
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "Riproduzione attiva")
    XCTAssertTrue(app.buttons["close-player"].isHittable)
    XCTAssertGreaterThan(Double(elapsed.value as? String ?? "") ?? 0, before + 2)
    app.buttons["return-to-library"].tap()
    XCTAssertTrue(mini.waitForExistence(timeout: 10))
    XCTAssertEqual(mini.value as? String, "Riproduzione attiva")
    mini.tap()
    XCTAssertEqual(mini.value as? String, "In pausa")
    app.buttons["open-player"].tap()
    XCTAssertEqual(toggle.value as? String, "In pausa")
    let paused = Double(elapsed.value as? String ?? "") ?? 0
    app.buttons["close-player"].tap()
    selectTab("Home", symbol: "house.fill", in: app)
    selectTab("Cerca", symbol: "magnifyingglass", in: app)
    app.buttons["open-player"].tap()
    XCTAssertEqual(toggle.value as? String, "In pausa")
    XCTAssertEqual(Double(elapsed.value as? String ?? "") ?? 0, paused, accuracy: 1)
  }

  @MainActor
  func testNativeMusicContinuesWhenAppEntersBackground() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-native-audio"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    waitForPlayback(toggle)
    let elapsed = app.staticTexts["playback-elapsed"]
    let before = Double(elapsed.value as? String ?? "") ?? 0
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
    // Remain outside the app long enough to distinguish background audio from a UI resume.
    // A bounded delay with no app interaction; elapsed is checked against actual AVPlayer time.
    Thread.sleep(forTimeInterval: 8)
    app.activate()
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "Riproduzione attiva")
    XCTAssertGreaterThan(Double(elapsed.value as? String ?? "") ?? 0, before + 6)
    toggle.tap()
  }

  @MainActor
  func testCarPlayNativeNarrationStartsInBackgroundAndResumesMusic() {
    verifyCarPlayNarration(streaming: false)
  }

  @MainActor
  func testCarPlayStreamingNarrationStartsInBackgroundAndResumesMusic() {
    verifyCarPlayNarration(streaming: true)
  }

  @MainActor
  private func verifyCarPlayNarration(streaming: Bool) {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-native-audio", "--test-carplay-meaning",
      streaming ? "--test-stream-meaning" : "--test-meaning",
    ]
    if streaming { app.launchArguments.append("--test-carplay-delayed-preparation") }
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 15))
    waitForPlayback(toggle)
    let diagnostics = app.staticTexts["carplay-diagnostics"]
    XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              diagnostics.label.split(separator: ":").dropFirst(4).first == "true"
            },
            object: diagnostics)
        ], timeout: 25), .completed, "System artwork provider must return an image")
    app.swipeUp()
    app.buttons["Significato della canzone"].tap()
    XCTAssertFalse(
      app.staticTexts["meaning-text"].exists, "CarPlay must not open the phone meaning sheet")
    XCTAssertTrue(diagnostics.label.hasSuffix(":true"), "Preparation has a background task")
    if streaming {
      XCTAssertTrue(diagnostics.label.hasPrefix("0:0:false:true:"))
      XCTAssertEqual(
        toggle.value as? String, "Riproduzione attiva",
        "CarPlay must keep music active until narration audio is ready")
    }
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
    Thread.sleep(forTimeInterval: streaming ? 18 : 14)
    app.activate()
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in diagnostics.label.hasPrefix("1:1:false:false:") },
            object: diagnostics)
        ], timeout: 25), .completed)
    XCTAssertFalse(diagnostics.label.hasSuffix(":true"), "Preparation task is released")
    XCTAssertEqual(toggle.value as? String, "Riproduzione attiva")
    toggle.tap()
  }

  @MainActor
  func testSystemNowPlayingRemainsActiveDuringCarPlayVoice() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-native-audio", "--test-carplay-meaning", "--test-meaning"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 20))
    waitForPlayback(toggle)
    app.swipeUp()
    app.buttons["Significato della canzone"].tap()
    let diagnostics = app.staticTexts["carplay-diagnostics"]
    let activeVoice = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        let fields = diagnostics.label.split(separator: ":")
        return fields.count == 7 && fields[2] == "true" && fields[5] == "true"
      }, object: diagnostics)
    XCTAssertEqual(XCTWaiter.wait(for: [activeVoice], timeout: 15), .completed)
    let completed = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        diagnostics.label.hasPrefix("1:1:false:false:")
      }, object: diagnostics)
    XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed)
    waitForPlayback(toggle)
    toggle.tap()
  }

  @MainActor
  func testRejectedCarPlayPresentationResumesMusicWithoutStartingVoice() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-native-audio", "--test-carplay-meaning", "--test-meaning",
      "--test-carplay-presentation-failure",
    ]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 20))
    waitForPlayback(toggle)
    app.swipeUp()
    app.buttons["Significato della canzone"].tap()
    XCTAssertFalse(app.staticTexts["meaning-text"].exists)
    let diagnostics = app.staticTexts["carplay-diagnostics"]
    XCTAssertTrue(diagnostics.label.hasPrefix("0:0:false:false:"))
    waitForPlayback(toggle)
    toggle.tap()
  }

  @MainActor
  func testNativeAudioStartupDiagnostic() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-native-audio"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    let playing = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "Riproduzione attiva"), object: toggle)
    XCTAssertEqual(
      XCTWaiter.wait(for: [playing], timeout: 25), .completed,
      app.staticTexts["native-audio-status"].label)
  }

}

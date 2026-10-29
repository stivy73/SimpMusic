import XCTest

final class PrototypeUITests: XCTestCase {
  @MainActor
  func testPaddedAudioAdvancesAtSourceEndWithoutWaitingForSilentTail() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-padded-audio-end"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 25))
    let second = app.staticTexts["Brano locale 2"].firstMatch
    XCTAssertTrue(second.waitForExistence(timeout: 20), "Six seconds of audio must not wait for a 120-second silent tail")
    waitForPlayback(toggle)
    toggle.tap()
  }

  @MainActor
  func testCarPlayVoiceRestoresFiniteMusicClockAfterCompletion() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-carplay-meaning", "--test-stream-meaning"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 20))
    waitForPlayback(toggle)
    app.swipeUp()
    app.buttons["Significato della canzone"].tap()
    let timing = app.staticTexts["now-playing-timing"]
    let voice = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      timing.label.hasSuffix(":1.0:true")
    }, object: timing)
    XCTAssertEqual(XCTWaiter.wait(for: [voice], timeout: 15), .completed)
    let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let values = timing.label.split(separator: ":")
      return values.count == 4 && (Double(values[0]) ?? 0) > 29
        && (Double(values[1]) ?? -1) >= 0 && values[2] == "1.0" && values[3] == "false"
    }, object: timing)
    XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 20), .completed)
    waitForPlayback(toggle)
    toggle.tap()
  }

  @MainActor
  func testPlayerMoreOpensSongOptionsDirectlyWithoutVideo() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-long-local", "--test-remote-library"]
    app.launch()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["youtube-like-local-1-80"].isHittable)
    openPlayerOptions(app)
    XCTAssertTrue(app.buttons["song-option-like"].exists)
    XCTAssertFalse(app.buttons["youtube-like-local-1-80"].exists)
    XCTAssertTrue(app.buttons["song-option-like"].label.contains("YouTube Music"))
    XCTAssertFalse(app.buttons["Mostra video"].exists)
    XCTAssertFalse(app.buttons["toggle-video"].exists)
    app.buttons["song-options-close"].tap()
    XCTAssertTrue(app.buttons["close-player"].isHittable)
    XCTAssertFalse(app.buttons["toggle-video"].exists)
    if app.buttons["playback-toggle"].value as? String == "Riproduzione attiva" {
      app.buttons["playback-toggle"].tap()
    }
  }

  @MainActor
  func testSavingSettingsReturnsToHome() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-remote-library"]
    app.launch()
    selectTab("Impostazioni", symbol: "gearshape.fill", in: app)
    saveSettingsAndExpectHome(app)
  }

  @MainActor
  func testConnectedDeviceSavingSettingsReturnsHome() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Physical-device check saves the existing settings without editing fields")
    #else
      let app = XCUIApplication()
      app.activate()
      if app.buttons["song-options-close"].isHittable {
        app.buttons["song-options-close"].tap()
      }
      if app.buttons["close-player"].isHittable { app.buttons["close-player"].tap() }
      selectTab("Impostazioni", symbol: "gearshape.fill", in: app)
      saveSettingsAndExpectHome(app)
    #endif
  }

  @MainActor
  private func saveSettingsAndExpectHome(_ app: XCUIApplication) {
    let save = app.buttons["settings-save"]
    let form = app.collectionViews.firstMatch
    for _ in 0..<8 {
      if save.isHittable { break }
      // The full Duo window includes the separate system side region. Scroll
      // the Form itself so the gesture starts in its content on either posture.
      if form.exists { form.swipeUp() } else { app.swipeUp() }
    }
    XCTAssertTrue(save.isHittable)
    save.tap()
    XCTAssertEqual(
      XCTWaiter.wait(for: [XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "hittable == true"),
        object: app.buttons["home-filter-all"])], timeout: 8), .completed)
    XCTAssertFalse(app.staticTexts["settings-error"].exists)
    XCTAssertFalse(save.isHittable)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Home after saving settings"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testConnectedDevicePlayerOptionsCloseAndBack() throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Physical-device check uses the existing account and paused session")
    #else
      let app = XCUIApplication()
      app.activate()
      let close = app.buttons["song-options-close"]
      if close.exists {
        close.tap()
        XCTAssertEqual(
          XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: close)], timeout: 6), .completed)
      }
      let back = app.buttons["close-player"]
      if !back.exists {
        let open = app.buttons["open-player"]
        guard open.waitForExistence(timeout: 10) else {
          throw XCTSkip("No saved track; this check does not start new playback")
        }
        open.tap()
      }
      XCTAssertTrue(back.waitForExistence(timeout: 10), app.debugDescription)
      openPlayerOptions(app)
      XCTAssertTrue(app.buttons.matching(NSPredicate(
        format: "identifier BEGINSWITH %@", "youtube-like-")).firstMatch.exists)
      XCTAssertFalse(app.buttons["Mostra video"].exists)
      XCTAssertFalse(app.buttons["toggle-video"].exists)
      XCTAssertTrue(close.waitForExistence(timeout: 6), app.debugDescription)
      XCTAssertTrue(close.isHittable)
      close.tap()
      XCTAssertEqual(
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == false"), object: close)], timeout: 6), .completed)
      XCTAssertTrue(back.isHittable)
      back.tap()
      let open = app.buttons["open-player"]
      let mini = app.buttons["mini-playback-toggle"]
      XCTAssertTrue(open.waitForExistence(timeout: 6))
      let previousStatus = mini.value as? String
      open.tap()
      XCTAssertTrue(back.waitForExistence(timeout: 6))
      let window = app.windows.firstMatch
      window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.35))
        .press(forDuration: 0.1, thenDragTo:
          window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.35)))
      XCTAssertTrue(open.waitForExistence(timeout: 6), app.debugDescription)
      XCTAssertEqual(mini.value as? String, previousStatus)
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "Duo physical device after Close, Back and edge swipe"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    #endif
  }

  @MainActor
  func testSongOptionsCloseReturnsToPlayerAndNestedAlbum() {
    let app = XCUIApplication()
    startAlbumPlayer(app)
    let close = app.buttons["song-options-close"]
    XCTAssertTrue(close.isHittable, app.debugDescription)
    close.tap()
    XCTAssertEqual(
      XCTWaiter.wait(for: [XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "exists == false"), object: close)], timeout: 6), .completed)
    XCTAssertTrue(app.buttons["close-player"].isHittable)
    openPlayerOptions(app)
    let album = app.buttons["song-option-album"]
    if !album.isHittable { app.swipeUp() }
    album.tap()
    XCTAssertTrue(app.buttons["album-play"].waitForExistence(timeout: 8))
    let scroll = app.scrollViews["album-scroll"]
    let trackOptions = app.buttons["album-track-options-1"]
    for _ in 0..<4 {
      if trackOptions.isHittable { break }
      scroll.swipeUp()
    }
    XCTAssertTrue(trackOptions.isHittable)
    trackOptions.tap()
    XCTAssertTrue(close.waitForExistence(timeout: 6))
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(close.isHittable, "Close remains reachable after resizing")
    close.tap()
    XCTAssertTrue(app.scrollViews["album-scroll"].waitForExistence(timeout: 6))
    XCTAssertFalse(app.buttons["song-option-like"].isHittable,
      "Only the nested song menu should close; the album stays open")
    XCUIDevice.shared.orientation = .portrait
  }

  @MainActor
  func testPlayerEdgeSwipeBackKeepsMusicAndAllowsScrubbing() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-long-local"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
    waitForPlayback(toggle)
    let back = app.buttons["close-player"]
    let seek = app.sliders["playback-seek"]
    if !seek.isHittable { app.swipeUp() }
    XCTAssertTrue(seek.isHittable, app.debugDescription)
    seek.adjust(toNormalizedSliderPosition: 0.3)
    XCTAssertTrue(back.isHittable, "Scrubbing must not dismiss the player")
    let elapsed = app.staticTexts["playback-elapsed"]
    let position = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (Double(elapsed.value as? String ?? "") ?? 0) >= 20 },
      object: elapsed)
    XCTAssertEqual(XCTWaiter.wait(for: [position], timeout: 8), .completed)
    let window = app.windows.firstMatch
    let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.35))
    let cancelled = edge.withOffset(CGVector(dx: 18, dy: 0))
    edge.press(forDuration: 0.1, thenDragTo: cancelled)
    XCTAssertTrue(back.isHittable, "A short edge gesture must cancel")
    let destination = window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.35))
    edge.press(forDuration: 0.1, thenDragTo: destination)
    let mini = app.buttons["mini-playback-toggle"]
    XCTAssertTrue(mini.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertEqual(mini.value as? String, "Riproduzione attiva")
    app.buttons["open-player"].tap()
    XCTAssertTrue(back.waitForExistence(timeout: 8))
    XCTAssertEqual(toggle.value as? String, "Riproduzione attiva")
    XCTAssertGreaterThanOrEqual(Double(elapsed.value as? String ?? "") ?? 0, 20)
    toggle.tap()
  }

  @MainActor
  func testDuoVerticalPlayerBarAndBackNavigation() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-long-local", "--test-karaoke"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
    waitForPlayback(toggle)
    let back = app.buttons["close-player"]
    let queue = app.buttons["show-queue"]
    let lyrics = app.buttons["toggle-lyrics"]
    for button in [back, queue, lyrics] {
      XCTAssertTrue(button.isHittable, app.debugDescription)
      XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), "Control outside window")
    }
    // These commands must share the system's side region, rather than a clipped
    // toolbar or a second row laid over the album artwork.
    XCTAssertEqual(back.frame.midX, queue.frame.midX, accuracy: 12)
    XCTAssertLessThan(back.frame.midY, queue.frame.midY)
    let sidebar = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    sidebar.name = "Duo player with native side controls and Back"
    sidebar.lifetime = .keepAlways
    add(sidebar)

    lyrics.tap()
    XCTAssertTrue(app.scrollViews["synchronized-lyrics-scroll"].firstMatch.waitForExistence(timeout: 8))
    app.buttons["Chiudi"].firstMatch.tap()
    queue.tap()
    XCTAssertTrue(app.staticTexts["queue-count"].waitForExistence(timeout: 8))
    app.buttons["Chiudi"].firstMatch.tap()
    back.tap()
    let mini = app.buttons["mini-playback-toggle"]
    XCTAssertTrue(mini.waitForExistence(timeout: 8))
    XCTAssertEqual(mini.value as? String, "Riproduzione attiva")
    selectTab("Cerca", symbol: "magnifyingglass", in: app)
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8))
    app.buttons["open-player"].tap()
    XCTAssertTrue(back.waitForExistence(timeout: 8))
    back.tap()
    XCTAssertTrue(app.searchFields.firstMatch.isHittable, "Back must return to the previous tab")
    XCTAssertEqual(mini.value as? String, "Riproduzione attiva")
    mini.tap()
  }

  @MainActor
  private func startAlbumPlayer(_ app: XCUIApplication, multipleArtists: Bool = false) {
    app.launchArguments = ["--test-local-playback", "--test-album-player", "--test-remote-library"]
    if multipleArtists { app.launchArguments.append("--test-album-multiple-artists") }
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
    if toggle.value as? String == "Riproduzione attiva" { toggle.tap() }
    app.swipeUp()
    openPlayerOptions(app)
    XCTAssertTrue(app.buttons["song-option-like"].waitForExistence(timeout: 5))
  }

  @MainActor
  private func openPlayerOptions(_ app: XCUIApplication) {
    let options = app.buttons["player-more-options"]
    XCTAssertTrue(options.waitForExistence(timeout: 6), app.debugDescription)
    for _ in 0..<3 {
      if options.isHittable { break }
      app.swipeDown()
    }
    XCTAssertTrue(options.isHittable)
    options.tap()
    XCTAssertTrue(app.buttons["song-options-close"].waitForExistence(timeout: 6),
      "The three dots should open the sheet directly")
  }

  @MainActor
  func testPlayerOffersEveryCreditedArtist() {
    let app = XCUIApplication()
    startAlbumPlayer(app, multipleArtists: true)
    app.buttons["song-option-artists"].tap()
    XCTAssertTrue(app.buttons["context-artist-UCfixture"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["context-artist-UCguest"].exists)
    app.buttons["context-artist-UCguest"].tap()
    XCTAssertTrue(app.navigationBars["Artista ospite"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testPlayerOptionsLikesPlaylistAndPlayNextKeepCurrentTrack() {
    let app = XCUIApplication()
    startAlbumPlayer(app)
    let like = app.buttons["song-option-like"]
    let before = like.value as? String
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Menu brano come Android"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    like.tap()
    let liked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: like)
    XCTAssertEqual(XCTWaiter.wait(for: [liked], timeout: 10), .completed)
    for action in ["playlist", "next", "queue", "artists", "album", "radio", "share"] {
      XCTAssertTrue(app.buttons["song-option-" + action].exists, action)
    }
    app.buttons["song-option-playlist"].tap()
    XCTAssertTrue(app.buttons["Playlist di prova"].waitForExistence(timeout: 8))
    app.buttons["Chiudi"].firstMatch.tap()
    app.buttons["song-option-next"].tap()
    XCTAssertTrue(app.buttons["show-queue"].waitForExistence(timeout: 5))
    app.buttons["show-queue"].tap()
    XCTAssertEqual(app.staticTexts["queue-count"].label, "4 brani")
    let current = app.buttons.matching(identifier: "queue-local-1-30").allElementsBoundByIndex
    XCTAssertTrue(current.contains { $0.value as? String == "Brano corrente" })
  }

  @MainActor
  func testAlbumHeaderFavoriteDownloadAndTrackOptions() {
    let app = XCUIApplication()
    startAlbumPlayer(app)
    let albumLink = app.buttons["song-option-album"]
    if !albumLink.isHittable { app.swipeUp() }
    albumLink.tap()
    XCTAssertTrue(app.buttons["album-play"].waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertEqual(app.staticTexts["album-year"].label, "1988 · Album")
    XCTAssertTrue(app.buttons["album-shuffle"].exists)
    XCTAssertEqual(app.buttons["album-download"].label, "Album disponibile offline")
    let favorite = app.buttons["album-favorite"]
    let wasLiked = favorite.value as? String
    favorite.tap()
    let albumLiked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Attivo"), object: favorite)
    XCTAssertEqual(XCTWaiter.wait(for: [albumLiked], timeout: 10), .completed)
    XCTAssertNotEqual(favorite.value as? String, wasLiked)
    let scroll = app.scrollViews["album-scroll"]
    scroll.swipeUp()
    XCTAssertEqual(app.staticTexts["album-track-summary"].label, "3 tracce, 2 minuti")
    XCTAssertTrue(app.staticTexts["album-description"].label.contains("Storie e viaggi"))
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Album con tracce numerate e opzioni"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["album-track-options-1"].tap()
    XCTAssertTrue(app.buttons["song-option-queue"].waitForExistence(timeout: 5))
    app.buttons["song-options-close"].tap()
    app.buttons["album-track-1"].tap()
    XCTAssertTrue(app.buttons["player-more-options"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Brano locale 2"].exists)
    app.buttons["playback-toggle"].tap()
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["return-to-library"].waitForExistence(timeout: 15))
    app.buttons["return-to-library"].tap()
    app.buttons["library-section-menu"].tap()
    XCTAssertFalse(app.buttons["library-menu-favoriteAlbums"].exists)
    app.buttons["library-menu-likes"].tap()
  }

  @MainActor
  func testPlayerArtistDestinationAndAlbumShuffle() {
    let app = XCUIApplication()
    startAlbumPlayer(app)
    app.buttons["song-option-artists"].tap()
    XCTAssertTrue(app.navigationBars["Prova offline"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    let album = app.buttons["song-option-album"]
    if !album.isHittable { app.swipeUp() }
    album.tap()
    XCTAssertTrue(app.buttons["album-shuffle"].waitForExistence(timeout: 5))
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Copertina e comandi album"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["album-shuffle"].tap()
    XCTAssertTrue(app.buttons["playback-shuffle"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["playback-shuffle"].value as? String, "Attiva")
    app.buttons["show-queue"].tap()
    XCTAssertEqual(app.staticTexts["queue-count"].label, "3 brani")
  }

  @MainActor
  func testLocalOfflineAudioContinuesBeyondMinuteAndMinimizingKeepsPlaying() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-long-local"]
    app.launch()
    let source = app.staticTexts["native-source-status"]
    XCTAssertTrue(source.waitForExistence(timeout: 15), app.debugDescription)
    XCTAssertEqual(source.label, "File locale verificato")
    let elapsed = app.staticTexts["playback-elapsed"]
    expectation(
      for: NSPredicate { _, _ in Int(elapsed.value as? String ?? "0") ?? 0 >= 3 },
      evaluatedWith: elapsed)
    waitForExpectations(timeout: 15)
    app.buttons["close-player"].tap()
    XCTAssertTrue(app.buttons["mini-playback-toggle"].waitForExistence(timeout: 5))
    app.buttons["open-player"].tap()
    expectation(
      for: NSPredicate { _, _ in Int(elapsed.value as? String ?? "0") ?? 0 >= 65 },
      evaluatedWith: elapsed)
    waitForExpectations(timeout: 85)
    XCTAssertFalse(app.staticTexts["playback-error"].exists)
    XCTAssertTrue(app.staticTexts["native-audio-status"].label.contains("PCM "))
    let diagnostic = app.staticTexts["native-audio-status"].label
    let count = diagnostic.components(separatedBy: "PCM ").last.flatMap(Int.init) ?? 0
    XCTAssertGreaterThan(count, 100000)
    app.buttons["playback-toggle"].tap()
  }

  @MainActor
  func testCrossfadePromotesPreparedTrackAndManualPauseStopsBothDecks() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-crossfade"]
    app.launch()
    let id = app.staticTexts["test-current-id"]
    XCTAssertTrue(id.waitForExistence(timeout: 15), app.debugDescription)
    app.buttons["playback-toggle"].tap()
    expectation(for: NSPredicate(format: "label == %@", "local-2-10"), evaluatedWith: id)
    waitForExpectations(timeout: 18)
    XCTAssertFalse(app.staticTexts["playback-error"].exists)
    XCTAssertEqual(app.staticTexts["test-crossfade-starts"].label, "1")
    app.buttons["playback-toggle"].tap()
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
    let next = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", "local-3-10"), object: id)
    next.isInverted = true
    XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 5), .completed)
  }

  @MainActor
  func testSleepTimerStopsAndSynchronizedLyricSeeks() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback"]
    app.launch()
    let timer = app.buttons["test-sleep-short"]
    XCTAssertTrue(timer.waitForExistence(timeout: 15))
    app.buttons["toggle-lyrics"].tap()
    app.buttons["Espandi testo"].tap()
    let line = app.buttons["lyric-line-2"].firstMatch
    XCTAssertTrue(line.waitForExistence(timeout: 5))
    line.tap()
    app.buttons["Chiudi"].firstMatch.tap()
    let elapsed = app.staticTexts["playback-elapsed"]
    expectation(
      for: NSPredicate { _, _ in Int(elapsed.value as? String ?? "0") ?? 0 >= 6 },
      evaluatedWith: elapsed)
    waitForExpectations(timeout: 5)
    timer.tap()
    let toggle = app.buttons["playback-toggle"]
    expectation(for: NSPredicate(format: "value == %@", "In pausa"), evaluatedWith: toggle)
    waitForExpectations(timeout: 5)
  }

  @MainActor
  func testKaraokeFollowsMediaAndResumesAfterManualBrowsing() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-karaoke"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 15))
    if toggle.value as? String == "Riproduzione attiva" { toggle.tap() }
    app.buttons["toggle-lyrics"].tap()
    app.buttons["Espandi testo"].tap()
    let first = app.buttons["lyric-line-0"].firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 5))
    first.tap()
    let scroll = app.scrollViews["synchronized-lyrics-scroll"].firstMatch
    XCTAssertTrue(scroll.waitForExistence(timeout: 5))
    scroll.swipeUp()
    scroll.swipeUp()
    let resume = app.buttons["lyrics-resume-follow"].firstMatch
    XCTAssertTrue(resume.waitForExistence(timeout: 5), app.debugDescription)
    // Manual browsing must not trigger a seek or immediately snap back to the active line.
    XCTAssertTrue(resume.exists)
    resume.tap()
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: first)
        ], timeout: 5), .completed)
    XCTAssertFalse(resume.exists)
    XCTAssertEqual(first.value as? String, "Riga in riproduzione")
    app.buttons["Chiudi"].firstMatch.tap()
    XCTAssertEqual(toggle.value as? String, "In pausa")
    toggle.tap()
    app.buttons["Espandi testo"].tap()
    let nextLine = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier != %@ AND value == %@",
        "lyric-line-", "lyric-line-0", "Riga in riproduzione")
    ).firstMatch
    XCTAssertTrue(nextLine.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(nextLine.isHittable)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Karaoke parole e riga sincronizzate"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["Chiudi"].firstMatch.tap()
    toggle.tap()
  }

  @MainActor
  func testNativeAudioRecoversSameTrackAndPositionAfterResourceFailure() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-audio-recovery"]
    app.launch()
    let elapsed = app.staticTexts["playback-elapsed"]
    XCTAssertTrue(elapsed.waitForExistence(timeout: 15))
    let recovery = app.staticTexts["test-audio-recovery-count"]
    XCTAssertTrue(recovery.waitForExistence(timeout: 5))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
              (Double(elapsed.value as? String ?? "") ?? 0) > 9
                && recovery.label == "1"
            }, object: elapsed)
        ], timeout: 20), .completed, app.debugDescription)
    XCTAssertTrue(app.staticTexts["Brano locale 1"].firstMatch.exists)
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "Riproduzione attiva")
    app.buttons["playback-toggle"].tap()
  }

  @MainActor
  func testRestoredSessionKeepsPositionAndQueuePaused() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-session"]
    app.launch()
    let elapsed = app.staticTexts["playback-elapsed"]
    XCTAssertTrue(elapsed.waitForExistence(timeout: 15))
    expectation(
      for: NSPredicate { _, _ in Int(elapsed.value as? String ?? "0") ?? 0 >= 3 },
      evaluatedWith: elapsed)
    waitForExpectations(timeout: 10)
    app.buttons["playback-toggle"].tap()
    let before = Int(elapsed.value as? String ?? "0") ?? 0
    XCUIDevice.shared.press(.home)
    app.terminate()
    app.launchArguments.append("--test-restore-session")
    app.launch()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 15))
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
    XCTAssertLessThanOrEqual(
      abs((Int(app.staticTexts["playback-elapsed"].value as? String ?? "0") ?? 0) - before), 1)
    app.buttons["show-queue"].tap()
    XCTAssertEqual(app.staticTexts["queue-count"].label, "3 brani")
  }

  @MainActor
  func testAudioSettingsAndRecapImageFromRecordedListening() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback", "--test-session"]
    app.launch()
    let elapsed = app.staticTexts["playback-elapsed"]
    XCTAssertTrue(elapsed.waitForExistence(timeout: 15))
    expectation(
      for: NSPredicate { _, _ in Int(elapsed.value as? String ?? "0") ?? 0 >= 3 },
      evaluatedWith: elapsed)
    waitForExpectations(timeout: 10)
    app.buttons["playback-toggle"].tap()
    app.buttons["close-player"].tap()
    selectTab("Impostazioni", symbol: "gearshape.fill", in: app)
    let audio = app.buttons["open-audio-settings"]
    XCTAssertTrue(audio.waitForExistence(timeout: 5))
    audio.tap()
    XCTAssertTrue(app.switches["effects-enabled"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["open-listening"].tap()
    XCTAssertTrue(app.staticTexts["listening-summary"].waitForExistence(timeout: 5))
    let create = app.buttons["create-recap-image"]
    for _ in 0..<4 where !create.isHittable { app.swipeUp() }
    XCTAssertTrue(create.exists, app.debugDescription)
    create.tap()
    XCTAssertTrue(app.buttons["Condividi immagine"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testOfflineCollectionAndVerseImage() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-local-playback"]
    app.launch()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 15))
    app.buttons["playback-toggle"].tap()
    app.buttons["toggle-lyrics"].tap()
    app.buttons["Espandi testo"].tap()
    let tools = app.buttons["lyrics-tools"].firstMatch
    XCTAssertTrue(tools.waitForExistence(timeout: 5))
    tools.tap()
    XCTAssertTrue(app.switches["lyrics-romanize"].waitForExistence(timeout: 5))
    app.switches["lyrics-romanize"].tap()
    let verse = app.buttons["verse-0"]
    for _ in 0..<3 where !verse.isHittable { app.swipeUp() }
    verse.tap()
    XCTAssertEqual(verse.value as? String, "Selezionato")
    let create = app.buttons["create-verse-image"]
    XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
    create.tap()
    XCTAssertTrue(app.buttons["share-verse-image"].waitForExistence(timeout: 5))
    app.navigationBars["Strumenti testo"].buttons.firstMatch.tap()
    app.buttons["Chiudi"].firstMatch.tap()
    app.buttons["close-player"].tap()
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    app.buttons["library-section-menu"].tap()
    app.buttons["library-menu-offline"].tap()
    XCTAssertTrue(app.staticTexts["offline-count"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["offline-count"].label.contains("brani completi"))
  }

  @MainActor
  private func startFullSearch(_ app: XCUIApplication, fail: Bool = false) {
    app.launchArguments =
      ["--test-full-search", "--test-remote-library"] + (fail ? ["--test-search-failure"] : [])
    app.launch()
    selectTab("Cerca", symbol: "magnifyingglass", in: app)
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    field.tap()
    field.typeText("Prova\n")
    XCTAssertTrue(app.buttons["search-result-songs-search-songs-1"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testFullSearchFiltersPaginationAndPlaybackQueue() {
    let app = XCUIApplication()
    startFullSearch(app)
    app.buttons["search-filter-songs"].tap()
    let more = app.buttons["search-more-songs"]
    for _ in 0..<3 where !more.isHittable { app.swipeUp() }
    XCTAssertTrue(more.waitForExistence(timeout: 5))
    more.tap()
    let last = app.buttons["search-result-songs-search-songs-8"]
    XCTAssertTrue(last.waitForExistence(timeout: 10))
    app.swipeDown()
    app.swipeDown()
    let first = app.buttons["search-result-songs-search-songs-1"]
    XCTAssertTrue(first.exists)
    first.tap()
    XCTAssertTrue(app.buttons["show-queue"].waitForExistence(timeout: 10))
    app.buttons["show-queue"].tap()
    XCTAssertEqual(app.staticTexts["queue-count"].label, "8 brani")
    XCTAssertEqual(app.buttons["queue-search-songs-1"].value as? String, "Brano corrente")
  }

  @MainActor
  func testFullSearchAlbumArtistAndPlaylistNavigation() {
    let app = XCUIApplication()
    startFullSearch(app)
    let filters = app.scrollViews["search-filters"]
    let albumFilter = app.buttons["search-filter-albums"]
    if !albumFilter.isHittable { filters.swipeLeft() }
    albumFilter.tap()
    let album = app.buttons["search-result-albums-MPREsearch-1"]
    XCTAssertTrue(album.waitForExistence(timeout: 10))
    album.tap()
    XCTAssertTrue(app.navigationBars["Prova · Album 1"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()
    let artistFilter = app.buttons["search-filter-artists"]
    if !artistFilter.isHittable { filters.swipeRight() }
    artistFilter.tap()
    let artist = app.buttons["search-result-artists-UCsearch-1"]
    XCTAssertTrue(artist.waitForExistence(timeout: 10))
    artist.tap()
    XCTAssertTrue(app.navigationBars["Prova · Artisti 1"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.firstMatch.tap()
    let playlistFilter = app.buttons["search-filter-playlists"]
    for _ in 0..<3 where !playlistFilter.isHittable { filters.swipeLeft() }
    playlistFilter.tap()
    let playlist = app.buttons["search-result-playlists-VLsearch-playlists-1"]
    XCTAssertTrue(playlist.waitForExistence(timeout: 10))
    playlist.tap()
    XCTAssertTrue(app.buttons["playlist-track-a"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testFullSearchPartialFailureAndDeletableHistory() {
    let app = XCUIApplication()
    startFullSearch(app, fail: true)
    app.buttons["search-category-menu"].tap()
    app.buttons["search-menu-podcasts"].tap()
    XCTAssertTrue(app.buttons["search-retry-podcasts"].waitForExistence(timeout: 10))
    app.buttons["search-category-menu"].tap()
    app.buttons["search-menu-songs"].tap()
    XCTAssertTrue(app.buttons["search-result-songs-search-songs-1"].waitForExistence(timeout: 10))
    let field = app.searchFields.firstMatch
    field.tap()
    let clear = field.buttons.firstMatch
    if clear.exists {
      clear.tap()
    } else {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
    }
    XCTAssertTrue(app.buttons["search-history-Prova"].waitForExistence(timeout: 10))
    app.buttons["search-clear-history"].tap()
    XCTAssertFalse(app.buttons["search-history-Prova"].exists)
  }

  @MainActor
  func testRadioReplacesQueueOnlyAfterServerResponse() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-playback-order", "--test-remote-library", "--test-radio"]
    app.launch()
    openPlayerOptions(app)
    let radio = app.buttons["song-option-radio"]
    if !radio.isHittable { app.swipeUp() }
    radio.tap()
    app.buttons["show-queue"].tap()
    XCTAssertTrue(app.buttons["queue-radio-1"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["queue-order-1"].value as? String, "Brano corrente")
    XCTAssertFalse(app.buttons["queue-order-2"].exists)
    XCTAssertEqual(app.staticTexts["queue-count"].label, "4 brani")
  }

  @MainActor
  func testAutoplayWaitsForManualQueueAndHonorsDisabledSetting() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-playback-order", "--test-remote-library", "--test-radio"]
    app.launch()
    app.buttons["show-queue"].tap()
    app.buttons["radio-test-ended"].tap()
    XCTAssertEqual(app.buttons["queue-order-2"].value as? String, "Brano corrente")
    XCTAssertEqual(app.staticTexts["queue-count"].label, "3 brani")
    app.buttons["radio-test-ended"].tap()
    XCTAssertEqual(app.buttons["queue-order-3"].value as? String, "Brano corrente")
    app.buttons["radio-test-ended"].tap()
    XCTAssertTrue(app.buttons["queue-radio-1"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["queue-count"].label, "6 brani")
    XCTAssertEqual(app.buttons["queue-radio-1"].value as? String, "Brano corrente")
    let automatic = app.switches["queue-autoplay"]
    automatic.tap()
    app.buttons["radio-test-ended"].tap()
    app.buttons["radio-test-ended"].tap()
    app.buttons["radio-test-ended"].tap()
    app.swipeUp()
    XCTAssertEqual(app.buttons["queue-radio-3"].value as? String, "Brano corrente")
    XCTAssertEqual(app.staticTexts["queue-count"].label, "6 brani")
  }

  @MainActor
  func testPauseWhileWaitingForRecommendationsDoesNotStartPlayback() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-playback-order", "--test-remote-library", "--test-radio", "--test-radio-slow",
    ]
    app.launch()
    app.buttons["show-queue"].tap()
    app.buttons["radio-test-ended"].tap()
    app.buttons["radio-test-ended"].tap()
    app.buttons["radio-test-ended"].tap()
    app.buttons["radio-test-pause"].tap()
    let loading = app.descendants(matching: .any)["radio-loading"]
    XCTAssertTrue(loading.waitForExistence(timeout: 2))
    let finished = NSPredicate(format: "exists == false")
    expectation(for: finished, evaluatedWith: loading)
    waitForExpectations(timeout: 12)
    XCTAssertEqual(app.staticTexts["queue-count"].label, "3 brani")
    XCTAssertEqual(app.buttons["queue-order-3"].value as? String, "Brano corrente")
    XCTAssertFalse(app.buttons["queue-radio-1"].exists)
  }

  @MainActor
  func testRadioFailureKeepsExistingQueue() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-playback-order", "--test-remote-library", "--test-radio", "--test-radio-failure",
    ]
    app.launch()
    openPlayerOptions(app)
    let radio = app.buttons["song-option-radio"]
    if !radio.isHittable { app.swipeUp() }
    radio.tap()
    XCTAssertTrue(app.alerts["Radio musicale"].waitForExistence(timeout: 10))
    app.alerts.buttons["OK"].tap()
    app.buttons["show-queue"].tap()
    XCTAssertEqual(app.staticTexts["queue-count"].label, "3 brani")
    XCTAssertEqual(app.buttons["queue-order-1"].value as? String, "Brano corrente")
  }

  @MainActor
  func testCarPlayAlbumFooterTraversesEveryPageAndReturnsFromPartialLastPage() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-remote-library", "--test-carplay-album-pages"]
    app.launch()
    let result = app.staticTexts["carplay-album-page-qa"]
    XCTAssertTrue(result.waitForExistence(timeout: 15))
    let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "true:3:true:true"), object: result)
    XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
  }

  @MainActor
  func testOldFavouriteSongsAndEveryAlbumTrackMigrateIntoYouTubeLikes() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-remote-library", "--test-favorites-migration"]
    app.launch()
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    app.buttons["library-section-likes"].tap()
    XCTAssertTrue(app.buttons["song-legacy-song"].waitForExistence(timeout: 15))
    for number in 1...3 {
      XCTAssertTrue(app.buttons["song-legacy-album-\(number)"].waitForExistence(timeout: 10))
    }
    XCTAssertFalse(app.buttons["retry-favorites-migration"].exists)
    XCTAssertFalse(app.buttons["library-section-local"].exists)
    XCTAssertFalse(app.buttons["library-section-favoriteAlbums"].exists)
  }

  @MainActor
  func testRemoteLibraryUsesOnlyYouTubeMusicLikes() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-remote-library"]
    app.launch()
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    XCTAssertTrue(app.staticTexts["Album di prova"].waitForExistence(timeout: 10))
    app.buttons["library-section-songs"].tap()
    let saved = app.buttons["song-saved-fixture"]
    XCTAssertTrue(saved.waitForExistence(timeout: 10))
    saved.press(forDuration: 1.1)
    app.buttons["Mi piace su YouTube Music"].tap()
    app.buttons["library-section-likes"].tap()
    XCTAssertTrue(app.buttons["song-saved-fixture"].waitForExistence(timeout: 10))
    let liked = app.buttons["song-liked-fixture"]
    XCTAssertTrue(liked.exists)
    liked.press(forDuration: 1.1)
    app.buttons["Rimuovi Mi piace da YouTube Music"].tap()
    XCTAssertFalse(app.buttons["song-liked-fixture"].waitForExistence(timeout: 2))
    let chips = app.scrollViews.firstMatch
    chips.swipeLeft()
    app.buttons["library-section-playlists"].tap()
    XCTAssertTrue(app.staticTexts["Playlist di prova"].waitForExistence(timeout: 10))
    app.buttons["library-section-artists"].tap()
    XCTAssertTrue(app.staticTexts["Artista seguito di prova"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["library-section-local"].exists)
    XCTAssertFalse(app.buttons["library-section-favoriteAlbums"].exists)
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Unica raccolta Mi piace YouTube Music"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testRejectedRemoteLikeShowsErrorAndKeepsLikedSong() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-remote-library", "--test-like-failure"]
    app.launch()
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    app.buttons["library-section-likes"].tap()
    let liked = app.buttons["song-liked-fixture"]
    XCTAssertTrue(liked.waitForExistence(timeout: 10))
    liked.press(forDuration: 1.1)
    app.buttons["Rimuovi Mi piace da YouTube Music"].tap()
    XCTAssertTrue(app.alerts["Sincronizzazione YouTube Music"].waitForExistence(timeout: 10))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(liked.exists)
  }
  @MainActor
  func testPlaylistRenameAndRemoveWithoutChangingLocalFavorites() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-remote-library"]
    app.launch()
    selectTab("Libreria", symbol: "square.stack.fill", in: app)
    app.scrollViews.firstMatch.swipeLeft()
    app.buttons["library-section-playlists"].tap()
    app.buttons["library-item-VLfixture"].tap()
    let track = app.buttons["playlist-track-b"]
    XCTAssertTrue(track.waitForExistence(timeout: 10))
    track.press(forDuration: 1.1)
    app.buttons["Rimuovi dalla playlist"].tap()
    XCTAssertFalse(track.waitForExistence(timeout: 2))
    app.buttons["Opzioni playlist"].tap()
    app.buttons["Rinomina"].tap()
    let alert = app.alerts["Rinomina playlist"]
    let field = alert.textFields.firstMatch
    field.tap()
    field.press(forDuration: 1.1)
    if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
    // Selecting and replacing via keyboard is stable on both simulator keyboard settings.
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "Playlist rinominata")
    alert.buttons["Salva"].tap()
    XCTAssertTrue(app.navigationBars["Playlist rinominata"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testShuffleRepeatAndQueueControls() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-playback-order", "--test-remote-library"]
    app.launch()
    let shuffle = app.buttons["playback-shuffle"]
    XCTAssertTrue(shuffle.waitForExistence(timeout: 10))
    XCTAssertEqual(shuffle.value as? String, "Disattivata")
    shuffle.tap()
    XCTAssertEqual(shuffle.value as? String, "Attiva")
    let repeatButton = app.buttons["playback-repeat"]
    repeatButton.tap()
    XCTAssertEqual(repeatButton.value as? String, "Ripeti coda")
    repeatButton.tap()
    XCTAssertEqual(repeatButton.value as? String, "Ripeti brano")
    repeatButton.tap()
    XCTAssertEqual(repeatButton.value as? String, "Ripetizione disattivata")
    app.buttons["show-queue"].tap()
    for id in 1...3 { XCTAssertTrue(app.buttons["queue-order-\(id)"].exists) }
  }

  @MainActor
  func testAddingDuplicateSongsAndRemovingUpcomingDoesNotRestartCurrent() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-playback-order", "--test-remote-library"]
    app.launch()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(toggle.value as? String, "In pausa")
    app.buttons["Altre opzioni"].tap()
    app.buttons["Aggiungi alla coda"].tap()
    XCTAssertEqual(toggle.value as? String, "In pausa")
    app.buttons["Altre opzioni"].tap()
    app.buttons["Riproduci dopo"].tap()
    XCTAssertEqual(toggle.value as? String, "In pausa")
    app.buttons["show-queue"].tap()
    XCTAssertEqual(app.staticTexts["queue-count"].label, "5 brani")
    XCTAssertEqual(app.buttons.matching(identifier: "queue-order-1").count, 3)
    let upcoming = app.buttons["queue-order-3"]
    upcoming.press(forDuration: 1.1)
    app.buttons["Rimuovi dalla coda"].tap()
    XCTAssertFalse(upcoming.waitForExistence(timeout: 2))
    XCTAssertEqual(app.staticTexts["queue-count"].label, "4 brani")
    XCTAssertEqual(app.buttons.matching(identifier: "queue-order-1").count, 3)
    app.buttons["Chiudi"].tap()
    XCTAssertEqual(toggle.value as? String, "In pausa")
  }

  @MainActor
  func testReorderingQueuePreservesCurrentOccurrenceAndShuffleState() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-playback-order", "--test-remote-library"]
    app.launch()
    let shuffle = app.buttons["playback-shuffle"]
    XCTAssertTrue(shuffle.waitForExistence(timeout: 10))
    shuffle.tap()
    app.buttons["show-queue"].tap()
    let edit = app.buttons["Edit"].exists ? app.buttons["Edit"] : app.buttons["Modifica"]
    edit.tap()
    let source = app.cells.containing(.button, identifier: "queue-order-3").firstMatch
    let target = app.cells.containing(.button, identifier: "queue-order-1").firstMatch
    source.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).press(
      forDuration: 1.0,
      thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.1)))
    let current = app.buttons["queue-order-1"]
    XCTAssertEqual(current.value as? String, "Brano corrente")
    XCTAssertLessThan(app.buttons["queue-order-3"].frame.minY, current.frame.minY)
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-order-")).count, 3
    )
    app.buttons["Chiudi"].tap()
    XCTAssertEqual(shuffle.value as? String, "Attiva")
    XCTAssertEqual(app.buttons["playback-toggle"].value as? String, "In pausa")
  }

  @MainActor
  func testRemovingLastQueueItemDismissesPlayer() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-playback-order", "--test-remote-library"]
    app.launch()
    XCTAssertTrue(app.buttons["show-queue"].waitForExistence(timeout: 10))
    app.buttons["show-queue"].tap()
    for index in [3, 2, 1] {
      let cell = app.cells.containing(.button, identifier: "queue-order-\(index)").firstMatch
      XCTAssertTrue(cell.waitForExistence(timeout: 5))
      cell.swipeLeft()
      let delete = app.buttons["Delete"].exists ? app.buttons["Delete"] : app.buttons["Elimina"]
      XCTAssertTrue(delete.waitForExistence(timeout: 5))
      delete.tap()
    }
    XCTAssertFalse(app.buttons["open-player"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["playback-toggle"].exists)
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  @MainActor func testDedicatedDiscoveryAndVerifiedAISuggestions() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-discovery-extras", "--test-remote-library", "--test-local-playback", "--test-session",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["close-player"].waitForExistence(timeout: 20))
    app.buttons["close-player"].tap()
    selectTab("Home", symbol: "house.fill", in: app)
    let menu = app.buttons["discovery-menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10))
    menu.tap()
    app.buttons["open-charts"].tap()
    XCTAssertTrue(app.staticTexts["Brano di classifica"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["charts-country"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    menu.tap()
    app.buttons["open-podcasts"].tap()
    XCTAssertTrue(app.staticTexts["Podcast di prova"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["podcasts-search"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    menu.tap()
    app.buttons["open-mixes"].tap()
    XCTAssertTrue(app.staticTexts["Brano di classifica"].waitForExistence(timeout: 10))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    menu.tap()
    app.buttons["open-ai-suggestions"].tap()
    let request = app.textFields["ai-music-request"]
    let multiline = app.textViews["ai-music-request"]
    let field = request.exists ? request : multiline
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.tap()
    field.typeText("Rock per un viaggio")
    app.buttons["generate-ai-music"].tap()
    XCTAssertTrue(app.staticTexts["Brano suggerito"].waitForExistence(timeout: 10))
    app.swipeUp()
    XCTAssertTrue(app.buttons["play-ai-suggestions"].waitForExistence(timeout: 5))
    app.buttons["play-ai-suggestions"].tap()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Brano suggerito"].exists)
  }

  @MainActor func testHomeWidgetInteractivePlayback() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-local-playback", "--test-long-local", "--test-session", "--test-remote-library",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 20))
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let icon = springboard.icons["NoteNarrate"].firstMatch
    XCTAssertTrue(icon.waitForExistence(timeout: 10))
    icon.press(forDuration: 1.5)
    let medium = springboard.buttons["Widget medio"]
    XCTAssertTrue(medium.waitForExistence(timeout: 10))
    medium.tap()
    XCUIDevice.shared.press(.home)
    let pause = springboard.buttons["Pausa"]
    XCTAssertTrue(pause.waitForExistence(timeout: 20), springboard.debugDescription)
    let screenshot = XCTAttachment(screenshot: springboard.screenshot())
    screenshot.name = "NoteNarrate Player widget"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    pause.tap()
    app.activate()
    let toggle = app.buttons["playback-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "In pausa"), object: toggle)
        ], timeout: 8), .completed)
    XCUIDevice.shared.press(.home)
    let play = springboard.buttons["Riproduci"]
    XCTAssertTrue(play.waitForExistence(timeout: 15))
    play.tap()
    app.activate()
    waitForPlayback(toggle)
    toggle.tap()
  }

  @MainActor func testFollowedArtistsReleaseBaselineAndNewNotice() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-discovery-extras", "--test-remote-library"]
    app.launch()
    selectTab("Home", symbol: "house.fill", in: app)
    XCTAssertTrue(app.buttons["discovery-menu"].waitForExistence(timeout: 10))
    app.buttons["discovery-menu"].tap()
    app.buttons["open-artist-releases"].tap()
    XCTAssertTrue(app.staticTexts["Artista seguito di prova"].waitForExistence(timeout: 10))
    let toggle = app.switches["release-alerts-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    addUIInterruptionMonitor(withDescription: "Notifications permission") { alert in
      let button = alert.buttons.matching(
        NSPredicate(format: "label IN %@", ["Allow", "Consenti", "Consenti notifiche"])
      ).firstMatch
      if button.exists {
        button.tap()
        return true
      }
      return false
    }
    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.buttons.matching(
      NSPredicate(format: "label IN %@", ["Allow", "Consenti", "Consenti notifiche"])
    ).firstMatch
    if allow.waitForExistence(timeout: 4) { allow.tap() }
    XCTAssertTrue(app.buttons["check-releases"].waitForExistence(timeout: 15))
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: app.buttons["check-releases"]
          )
        ], timeout: 15), .completed, app.debugDescription)
    XCTAssertFalse(app.staticTexts["Nuova uscita di prova"].exists)
    app.buttons["check-releases"].tap()
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Nuova uscita di prova"].waitForExistence(timeout: 12))
    // Disable the preference again; the test must not leave background notifications enabled.
    app.swipeDown()
    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
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
    app.buttons["search-filter-songs"].tap()
  }

  @MainActor
  private func findReferenceSong(in app: XCUIApplication) -> XCUIElement {
    let song = app.buttons["search-result-songs-ZmzqqdVFw8g"]
    let first = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "search-result-songs-")
    )
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
    let song = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "search-result-songs-")
    )
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
  func testArtworkLyricsAndQueue() {
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
    XCTAssertFalse(app.buttons["toggle-video"].exists)
    XCTAssertEqual(toggle.value as? String, "In pausa")
    XCTAssertEqual(Double(elapsed.value as? String ?? "") ?? 0, before, accuracy: 2)
    XCTAssertEqual(toggle.value as? String, "In pausa")
    openPlayerOptions(app)
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
    let nextLyrics = app.staticTexts["song-lyrics"]
    // Another recording may have no lyrics. Both states must discard the previous manual text.
    XCTAssertFalse(nextLyrics.exists && nextLyrics.label.contains("Un ricordo"))
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
    // Isolate the real player/PCM/cache regression from YouTube catalog/CDN availability.
    app.launchArguments = ["--test-local-playback", "--test-long-local", "--test-stream-meaning"]
    app.launch()
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
    // The UI lifecycle must preserve native audio even when external services are unavailable.
    app.launchArguments = ["--test-local-playback", "--test-long-local"]
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
    app.launchArguments = ["--test-local-playback", "--test-carplay-meaning", "--test-meaning"]
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
      "--test-local-playback", "--test-carplay-meaning", "--test-meaning",
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

  @MainActor
  func testCollectionListIndexJumpAndPreferencesSurviveRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = [
      "--test-remote-library", "--test-collection-presentation",
      "--test-reset-collection-preferences",
    ]
    app.launch()
    app.tabBars.buttons["Libreria"].tap()
    XCTAssertTrue(
      app.scrollViews["collection-grid"].waitForExistence(timeout: 12), app.debugDescription)
    app.buttons["collection-options"].tap()
    app.buttons["Lista"].tap()
    XCTAssertTrue(app.scrollViews["collection-list"].waitForExistence(timeout: 5))
    app.buttons["collection-options"].tap()
    app.buttons["collection-toggle-index"].tap()
    let index = app.scrollViews["collection-alphabet"]
    XCTAssertTrue(index.waitForExistence(timeout: 5))
    let z = app.buttons["collection-index-Z"]
    // Off-screen SwiftUI buttons can have no activation point; expose the end first.
    for _ in 0..<6 { index.swipeLeft() }
    XCTAssertTrue(z.isHittable, app.debugDescription)
    z.tap()
    XCTAssertTrue(app.buttons["album-MPREcollection-25"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["album-MPREcollection-25"].isHittable)
    app.terminate()
    app.launchArguments.removeAll { $0 == "--test-reset-collection-preferences" }
    app.launch()
    app.tabBars.buttons["Libreria"].tap()
    XCTAssertTrue(app.scrollViews["collection-list"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.scrollViews["collection-alphabet"].exists)
    let proof = XCTAttachment(screenshot: app.screenshot())
    proof.name = "Library list and alphabet"
    proof.lifetime = .keepAlways
    add(proof)
    app.buttons["library-section-menu"].tap()
    app.buttons["library-menu-songs"].tap()
    XCTAssertTrue(app.buttons["song-saved-fixture"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.scrollViews["collection-alphabet"].exists)
  }

  @MainActor
  func testRealShareExtensionReceivesNowPlayingThenSearchesInApp() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-shared-music", "--test-full-search"]
    app.launch()
    let share = app.buttons["test-share-sheet"]
    XCTAssertTrue(share.waitForExistence(timeout: 10))
    share.tap()
    let activity = app.cells.matching(NSPredicate(format: "label == %@", "NoteNarrate")).firstMatch
    if !activity.waitForExistence(timeout: 8) {
      let more = app.buttons["More"]
      if more.exists { more.tap() }
      let altro = app.buttons["Altro"]
      if altro.exists { altro.tap() }
    }
    XCTAssertTrue(activity.waitForExistence(timeout: 8), app.debugDescription)
    activity.tap()
    let save = app.buttons["share-save"]
    XCTAssertTrue(save.waitForExistence(timeout: 12), app.debugDescription)
    save.tap()
    let done = app.buttons["share-done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
    done.tap()
    app.terminate()
    app.launch()
    let search = app.buttons["shared-search"]
    XCTAssertTrue(search.waitForExistence(timeout: 12), app.debugDescription)
    XCTAssertEqual(app.textFields["shared-search-query"].value as? String, "Heroes David Bowie")
    let proof = XCTAttachment(screenshot: app.screenshot())
    proof.name = "Received Now Playing song"
    proof.lifetime = .keepAlways
    add(proof)
    search.tap()
    let result = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "search-result-songs-")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
    result.tap()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 8), app.debugDescription)
  }

  @MainActor
  func testRealShareExtensionReceivesYouTubeURLAndOpensExactTrack() {
    let app = XCUIApplication()
    app.launchArguments = ["--test-shared-music", "--test-shared-link", "--test-full-search"]
    app.launch()
    app.buttons["test-share-sheet"].tap()
    let activity = app.cells.matching(NSPredicate(format: "label == %@", "NoteNarrate")).firstMatch
    XCTAssertTrue(activity.waitForExistence(timeout: 10), app.debugDescription)
    activity.tap()
    XCTAssertTrue(app.buttons["share-save"].waitForExistence(timeout: 10))
    app.buttons["share-save"].tap()
    XCTAssertTrue(app.buttons["share-done"].waitForExistence(timeout: 5))
    app.buttons["share-done"].tap()
    let play = app.buttons["shared-play"]
    XCTAssertTrue(play.waitForExistence(timeout: 10), app.debugDescription)
    play.tap()
    XCTAssertTrue(app.buttons["playback-toggle"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.staticTexts["Heroes"].exists)
  }

}

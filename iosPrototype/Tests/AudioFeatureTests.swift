import XCTest

@testable import PrototypeCore

final class AudioFeatureTests: XCTestCase {
  func testEqualizerChangesFrequencyResponseWithoutClipping() {
    var settings = AudioEffects()
    settings.enabled = true
    settings.gains[5] = 9
    let enhanced = EffectsDSP(settings: settings, rate: 48000, channels: 2)
    let flat = EffectsDSP(settings: AudioEffects(), rate: 48000, channels: 2)
    var a = 0.0
    var b = 0.0
    for i in 0..<24000 {
      let x = Float(sin(Double(i) * 2 * .pi * 1000 / 48000) * 0.1)
      let left = enhanced.process(x, channel: 0)
      let right = enhanced.process(0, channel: 1)
      XCTAssertTrue(left.isFinite && abs(left) <= 1)
      XCTAssertEqual(right, 0)
      if i > 2000 {
        a += Double(left * left)
        let plain = flat.process(x, channel: 0)
        b += Double(plain * plain)
      }
    }
    // Automatic -9 dB headroom compensates the boosted 1 kHz peak. An off-band signal is attenuated.
    XCTAssertEqual(sqrt(a / b), 1, accuracy: 0.03)
    let bass = EffectsDSP(settings: settings, rate: 48000, channels: 1)
    var energy = 0.0
    for i in 0..<24000 {
      let x = Float(sin(Double(i) * 2 * .pi * 100 / 48000) * 0.1)
      let y = bass.process(x, channel: 0)
      if i > 2000 { energy += Double(y * y) }
    }
    XCTAssertLessThan(energy / a, 0.3)
  }
  func testDelayAndReverbHaveTailsAndBypassIsExact() {
    var settings = AudioEffects()
    settings.enabled = true
    settings.delay = 0.4
    settings.reverb = 0.3
    settings.delaySeconds = 0.1
    let processor = EffectsDSP(settings: settings, rate: 10000, channels: 1)
    let output = (0..<10000).map { processor.process($0 == 0 ? 0.5 : 0, channel: 0) }
    XCTAssertGreaterThan(abs(output[1000]), 0.1)
    XCTAssertTrue(output[2000...].contains { abs($0) > 0.00001 })
    let flat = EffectsDSP(settings: AudioEffects(), rate: 48000, channels: 1)
    XCTAssertEqual(flat.process(0.123, channel: 0), 0.123)
    XCTAssertEqual(flat.process(.nan, channel: 0), 0)
  }
  func testDJSweepAttenuatesOutgoingTrebleAndIncomingBass() {
    func energy(frequency: Double, progress: Double?, incoming: Bool) -> Double {
      let filter = DJSweep()
      filter.configure(progress: progress, incoming: incoming, rate: 48000)
      var total = 0.0
      for index in 0..<4800 {
        let x = Float(sin(Double(index) * 2 * .pi * frequency / 48000) * 0.2)
        let y = filter.process(x, channel: 0)
        if index > 200 { total += Double(y * y) }
      }
      return total
    }
    XCTAssertLessThan(
      energy(frequency: 8000, progress: 1, incoming: false),
      energy(frequency: 8000, progress: nil, incoming: false) * 0.1)
    XCTAssertLessThan(
      energy(frequency: 100, progress: 0, incoming: true),
      energy(frequency: 100, progress: nil, incoming: true) * 0.1)
  }
  func testAutoEqRequiresAllCentresUniqueAndValidQ() throws {
    let profile =
      "Preamp: -5 dB\n"
      + AudioEffects.frequencies.enumerated().map {
        "Filter \($0.offset + 1): ON PK Fc \($0.element) Hz Gain 2 dB Q 1.41"
      }.joined(separator: "\n")
    let result = try AudioEffects.autoEq(profile)
    XCTAssertEqual(result.gains, [Double](repeating: 2, count: 10))
    XCTAssertEqual(result.preamp, -5)
    XCTAssertThrowsError(
      try AudioEffects.autoEq(
        profile.components(separatedBy: .newlines).dropLast().joined(separator: "\n")))
    XCTAssertThrowsError(
      try AudioEffects.autoEq(profile.replacingOccurrences(of: "Q 1.41", with: "Q 4")))
    XCTAssertThrowsError(
      try AudioEffects.autoEq(profile.replacingOccurrences(of: "16000.0", with: "8000.0")))
  }
  func testCrossfadeEndpointsPowerAndDJCurve() {
    for dj in [false, true] {
      XCTAssertEqual(CrossfadeCurve.gains(progress: 0, dj: dj).outgoing, 1)
      XCTAssertEqual(CrossfadeCurve.gains(progress: 1, dj: dj).incoming, 1)
      for step in 0...100 {
        let pair = CrossfadeCurve.gains(progress: Double(step) / 100, dj: dj)
        XCTAssertEqual(
          pair.outgoing * pair.outgoing + pair.incoming * pair.incoming, 1, accuracy: 0.00001)
      }
    }
    XCTAssertLessThan(
      CrossfadeCurve.gains(progress: 0.2, dj: true).incoming,
      CrossfadeCurve.gains(progress: 0.2, dj: false).incoming)
  }
  func testTTMLPreservesWordTimesAndDecodesEntities() throws {
    let xml =
      "<tt><body><div><p begin=\"00:01.000\" end=\"00:03.000\"><span begin=\"1.0s\" end=\"1.5s\">Hello </span><span begin=\"1.6s\" end=\"2.9s\">you &amp; me</span></p></div></body></tt>"
    let timeline = LyricsTimeline(lrc: try TTMLLyrics.lrc(xml))
    XCTAssertEqual(timeline.lines.count, 1)
    XCTAssertEqual(timeline.lines[0].text, "Hello you & me")
    XCTAssertEqual(timeline.lines[0].words.map(\.time), [1, 1.6])
    XCTAssertThrowsError(try TTMLLyrics.lrc("<broken>"))
  }
  func testAutoEqIndexPathAndProfileAreBoundToOfficialHost() {
    let entries = AutoEqEntry.parse(
      "- [Headphone](./Maker/GRAS/Headphone) by Maker on GRAS\n- [Bad](../secret) by Someone")
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries[0].profileURL?.host, "raw.githubusercontent.com")
    XCTAssertTrue(entries[0].profileURL!.absoluteString.hasSuffix("Headphone%20FixedBandEQ.txt"))
  }
  @MainActor func testListeningExcludesSeeksPausedTimeAndNarrationThenSurvivesRelaunch() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let history = ListeningHistory(url: url)
    let token = UUID()
    let now = Date(timeIntervalSince1970: 100000)
    let track = PlaybackTrack(
      id: "one", title: "Song", artist: "Artist", artwork: nil, durationSeconds: 180,
      albumTitle: "Album")
    for i in 0...35 {
      history.sample(
        track: track, token: token, position: Double(i), duration: 180, playing: true,
        now: now.addingTimeInterval(Double(i)))
    }
    history.sample(
      track: track, token: token, position: 120, duration: 180, playing: true,
      now: now.addingTimeInterval(36))
    history.sample(
      track: track, token: token, position: 120, duration: 180, playing: false,
      now: now.addingTimeInterval(37))
    history.sample(
      track: track, token: token, position: 121, duration: 180, playing: true,
      now: now.addingTimeInterval(50))
    history.sample(
      track: track, token: token, position: 122, duration: 180, playing: true,
      now: now.addingTimeInterval(51))
    history.save()
    let restored = ListeningHistory(url: url)
    let report = restored.report()
    XCTAssertEqual(report.seconds, 36, accuracy: 0.001)
    XCTAssertEqual(report.plays, 1)
    XCTAssertEqual(report.artists.first?.title, "Artist")
    XCTAssertEqual(report.albums.first?.title, "Album")
    XCTAssertEqual(restored.periods(.month).count, 1)
    XCTAssertEqual(
      restored.report(in: DateInterval(start: now.addingTimeInterval(3600), duration: 3600))
        .seconds, 0)
    restored.clear()
    XCTAssertTrue(ListeningHistory(url: url).entries.isEmpty)
  }
  @MainActor func testShortTrackCountsAfterHalfAndMonthlyRecapHasOnlyActualListening() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let history = ListeningHistory(url: url)
    let token = UUID()
    let now = Date(timeIntervalSince1970: 100000)
    let track = PlaybackTrack(id: "short", title: "Short", artist: "One", artwork: nil)
    for i in 0...10 {
      history.sample(
        track: track, token: token, position: Double(i), duration: 20, playing: true,
        now: now.addingTimeInterval(Double(i)))
    }
    XCTAssertEqual(history.report().plays, 1)
    XCTAssertEqual(history.report().days, 1)
    XCTAssertTrue(history.report().shareText.contains("Short"))
    XCTAssertEqual(history.periods(.year).count, 1)
  }
}

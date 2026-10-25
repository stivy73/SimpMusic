import AVFoundation
import XCTest

@testable import PrototypeCore

final class LocalPlaybackTests: XCTestCase {
  func testIncompleteHTTPTransferNeverCertifiesOffline() throws {
    XCTAssertThrowsError(
      try OfflineValidation.byteCount(actual: 1_048_576, expected: 4_000_000, status: 200))
    XCTAssertThrowsError(
      try OfflineValidation.byteCount(
        actual: 4096, expected: nil, status: 206, contentRange: "bytes 0-4095/8000"))
    XCTAssertThrowsError(try OfflineValidation.byteCount(actual: 4096, expected: 4096, status: 403))
    XCTAssertNoThrow(
      try OfflineValidation.byteCount(
        actual: 4096, expected: 4096, status: 206, contentRange: "bytes 0-4095/4096"))
  }
  @MainActor func testOfflineReadySurvivesRelaunchAndMissingFileIsRejected() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("audio.m4a")
    try Self.audioFixture(source)
    let store = OfflineLibrary(directory: root.appendingPathComponent("collection"))
    let track = PlaybackTrack(
      id: "../../../test", title: "Fixture", artist: "Local", artwork: nil, durationSeconds: 4)
    store.begin(track)
    try await store.finish(track.id, temporary: source, status: 200, contentRange: nil)
    XCTAssertEqual(store.ready.count, 1)
    let file = try XCTUnwrap(store.url(for: track.id))
    XCTAssertEqual(file.deletingLastPathComponent().path, store.directory.path)
    XCTAssertEqual(OfflineLibrary(directory: store.directory).ready.count, 1)
    try FileManager.default.removeItem(at: file)
    let restored = OfflineLibrary(directory: store.directory)
    XCTAssertTrue(restored.ready.isEmpty)
    XCTAssertEqual(restored.records.first?.state, .failed)
  }
  func testInvalidAudioAndWrongDurationRejected() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    try Self.audioFixture(url)
    let duration = try await OfflineValidation.playableFile(url, expectedDuration: 4)
    XCTAssertEqual(duration, 4, accuracy: 0.2)
    do {
      _ = try await OfflineValidation.playableFile(url, expectedDuration: 180)
      XCTFail("Wrong duration accepted")
    } catch {}
    try Data(repeating: 0, count: 5000).write(to: url)
    do {
      _ = try await OfflineValidation.playableFile(url, expectedDuration: nil)
      XCTFail("Invalid audio accepted")
    } catch {}
  }
  @MainActor func testQuotaIsCheckedAtCommitAndPartialFileDoesNotBecomeReady() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("source.m4a")
    try Self.audioFixture(file)
    let library = OfflineLibrary(directory: root.appendingPathComponent("offline"))
    let track = PlaybackTrack(
      id: "quota", title: "Quota", artist: "Test", artwork: nil, durationSeconds: 4)
    library.begin(track)
    do {
      try await library.finish(
        track.id, temporary: file, status: 200, contentRange: nil, maxBytes: 1)
      XCTFail("Quota exceeded")
    } catch OfflineError.storage {}
    XCTAssertTrue(library.ready.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    let data = try Data(contentsOf: file)
    try data.prefix(data.count / 2).write(to: file)
    do {
      _ = try await OfflineValidation.playableFile(file, expectedDuration: 4)
      XCTFail("Truncated audio accepted")
    } catch {}
  }
  func testSleepTimerUsesAbsoluteDeadlineAndOnlyTrackEndForEndMode() {
    let now = Date(timeIntervalSince1970: 1000)
    let timer = SleepTimer.minutes(15, now: now)
    XCTAssertFalse(timer.expired(now: now.addingTimeInterval(899)))
    XCTAssertTrue(timer.expired(now: now.addingTimeInterval(900)))
    XCTAssertFalse(SleepTimer.endOfTrack.expired(now: .distantFuture))
    XCTAssertTrue(SleepTimer.endOfTrack.expired(trackEnded: true))
  }
  func testSessionRoundTripPreservesDuplicateOccurrencesAndShuffleOrder() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let track = PlaybackTrack(id: "same", title: "Duplicate", artist: "Artist", artwork: nil)
    var sequence = PlaybackSequence()
    sequence.reset(count: 3, selected: 1, shuffle: true)
    sequence.move(from: IndexSet(integer: 2), to: 1)
    let ids = (0..<3).map { _ in UUID() }
    let snapshot = PlaybackSnapshot(
      tracks: [track, track, track], occurrenceIDs: ids, sequence: sequence,
      repeatMode: .all, position: 21, duration: 180, timer: .endOfTrack)
    let store = PlaybackSessionStore(url: url)
    try store.save(snapshot)
    let result = try XCTUnwrap(store.load())
    XCTAssertEqual(result.occurrenceIDs, ids)
    XCTAssertEqual(result.sequence.order, sequence.order)
    XCTAssertEqual(result.position, 21)
    XCTAssertEqual(result.timer, .endOfTrack)
    XCTAssertFalse(
      PlaybackSnapshot(
        tracks: [track], occurrenceIDs: [], sequence: sequence, repeatMode: .off, position: .nan,
        duration: 0
      ).valid)
    try Data("{}".utf8).write(to: url)
    XCTAssertNil(store.load())
  }
  func testLRCLineWordOffsetsAndSeekTargets() {
    let timeline = LyricsTimeline(
      lrc: "[offset:500]\n[00:01.000]<00:01.000>Hello <00:01.500>world\n[00:03][00:04]Again")
    XCTAssertEqual(timeline.lines.map(\.time), [0.5, 2.5, 3.5])
    XCTAssertNil(timeline.current(at: 0.4))
    XCTAssertEqual(timeline.current(at: 1)?.text, "Hello world")
    XCTAssertEqual(timeline.activeWord(in: timeline.lines[0], at: 1), 1)
    XCTAssertEqual(timeline.current(at: 3, delay: 1)?.id, 0)
    XCTAssertNil(timeline.current(at: .nan))
    XCTAssertEqual(LyricsTimeline(lrc: "unsynchronized text").lines.count, 0)
  }
  static func audioFixture(_ url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 176400)!
    buffer.frameLength = buffer.frameCapacity
    for channel in 0..<2 {
      for i in 0..<Int(buffer.frameLength) {
        buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100) * 0.1)
      }
    }
    let file = try AVAudioFile(
      forWriting: url,
      settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128000,
      ], commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
  }
}

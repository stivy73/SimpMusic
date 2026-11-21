import AVFoundation
import XCTest

@testable import PrototypeCore

final class FragmentedOfflineAudioTests: XCTestCase {
  // Four seconds of synthesized silence, AAC in four one-second fMP4 fragments.
  // mvhd, tkhd and mdhd also declare four seconds. AVFoundation can append an
  // empty end marker at eight seconds even though the AAC packets end at four.
  private func fixture() throws -> URL {
    try XCTUnwrap(
      Bundle.module.url(forResource: "four-seconds-fragmented", withExtension: "m4a"))
  }

  @MainActor func testPersistsActualAudioDurationWhenContainerIncludesEmptyTail() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let staged = root.appendingPathComponent("download.m4a")
    try FileManager.default.copyItem(at: fixture(), to: staged)
    let store = OfflineLibrary(directory: root.appendingPathComponent("offline"))
    let track = PlaybackTrack(
      id: "padded-aac", title: "Silence", artist: "Fixture", artwork: nil, durationSeconds: 4)
    store.begin(track)
    try await store.finish(track.id, temporary: staged, status: 200, contentRange: nil)

    let restored = try XCTUnwrap(OfflineLibrary(directory: store.directory).file(for: track.id))
    XCTAssertEqual(try XCTUnwrap(restored.duration), 4, accuracy: 0.06)
    XCTAssertEqual(try Data(contentsOf: restored.url), try Data(contentsOf: fixture()))
  }

  func testNeedsIndependentDurationToAcceptAnEmptyTail() async throws {
    let url = try fixture()
    let reported = try await AVURLAsset(url: url).load(.duration).seconds
    if reported < 4.1 {
      let duration = try await OfflineValidation.playableFile(url, expectedDuration: nil)
      XCTAssertEqual(duration, 4, accuracy: 0.06)
    } else {
      do {
        _ = try await OfflineValidation.playableFile(url, expectedDuration: nil)
        XCTFail("A doubled container duration alone cannot verify this audio")
      } catch OfflineError.incomplete {}
    }
  }

  func testMissingMediaFragmentsCannotBeCertifiedByMovieHeader() async throws {
    let data = try Data(contentsOf: fixture())
    // Keep the first two complete fragments, so the result is still readable.
    let first = try XCTUnwrap(data.firstRange(of: Data("moof".utf8)))
    let second = try XCTUnwrap(data[first.upperBound...].firstRange(of: Data("moof".utf8)))
    let third = try XCTUnwrap(data[second.upperBound...].firstRange(of: Data("moof".utf8)))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.prefix(third.lowerBound - 4).write(to: url)
    do {
      _ = try await OfflineValidation.playableFile(url, expectedDuration: 4)
      XCTFail("The remaining two seconds must not certify a four-second download")
    } catch OfflineError.incomplete {}
  }
}

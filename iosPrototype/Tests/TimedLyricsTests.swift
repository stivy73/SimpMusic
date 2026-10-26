import XCTest

@testable import PrototypeCore

final class TimedLyricsTests: XCTestCase {
  func testWordSweepUsesSourceBoundsAndKeepsPreviousWordsFilled() {
    let timeline = LyricsTimeline(
      lrc: "[00:01]<00:01>Hello <00:02>world<00:03>\n[00:06]Next line")
    let line = timeline.lines[0]
    XCTAssertEqual(timeline.progress(of: line.words[0], in: line, at: 0.99), 0)
    XCTAssertEqual(timeline.progress(of: line.words[0], in: line, at: 1), 0)
    XCTAssertEqual(timeline.progress(of: line.words[0], in: line, at: 1.5), 0.5)
    XCTAssertEqual(timeline.progress(of: line.words[0], in: line, at: 2), 1)
    XCTAssertEqual(timeline.progress(of: line.words[0], in: line, at: 20), 1)
    XCTAssertEqual(timeline.progress(of: line.words[1], in: line, at: 2.5), 0.5)
    // An empty end marker still bounds the final sung word, before the instrumental gap.
    XCTAssertEqual(timeline.progress(of: line.words[1], in: line, at: 3), 1)
  }

  func testPauseSeekAndDelayRecomputeFromMediaPositionWithoutWallClockDrift() {
    let timeline = LyricsTimeline(lrc: "[00:01]<00:01>First <00:03>second\n[00:05]Next")
    let line = timeline.lines[0]
    let word = line.words[0]
    for _ in 0..<50 {
      // A paused or buffering media clock must leave the same partial word visible.
      XCTAssertEqual(timeline.progress(of: word, in: line, at: 2), 0.5)
    }
    XCTAssertEqual(timeline.progress(of: word, in: line, at: 8), 1)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: 1.5), 0.25)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: 0), 0)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: 2.5, delay: 1), 0.25)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: 0.5, delay: -1), 0.25)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: .nan), 0)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: .infinity), 0)
    XCTAssertEqual(timeline.progress(of: word, in: line, at: 2, delay: .nan), 0)
    XCTAssertNil(timeline.activeWord(in: line, at: .infinity))
  }

  func testLineBoundaryAndFinalWordWithoutEndDoNotInventDurations() {
    let timeline = LyricsTimeline(lrc: "[00:01]<00:01>Bounded\n[00:03]<00:03>Last")
    XCTAssertEqual(
      timeline.progress(of: timeline.lines[0].words[0], in: timeline.lines[0], at: 2), 0.5)
    XCTAssertEqual(
      timeline.progress(of: timeline.lines[1].words[0], in: timeline.lines[1], at: 2.9), 0)
    XCTAssertEqual(
      timeline.progress(of: timeline.lines[1].words[0], in: timeline.lines[1], at: 3), 1)
    let plain = LyricsTimeline(lrc: "[00:01]Line only\n[00:03]Next line")
    XCTAssertFalse(plain.hasWords)
    XCTAssertTrue(plain.lines.allSatisfy { $0.words.isEmpty })
  }

  func testRepeatedLinesAndSourceOffsetShiftWordSweepsTogether() {
    let timeline = LyricsTimeline(
      lrc: "[offset:500]\n[00:02][00:08]<00:02>Hello <00:03>again<00:04>")
    XCTAssertEqual(timeline.lines.map(\.time), [1.5, 7.5])
    for (line, position) in zip(timeline.lines, [2.0, 8.0]) {
      XCTAssertEqual(timeline.progress(of: line.words[0], in: line, at: position), 0.5)
    }
    let shared = LyricsTimeline(lrc: "[00:01]<00:01>A<00:01>B<00:03>End")
    XCTAssertEqual(shared.progress(of: shared.lines[0].words[0], in: shared.lines[0], at: 2), 0.5)
    XCTAssertEqual(shared.progress(of: shared.lines[0].words[1], in: shared.lines[0], at: 2), 0.5)
  }
}

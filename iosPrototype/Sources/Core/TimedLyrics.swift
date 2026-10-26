import Foundation

public struct LyricWord: Equatable, Sendable, Identifiable {
  public let id: Int
  public let time: Double
  public let text: String
}
public struct LyricLine: Equatable, Sendable, Identifiable {
  public let id: Int
  public let time: Double
  public let text: String
  public let words: [LyricWord]
}

/// Standard and enhanced LRC. Timestamps come from the provider/file, never estimated by AI.
public struct LyricsTimeline: Equatable, Sendable {
  public let lines: [LyricLine]
  public var hasWords: Bool { lines.contains { !$0.words.isEmpty } }
  public init(lrc: String) {
    let stamp = try! NSRegularExpression(pattern: #"\[(\d+):([0-5]?\d)(?:[.:](\d{1,3}))?\]"#)
    let word = try! NSRegularExpression(pattern: #"<(\d+):([0-5]?\d)(?:[.:](\d{1,3}))?>"#)
    let offsetRegex = try! NSRegularExpression(
      pattern: #"\[offset:([+-]?\d+)\]"#, options: [.caseInsensitive])
    let whole = lrc as NSString
    let offset =
      offsetRegex.firstMatch(in: lrc, range: NSRange(location: 0, length: whole.length))
      .flatMap { Double(whole.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
    func time(_ match: NSTextCheckingResult, _ line: NSString) -> Double {
      let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
      let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0
      let fraction =
        match.range(at: 3).location == NSNotFound
        ? 0 : Double("0." + line.substring(with: match.range(at: 3))) ?? 0
      return max(0, minutes * 60 + seconds + fraction - offset)
    }
    var parsed: [(Double, String, [LyricWord], Int)] = []
    for line in lrc.components(separatedBy: .newlines) {
      let text = line as NSString
      let stamps = stamp.matches(in: line, range: NSRange(location: 0, length: text.length))
      guard let last = stamps.last else { continue }
      let start = last.range.location + last.range.length
      let content = text.substring(from: start)
      let plain = word.stringByReplacingMatches(
        in: content, range: NSRange(location: 0, length: (content as NSString).length),
        withTemplate: ""
      ).trimmingCharacters(in: .whitespaces)
      let words = word.matches(
        in: content, range: NSRange(location: 0, length: (content as NSString).length))
      var timed: [LyricWord] = []
      for (index, match) in words.enumerated() {
        let end =
          index + 1 < words.count ? words[index + 1].range.location : (content as NSString).length
        let from = match.range.location + match.range.length
        let value = (content as NSString).substring(
          with: NSRange(location: from, length: max(0, end - from)))
        timed.append(LyricWord(id: index, time: time(match, content as NSString), text: value))
      }
      for match in stamps {
        let shift = time(match, text) - time(stamps[0], text)
        let shifted = timed.map { LyricWord(id: $0.id, time: $0.time + shift, text: $0.text) }
        parsed.append((time(match, text), plain, shifted, parsed.count))
      }
    }
    parsed.sort { $0.0 == $1.0 ? $0.3 < $1.3 : $0.0 < $1.0 }
    lines = parsed.enumerated().map {
      LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1, words: $0.element.2)
    }
  }
  /// Positive user delay shifts highlighting later without changing the provider's original timing.
  public func current(at seconds: Double, delay: Double = 0) -> LyricLine? {
    guard seconds.isFinite, delay.isFinite else { return nil }
    let position = seconds - delay
    var low = 0
    var high = lines.count
    while low < high {
      let middle = (low + high) / 2
      if lines[middle].time <= position { low = middle + 1 } else { high = middle }
    }
    return low > 0 ? lines[low - 1] : nil
  }
  public func activeWord(in line: LyricLine, at seconds: Double, delay: Double = 0) -> Int? {
    guard seconds.isFinite, delay.isFinite else { return nil }
    return line.words.last { $0.time + delay <= seconds }?.id
  }

  /// Visual progress follows the media position, never elapsed wall time. The next real
  /// word/line timestamp bounds the sweep; an unbounded last word lights up at its start.
  /// This does not manufacture word timing for line-only lyrics.
  public func progress(
    of word: LyricWord, in line: LyricLine, at seconds: Double, delay: Double = 0
  ) -> Double {
    guard seconds.isFinite, delay.isFinite, word.time.isFinite else { return 0 }
    let position = seconds - delay
    guard position >= word.time else { return 0 }
    let nextWord = line.words.lazy.map(\.time).filter { $0 > word.time && $0.isFinite }.min()
    let nextLine = lines.first { $0.time > word.time }?.time
    guard let end = [nextWord, nextLine].compactMap({ $0 }).min(), end.isFinite else {
      return 1
    }
    return min(1, max(0, (position - word.time) / (end - word.time)))
  }
}

import Foundation
import YouTubeSDK

public struct LyricsQuery: Hashable, Sendable {
  public let videoID: String
  public let title: String
  public let artist: String
  public let durationSeconds: Double?

  public init(videoID: String, title: String, artist: String, durationSeconds: Double? = nil) {
    self.videoID = videoID
    self.title = title
    self.artist = artist
    self.durationSeconds = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
  }
}

public struct ResolvedLyrics: Equatable, Sendable {
  public enum Source: String, Sendable {
    case youtube = "YouTube Music"
    case lrclib = "LRCLIB"
  }
  public let text: String
  public let source: Source
  public let sourceURL: URL?
}

public enum LyricsLookupError: LocalizedError {
  case unavailable, rateLimited
  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "Non riesco a cercare il testo online. Controlla la connessione e riprova."
    case .rateLimited:
      "La ricerca del testo è temporaneamente limitata. Attendi e riprova."
    }
  }
}

/// Same alternative catalog used by Android. No AI-generated lyrics or title-only analysis.
public actor LyricsResolver {
  public typealias PrimaryLookup = @Sendable (String) async throws -> String?
  private let primary: PrimaryLookup
  private let session: URLSession
  private var cache: [LyricsQuery: ResolvedLyrics] = [:]
  private var cacheOrder: [LyricsQuery] = []
  private var nextSearchAt = Date.distantPast

  public init(session: URLSession = .shared, primary: PrimaryLookup? = nil) {
    self.session = session
    let music = YouTubeMusicClient()
    self.primary = primary ?? { try await music.getLyrics(videoId: $0) }
  }

  public func resolve(
    _ query: LyricsQuery, force: Bool = false,
    onFallback: @Sendable () async -> Void = {}
  ) async throws -> ResolvedLyrics? {
    try Task.checkCancellation()
    if !force, let cached = cache[query] { return cached }
    if force { cache.removeValue(forKey: query) }
    do {
      let text = try await primary(query.videoID)
      try Task.checkCancellation()
      if let text = Self.usableText(text) {
        return remember(
          ResolvedLyrics(text: text, source: .youtube, sourceURL: nil), for: query)
      }
    } catch {
      try Task.checkCancellation()
      if error is CancellationError { throw error }
      // A failed primary provider must still allow the online fallback.
    }
    try Task.checkCancellation()
    guard !query.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !query.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    await onFallback()
    let title = Self.searchTitle(query.title)
    let artist = Self.searchArtist(query.artist)
    // Search exact metadata first, then remove only technical version suffixes.
    let searches =
      query.title == title && query.artist == artist
      ? [(title, artist)] : [(query.title, query.artist), (title, artist)]
    for (title, artist) in searches {
      let records = try await search(title: title, artist: artist)
      try Task.checkCancellation()
      if let lyrics = Self.select(records, for: query) { return remember(lyrics, for: query) }
    }
    return nil  // Negative results are never cached, so Retry can find newly added lyrics.
  }

  private func remember(_ lyrics: ResolvedLyrics, for query: LyricsQuery) -> ResolvedLyrics {
    cache[query] = lyrics
    cacheOrder.removeAll { $0 == query }
    cacheOrder.append(query)
    while cacheOrder.count > 100 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    return lyrics
  }

  private func search(title: String, artist: String) async throws -> [LrclibRecord] {
    // Honor Retry-After and leave a short gap between sequential fallback searches.
    let delay = nextSearchAt.timeIntervalSinceNow
    if delay > 1 { throw LyricsLookupError.rateLimited }
    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
    try Task.checkCancellation()
    nextSearchAt = Date().addingTimeInterval(0.25)
    var url = URLComponents(string: "https://lrclib.net/api/search")!
    url.queryItems = [
      URLQueryItem(name: "track_name", value: title),
      URLQueryItem(name: "artist_name", value: artist),
    ]
    var request = URLRequest(url: url.url!, timeoutInterval: 10)
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "0.5.1"
    request.setValue(
      "NoteNarrate/\(version) (https://github.com/stivy73/SimpMusic)",
      forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, response) = try await session.data(for: request)
      try Task.checkCancellation()
      guard let response = response as? HTTPURLResponse else {
        throw LyricsLookupError.unavailable
      }
      if response.statusCode == 429 {
        let retry = Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"))
        nextSearchAt = Date().addingTimeInterval(retry)
        throw LyricsLookupError.rateLimited
      }
      if response.statusCode == 404 { return [] }
      guard (200..<300).contains(response.statusCode) else {
        throw LyricsLookupError.unavailable
      }
      return try JSONDecoder().decode(LrclibResponse.self, from: data).records
    } catch {
      try Task.checkCancellation()
      if error is CancellationError || error is LyricsLookupError { throw error }
      throw LyricsLookupError.unavailable
    }
  }

  private static func retryDelay(_ header: String?) -> TimeInterval {
    if let header, let seconds = Double(header), seconds.isFinite { return max(1, seconds) }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let header, let date = formatter.date(from: header) {
      return max(1, date.timeIntervalSinceNow)
    }
    return 60
  }

  static func select(_ records: [LrclibRecord], for query: LyricsQuery) -> ResolvedLyrics? {
    let title = normalized(searchTitle(query.title))
    let artist = normalized(searchArtist(query.artist))
    let matches = records.filter {
      !$0.instrumental && normalized(searchTitle($0.trackName)) == title
        && normalized(searchArtist($0.artistName)) == artist
        && (query.durationSeconds == nil
          || ($0.duration.map { $0.isFinite && abs($0 - query.durationSeconds!) <= 10 } ?? false))
    }.sorted {
      if let duration = query.durationSeconds {
        return abs(($0.duration ?? .infinity) - duration)
          < abs(($1.duration ?? .infinity) - duration)
      }
      // Original metadata wins over a remastered version when both contain lyrics.
      return normalized($0.trackName) == normalized(query.title)
        && normalized($1.trackName) != normalized(query.title)
    }
    for record in matches {
      if let text = usableText(record.plainLyrics) ?? usableText(stripLRC(record.syncedLyrics)) {
        return ResolvedLyrics(
          text: text, source: .lrclib,
          sourceURL: URL(string: "https://lrclib.net/api/get/\(record.id)"))
      }
    }
    return nil
  }

  static func searchTitle(_ title: String) -> String {
    // Keep meaningful subtitles, live/acoustic variants and featured artists intact.
    let suffix =
      #"\s*(?:[\[(](?:(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?|official\s+(?:audio|video|music\s+video)|lyrics|mono|stereo)(?:\s*/\s*remaster(?:ed)?)?[\])]|[-–—]\s*(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?)\s*$"#
    var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
    while true {
      let cleaned = result.replacingOccurrences(
        of: suffix, with: "", options: [.regularExpression, .caseInsensitive])
      if cleaned == result { return result }
      result = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  static func searchArtist(_ artist: String) -> String {
    artist.replacingOccurrences(
      of: #"\s*[-–—]\s*Topic$"#, with: "", options: [.regularExpression, .caseInsensitive]
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalized(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
    )
    .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(
      separator: " ")
  }

  static func usableText(_ text: String?) -> String? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.rangeOfCharacter(from: .letters) != nil,
      ![
        "lyrics not available", "lyrics unavailable", "no lyrics", "instrumental",
        "testo non disponibile",
      ]
      .contains(normalized(trimmed)),
      !trimmed.lowercased().contains("<html")
    else { return nil }
    return trimmed
  }

  static func stripLRC(_ text: String?) -> String? {
    text?.components(separatedBy: .newlines).compactMap { line in
      if line.range(of: #"^\s*\[(?:ar|ti|al|by|offset|length|re|ve):"#, options: .regularExpression)
        != nil
      {
        return nil
      }
      return line.replacingOccurrences(
        of: #"\[\d+:\d+(?:[.:]\d+)?\]|<\d+:\d+(?:[.:]\d+)?>"#, with: "", options: .regularExpression
      )
      .trimmingCharacters(in: .whitespaces)
    }.joined(separator: "\n")
  }
}

struct LrclibRecord: Decodable, Sendable {
  let id: Int
  let trackName: String
  let artistName: String
  let duration: Double?
  let instrumental: Bool
  let plainLyrics: String?
  let syncedLyrics: String?
}

/// The live catalog includes null durations and occasionally incomplete records.
private struct LrclibResponse: Decodable {
  let records: [LrclibRecord]
  init(from decoder: Decoder) throws {
    var array = try decoder.unkeyedContainer()
    var valid: [LrclibRecord] = []
    while !array.isAtEnd {
      let record = try array.superDecoder()
      if let decoded = try? LrclibRecord(from: record) { valid.append(decoded) }
    }
    records = valid
  }
}

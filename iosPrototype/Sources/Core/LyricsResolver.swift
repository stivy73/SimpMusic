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

public struct ResolvedLyrics: Equatable, Codable, Sendable {
  public enum Source: String, Codable, Sendable {
    case youtube = "YouTube Music"
    case lrclib = "LRCLIB"
    case simpMusic = "SimpMusic Lyrics"
    case better = "Better Lyrics"
    case spotify = "Spotify"
    case offline = "Testo salvato"
  }
  public let text: String
  public let source: Source
  public let sourceURL: URL?
  public let syncedText: String?
  public init(text: String, source: Source, sourceURL: URL?, syncedText: String? = nil) {
    self.text = text
    self.source = source
    self.sourceURL = sourceURL
    self.syncedText = syncedText
  }
}

public enum LyricsLookupError: LocalizedError {
  case unavailable, rateLimited, spotifyCredentials
  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "Non riesco a cercare il testo online. Controlla la connessione e riprova."
    case .spotifyCredentials:
      "Inserisci una sessione web Spotify valida negli strumenti del testo. I token Spotify sono separati dalla chiave Gemini."
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
  private let cacheDirectory: URL?
  private let primaryTimeout: Duration
  private var cache: [LyricsQuery: ResolvedLyrics] = [:]
  private var timedCache: [LyricsQuery: ResolvedLyrics] = [:]
  private var cacheOrder: [LyricsQuery] = []
  private var nextSearchAt = Date.distantPast

  public init(
    cacheDirectory: URL? = LocalFiles.directory("Lyrics"), session: URLSession = .shared,
    primary: PrimaryLookup? = nil,
    primaryTimeout: Duration = .seconds(4)
  ) {
    self.cacheDirectory = cacheDirectory
    self.session = session
    self.primaryTimeout = primaryTimeout
    let music = YouTubeMusicClient()
    self.primary = primary ?? { try await music.getLyrics(videoId: $0) }
  }

  public func resolve(
    _ query: LyricsQuery, force: Bool = false, provider: LyricsProviderChoice = .automatic,
    providerToken: String = "", clientToken: String = "",
    onFallback: @Sendable () async -> Void = {}
  ) async throws -> ResolvedLyrics? {
    try Task.checkCancellation()
    if provider == .offline {
      return lyricsFile(query).flatMap { LocalFiles.read(ResolvedLyrics.self, from: $0) }
    }
    if provider == .simpMusic || provider == .better || provider == .spotify {
      if let result = try await ExtraLyrics(session: session).fetch(
        query, provider: provider, token: providerToken, clientToken: clientToken)
      {
        return remember(result, for: query)
      }
      return nil
    }
    if provider == .lrclib {
      if let result = Self.select(
        try await search(
          title: Self.searchTitle(query.title), artist: Self.searchArtist(query.artist)), for: query
      ) {
        return remember(result, for: query)
      }
      return nil
    }
    if !force, let cached = cache[query] { return cached }
    if force { cache.removeValue(forKey: query) }
    do {
      let lookup = primary
      let timeout = primaryTimeout
      let text = try await withThrowingTaskGroup(of: String?.self) { group in
        group.addTask { try await lookup(query.videoID) }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw LyricsLookupError.unavailable
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
      }
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
    if provider == .youtube { return nil }
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

  public func synchronized(_ query: LyricsQuery) async throws -> ResolvedLyrics? {
    if let cached = timedCache[query] { return cached }
    let file = cacheDirectory?.appendingPathComponent(LocalFiles.key(query.videoID) + "-timed.json")
    if let file, let cached = LocalFiles.read(ResolvedLyrics.self, from: file),
      !LyricsTimeline(lrc: cached.syncedText ?? "").lines.isEmpty
    {
      return cached
    }
    if let cached = cache[query], let synced = cached.syncedText,
      !LyricsTimeline(lrc: synced).lines.isEmpty
    {
      return cached
    }
    let records = try await search(
      title: Self.searchTitle(query.title), artist: Self.searchArtist(query.artist))
    if let result = Self.select(
      records.filter { !LyricsTimeline(lrc: $0.syncedLyrics ?? "").lines.isEmpty }, for: query)
    {
      if timedCache.count >= 100 { timedCache.removeAll() }
      timedCache[query] = result
      if let file { try? LocalFiles.write(result, to: file) }
      return result
    }
    return nil
  }

  private func lyricsFile(_ query: LyricsQuery) -> URL? {
    cacheDirectory?.appendingPathComponent(LocalFiles.key(query.videoID) + ".json")
  }
  private func remember(_ lyrics: ResolvedLyrics, for query: LyricsQuery) -> ResolvedLyrics {
    if let file = lyricsFile(query) { try? LocalFiles.write(lyrics, to: file) }
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
    for attempt in 0..<2 {
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
        if attempt == 0 && [408, 500, 502, 503, 504].contains(response.statusCode) {
          try await Task.sleep(for: .milliseconds(350))
          continue
        }
        guard (200..<300).contains(response.statusCode) else { throw LyricsLookupError.unavailable }
        return try JSONDecoder().decode(LrclibResponse.self, from: data).records
      } catch {
        try Task.checkCancellation()
        if let network = error as? URLError, attempt == 0,
          [.timedOut, .networkConnectionLost].contains(network.code)
        {
          try await Task.sleep(for: .milliseconds(350))
          continue
        }
        if error is CancellationError || error is LyricsLookupError { throw error }
        throw LyricsLookupError.unavailable
      }
    }
    throw LyricsLookupError.unavailable
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
          sourceURL: URL(string: "https://lrclib.net/api/get/\(record.id)"),
          syncedText: record.syncedLyrics)
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

  static func normalized(_ value: String) -> String {
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

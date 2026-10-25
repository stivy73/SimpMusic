import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

public enum LyricsProviderChoice: String, CaseIterable, Identifiable, Codable, Sendable {
  case automatic = "Automatico"
  case youtube = "YouTube Music"
  case simpMusic = "SimpMusic Lyrics"
  case lrclib = "LRCLIB"
  case better = "Better Lyrics"
  case spotify = "Spotify"
  case offline = "Testo salvato"
  public var id: String { rawValue }
}
public struct ExtraLyrics: Sendable {
  let session: URLSession
  public init(session: URLSession = .shared) { self.session = session }
  public func fetch(
    _ query: LyricsQuery, provider: LyricsProviderChoice, token: String = "",
    clientToken: String = ""
  ) async throws -> ResolvedLyrics? {
    switch provider {
    case .simpMusic:
      var url = URL(string: "https://api-lyrics.simpmusic.org/v1")!
      url.appendPathComponent(query.videoID)
      let data = try await get(url)
      let object = try JSONSerialization.jsonObject(with: data)
      let rows: [[String: Any]]
      if let array = object as? [[String: Any]] {
        rows = array
      } else if let root = object as? [String: Any], let array = root["data"] as? [[String: Any]] {
        rows = array
      } else {
        return nil
      }
      for row in rows.sorted(by: { ($0["vote"] as? Int ?? 0) > ($1["vote"] as? Int ?? 0) }) {
        guard row["videoId"] as? String == query.videoID else { continue }
        if let duration = query.durationSeconds, let actual = row["durationSeconds"] as? Double,
          abs(duration - actual) > 10
        {
          continue
        }
        let lrc = row["syncedLyrics"] as? String
        if let text = LyricsResolver.usableText(row["plainLyric"] as? String)
          ?? LyricsResolver.usableText(LyricsResolver.stripLRC(lrc))
        {
          return ResolvedLyrics(text: text, source: .simpMusic, sourceURL: url, syncedText: lrc)
        }
      }
      return nil
    case .better:
      var url = URLComponents(string: "https://lyrics-api.boidu.dev/getLyrics")!
      url.queryItems = [
        URLQueryItem(name: "s", value: query.title), URLQueryItem(name: "a", value: query.artist),
      ]
      if let duration = query.durationSeconds {
        url.queryItems?.append(URLQueryItem(name: "d", value: String(Int(duration))))
      }
      let data = try await get(url.url!)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let ttml = json["ttml"] as? String
      else { return nil }
      let lrc = try TTMLLyrics.lrc(ttml)
      if let duration = query.durationSeconds,
        (LyricsTimeline(lrc: lrc).lines.last?.time ?? 0) > duration + 10
      {
        return nil
      }
      guard let text = LyricsResolver.usableText(LyricsResolver.stripLRC(lrc)) else { return nil }
      return ResolvedLyrics(text: text, source: .better, sourceURL: nil, syncedText: lrc)
    case .spotify:
      guard !token.isEmpty else { throw LyricsLookupError.spotifyCredentials }
      var search = URLComponents(string: "https://api.spotify.com/v1/search")!
      search.queryItems = [
        URLQueryItem(name: "q", value: "track:\(query.title) artist:\(query.artist)"),
        URLQueryItem(name: "type", value: "track"), URLQueryItem(name: "limit", value: "5"),
      ]
      let data = try await get(search.url!, token: token)
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tracks = json["tracks"] as? [String: Any],
        let rows = tracks["items"] as? [[String: Any]]
      else { return nil }
      for row in rows {
        guard let id = row["id"] as? String,
          id.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
          let title = row["name"] as? String,
          LyricsResolver.normalized(LyricsResolver.searchTitle(title))
            == LyricsResolver.normalized(LyricsResolver.searchTitle(query.title)),
          let artists = row["artists"] as? [[String: Any]],
          artists.contains(where: {
            LyricsResolver.normalized($0["name"] as? String ?? "")
              == LyricsResolver.normalized(LyricsResolver.searchArtist(query.artist))
          })
        else { continue }
        if let expected = query.durationSeconds, let actual = row["duration_ms"] as? Double,
          abs(actual / 1000 - expected) > 10
        {
          continue
        }
        let endpoint = URL(
          string:
            "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(id)?format=json&vocalRemoval=false&market=from_token"
        )!
        let bytes = try await get(endpoint, token: token, spotify: true, clientToken: clientToken)
        guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          let lyrics = json["lyrics"] as? [String: Any],
          let lines = lyrics["lines"] as? [[String: Any]]
        else { return nil }
        let text = lines.compactMap { $0["words"] as? String }.joined(separator: "\n")
        let synced = lyrics["syncType"] as? String == "LINE_SYNCED"
        let lrc =
          synced
          ? lines.compactMap { line -> String? in
            guard let time = Double(line["startTimeMs"] as? String ?? ""),
              let words = line["words"] as? String
            else { return nil }
            return TTMLLyrics.stamp(time / 1000, word: false) + words
          }.joined(separator: "\n") : nil
        guard let usable = LyricsResolver.usableText(text) else { return nil }
        return ResolvedLyrics(
          text: usable, source: .spotify,
          sourceURL: URL(string: "https://open.spotify.com/track/\(id)"), syncedText: lrc)
      }
      return nil
    default: return nil
    }
  }
  private func get(_ url: URL, token: String = "", spotify: Bool = false, clientToken: String = "")
    async throws -> Data
  {
    var request = URLRequest(url: url, timeoutInterval: 12)
    request.setValue(
      url.host == "api-lyrics.simpmusic.org"
        ? "SimpMusicLyrics/1.0" : "NoteNarrate/0.9 (https://github.com/stivy73/SimpMusic)",
      forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    if !clientToken.isEmpty { request.setValue(clientToken, forHTTPHeaderField: "Client-Token") }
    if spotify { request.setValue("WebPlayer", forHTTPHeaderField: "app-platform") }
    let (data, response) = try await session.data(for: request)
    guard let code = (response as? HTTPURLResponse)?.statusCode else {
      throw LyricsLookupError.unavailable
    }
    if code == 404 { return Data("[]".utf8) }
    guard (200..<300).contains(code), data.count < 2_000_000 else {
      throw LyricsLookupError.unavailable
    }
    return data
  }
}

public enum TTMLLyrics {
  public static func stamp(_ time: Double, word: Bool) -> String {
    let ms = max(0, Int((time * 1000).rounded()))
    return String(
      format: word ? "<%02d:%02d.%03d>" : "[%02d:%02d.%03d]", ms / 60000, ms / 1000 % 60, ms % 1000)
  }
  public static func lrc(_ xml: String) throws -> String {
    guard xml.utf8.count < 2_000_000 else { throw LyricsLookupError.unavailable }
    let delegate = TTMLReader()
    let parser = XMLParser(data: Data(xml.utf8))
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), !delegate.rows.isEmpty else { throw LyricsLookupError.unavailable }
    return delegate.rows.joined(separator: "\n")
  }
}
private final class TTMLReader: NSObject, XMLParserDelegate {
  var rows: [String] = []
  private var line: String?
  private var plain = ""
  private var wordEnd: Double?
  private func time(_ value: String?) -> Double? {
    guard let value else { return nil }
    if value.hasSuffix("ms") { return Double(value.dropLast(2)).map { $0 / 1000 } }
    if value.hasSuffix("s") { return Double(value.dropLast()) }
    let components = value.split(separator: ":").compactMap { Double($0) }
    guard !components.isEmpty else { return nil }
    return components.reduce(0) { $0 * 60 + $1 }
  }
  func parser(
    _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    let name = element.split(separator: ":").last.map(String.init)
    if name == "p", let begin = time(attributes["begin"]), begin.isFinite, begin >= 0 {
      line = TTMLLyrics.stamp(begin, word: false)
      plain = ""
      wordEnd = nil
    } else if name == "span", line != nil, let begin = time(attributes["begin"]), begin.isFinite {
      line! += TTMLLyrics.stamp(begin, word: true)
      wordEnd = time(attributes["end"])
    } else if name == "br", line != nil {
      line! += " "
      plain += " "
    }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if line != nil {
      line! += string
      plain += string
    }
  }
  func parser(
    _ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    if element.split(separator: ":").last == "p" {
      if let line, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        rows.append(line)
      }
      line = nil
    }
  }
}

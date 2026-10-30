import Foundation
import YouTubeSDK

public enum AudioQuality: String, CaseIterable, Codable, Sendable, Identifiable {
  case saver = "Risparmio dati"
  case normal = "Standard"
  case high = "Alta"
  public var id: String { rawValue }
  public var bitrate: Int {
    switch self {
    case .saver: 48000
    case .normal: 128000
    case .high: 320000
    }
  }
}

public enum AudioPlaybackError: LocalizedError {
  case unavailable
  case rejectedRange(offset: Int64, status: Int?)
  public var errorDescription: String? {
    "Audio non disponibile per questo brano. Prova un altro risultato oppure apri il video su YouTube."
  }
}

/// Sanitized stages only: never retains provider response bodies, headers or URLs.
public struct AudioResolutionFailure: LocalizedError, Sendable {
  public let accountDiagnostic: String
  public let networkDiagnostic: String
  public var errorDescription: String? { AudioPlaybackError.unavailable.localizedDescription }

  static func detail(_ error: Error) -> String {
    if case AudioPlaybackError.rejectedRange(let offset, let status) = error {
      return "CDN offset \(offset): "
        + (status.map { "HTTP \($0), intervallo non valido" } ?? "risposta non valida")
    }
    if error is PlayerCipherError { return "decodifica indirizzo audio non disponibile" }
    if case LibraryError.authentication = error { return "sessione rifiutata da YouTube Music" }
    if case LibraryError.http(let status) = error { return "player HTTP \(status)" }
    if let error = error as? URLError { return "rete \(error.code.rawValue)" }
    return "nessuno stream completo validato"
  }
}

/// Uses the SDK player response/parser; signed URLs are never persisted or logged.
public struct YouTubeAudio: Sendable {
  public struct Source: Sendable {
    public let url: URL
    public let duration: Double
    public let userAgent: String
    public let byteCount: Int64?
    public let isHLS: Bool
    public let authenticated: Bool
    public let accountDiagnostic: String
    public init(
      url: URL, duration: Double, userAgent: String, byteCount: Int64?, isHLS: Bool,
      authenticated: Bool = false, accountDiagnostic: String = ""
    ) {
      self.url = url
      self.duration = duration
      self.userAgent = userAgent
      self.byteCount = byteCount
      self.isHLS = isHLS
      self.authenticated = authenticated
      self.accountDiagnostic = accountDiagnostic
    }
  }
  private let transport: URLSession?
  public init(transport: URLSession? = nil) { self.transport = transport }

  public static func candidates(_ video: YouTubeVideo, quality: AudioQuality = .high) -> [URL] {
    let aac = (video.streamingData?.adaptiveFormats ?? []).filter {
      $0.mimeType.hasPrefix("audio/mp4") && $0.mimeType.contains("mp4a")
    }.sorted {
      let a = abs($0.bitrate - quality.bitrate)
      let b = abs($1.bitrate - quality.bitrate)
      return a == b ? $0.bitrate > $1.bitrate : a < b
    }.compactMap { $0.url.flatMap(URL.init(string:)) }
    var seen = Set<URL>()
    return (aac + [video.hlsURL].compactMap { $0 }).filter { url in
      guard url.scheme == "https", let host = url.host,
        host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
      else { return false }
      return seen.insert(url).inserted
    }
  }

  public func resolve(
    videoID: String, session account: YouTubeSession? = nil, quality: AudioQuality = .high,
    excluding: Set<URL> = [], preferHLS: Bool = false
  ) async throws
    -> Source
  {
    var accountDiagnostic = "Nessuna sessione YouTube Music disponibile"
    var publicDiagnostic = "IOS pubblico: non verificato"
    if preferHLS { await YouTubePlayerCipher.shared.invalidate() }
    if let account {
      do {
        let video = try await webVideo(videoID: videoID, account: account)
        return try await source(
          video: video, userAgent: ClientConfig.webRemix.userAgent, authenticated: true,
          quality: quality, excluding: excluding, preferHLS: preferHLS)
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
        if case DecodingError.keyNotFound(let key, _) = error {
          let field = String(
            key.stringValue.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40))
          accountDiagnostic = "Account: risposta player incompleta (" + field + ")"
        } else {
          accountDiagnostic = "Account: " + AudioResolutionFailure.detail(error)
        }
      }
    }
    do {
      let video = try await YouTubeClient().video(id: videoID)
      let fallback = try await source(
        video: video, userAgent: ClientConfig.ios.userAgent, authenticated: false, quality: quality,
        excluding: excluding, preferHLS: preferHLS)
      return Source(
        url: fallback.url, duration: fallback.duration, userAgent: fallback.userAgent,
        byteCount: fallback.byteCount, isHLS: fallback.isHLS, authenticated: false,
        accountDiagnostic: accountDiagnostic + "; sorgente IOS pubblica validata")
    } catch is CancellationError { throw CancellationError() } catch {
      try Task.checkCancellation()
      publicDiagnostic = "IOS pubblico: " + AudioResolutionFailure.detail(error)
    }
    // Native IOS can serve a valid prefix but reject the rest. Try the web player
    // with its actual signature timestamp and local s/n decoding before giving up.
    do {
      let video = try await webVideo(videoID: videoID, account: nil)
      let fallback = try await source(
        video: video, userAgent: ClientConfig.webRemix.userAgent, authenticated: false,
        quality: quality, excluding: excluding, preferHLS: preferHLS)
      return Source(
        url: fallback.url, duration: fallback.duration, userAgent: fallback.userAgent,
        byteCount: fallback.byteCount, isHLS: fallback.isHLS, authenticated: false,
        accountDiagnostic: accountDiagnostic + "; sorgente WEB pubblica decodificata e validata")
    } catch is CancellationError { throw CancellationError() } catch {
      try Task.checkCancellation()
      throw AudioResolutionFailure(
        accountDiagnostic: accountDiagnostic,
        networkDiagnostic: publicDiagnostic + "; WEB pubblico: "
          + AudioResolutionFailure.detail(error))
    }
  }

  private func webVideo(videoID: String, account: YouTubeSession?) async throws -> YouTubeVideo {
    let cipher = YouTubePlayerCipher.shared
    let info: YouTubePlayerCipher.PlayerInfo?
    do { info = try await cipher.playerInfo() } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      info = nil
    }
    let video = try await YouTubeBrowse(session: account).player(
      videoID: videoID, signatureTimestamp: info?.signatureTimestamp)
    // An unavailable decoder registry must not break already playable direct/HLS
    // responses. source() still validates actual media access beyond the prefix.
    guard let info else { return video }
    return try await cipher.decipher(video: video, player: info)
  }

  func source(
    video: YouTubeVideo, userAgent: String, authenticated: Bool, quality: AudioQuality,
    excluding: Set<URL> = [], preferHLS: Bool = false
  ) async throws
    -> Source
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let transport = self.transport ?? URLSession(configuration: configuration)
    defer { if self.transport == nil { transport.invalidateAndCancel() } }
    var candidates = Self.candidates(video, quality: quality).filter { !excluding.contains($0) }
    if preferHLS, let hls = video.hlsURL, candidates.contains(hls) {
      candidates.removeAll { $0 == hls }
      candidates.insert(hls, at: 0)
    }
    var lastError: Error = AudioPlaybackError.unavailable
    for url in candidates {
      do {
        if url == video.hlsURL {
          let playlist = try await validateHLS(url: url, userAgent: userAgent, transport: transport)
          guard !excluding.contains(playlist) else { continue }
          return Source(
            url: playlist, duration: Double(video.lengthInSeconds) ?? 0,
            userAgent: userAgent, byteCount: nil, isHLS: true, authenticated: authenticated,
            accountDiagnostic: authenticated ? "Account: segmenti HLS verificati" : "")
        }
        let length = try await validateRange(
          url: url, userAgent: userAgent, transport: transport, first: 0, last: 1023)
        // A readable prefix is not a playable song. Validate the exact failure boundary
        // and the tail for BOTH account and public streams before giving one to AVPlayer.
        try await withThrowingTaskGroup(of: Void.self) { group in
          if length > 1_048_576 {
            group.addTask {
              _ = try await validateRange(url: url, userAgent: userAgent, transport: transport,
                first: 1_048_576, last: min(length - 1, 1_049_599), expectedLength: length)
            }
          }
          if length > 1024 {
            group.addTask {
              _ = try await validateRange(url: url, userAgent: userAgent, transport: transport,
                first: length - 1024, last: length - 1, expectedLength: length)
            }
          }
          for try await _ in group {}
        }
        try Task.checkCancellation()
        return Source(
          url: url, duration: Double(video.lengthInSeconds) ?? 0,
          userAgent: userAgent, byteCount: length, isHLS: false,
          authenticated: authenticated,
          accountDiagnostic: authenticated ? "Account: inizio, oltre 1 MiB e fine verificati" : "")
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
        lastError = error
      }
    }
    throw lastError
  }

  private func validateRange(
    url: URL, userAgent: String, transport: URLSession, first: Int64, last: Int64,
    expectedLength: Int64? = nil
  ) async throws -> Int64 {
    let source = Source(
      url: url, duration: 0, userAgent: userAgent, byteCount: expectedLength, isHLS: false)
    let request = try AudioRangeLoader.rangeRequest(source: source, offset: first, last: last)
    let (data, response) = try await transport.data(for: request)
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse, http.statusCode == 206,
      let range = http.value(forHTTPHeaderField: "Content-Range"),
      let length = range.split(separator: "/").last.flatMap({ Int64($0) }), length > last,
      expectedLength == nil || expectedLength == length,
      range == "bytes \(first)-\(last)/\(length)", data.count == last - first + 1
    else {
      throw AudioPlaybackError.rejectedRange(
        offset: first, status: (response as? HTTPURLResponse)?.statusCode)
    }
    return length
  }

  /// A manifest returning 200 says nothing about segment access. Probe an early,
  /// post-minute and final segment, keeping all requests on Google's media hosts.
  private func validateHLS(
    url: URL, userAgent: String, transport: URLSession, depth: Int = 0
  ) async throws -> URL {
    guard depth < 3 else { throw AudioPlaybackError.unavailable }
    let data = try await hlsData(url, userAgent: userAgent, transport: transport, limit: 512 * 1024)
    guard let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") else {
      throw AudioPlaybackError.unavailable
    }
    let lines = text.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // Use the exact validated playlist so AVPlayer cannot select an untested variant.
    if let variant = lines.firstIndex(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }) {
      let attributes = Self.hlsAttributes(lines[variant])
      let variantURI = lines.dropFirst(variant + 1).first {
        !$0.isEmpty && !$0.hasPrefix("#")
      }
      var selectedURI = variantURI
      if let group = attributes["AUDIO"] {
        let renditions = lines.filter { $0.hasPrefix("#EXT-X-MEDIA:") }
          .map(Self.hlsAttributes).filter { $0["TYPE"] == "AUDIO" && $0["GROUP-ID"] == group }
        guard
          let rendition = renditions.first(where: { $0["DEFAULT"] == "YES" })
            ?? renditions.first(where: { $0["AUTOSELECT"] == "YES" }) ?? renditions.first
        else { throw AudioPlaybackError.unavailable }
        // A separate audio rendition belongs to the master. Returning only its video
        // child would discard AUDIO=group and produce silent playback in an audio app.
        // No URI means the selected rendition is multiplexed in the variant itself.
        selectedURI = rendition["URI"] ?? variantURI
      }
      guard let value = selectedURI, let child = Self.mediaURL(value, relativeTo: url)
      else { throw AudioPlaybackError.unavailable }
      return try await validateHLS(
        url: child, userAgent: userAgent, transport: transport, depth: depth + 1)
    }
    var segments: [(url: URL, start: Double)] = []
    var position = 0.0
    var duration: Double?
    for line in lines {
      if line.hasPrefix("#EXTINF:") {
        duration = line.dropFirst(8).split(separator: ",").first.flatMap { Double($0) }
      } else if !line.isEmpty, !line.hasPrefix("#"), let seconds = duration,
        seconds.isFinite, seconds > 0, let segment = Self.mediaURL(line, relativeTo: url)
      {
        segments.append((segment, position))
        position += seconds
        duration = nil
      }
    }
    guard !segments.isEmpty, lines.contains("#EXT-X-ENDLIST") else {
      throw AudioPlaybackError.unavailable
    }
    var probes = [segments[0].url, segments[segments.count - 1].url]
    if let afterMinute = segments.first(where: { $0.start >= 60 }) {
      probes.append(afterMinute.url)
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for segment in Set(probes) {
        group.addTask {
          _ = try await hlsData(segment, userAgent: userAgent, transport: transport,
            limit: 1024, range: true)
        }
      }
      for try await _ in group {}
    }
    return url
  }

  /// HLS attribute lists allow commas inside quoted values (CODECS, names and URIs).
  /// Split only outside quotes so rendition group names and signed URLs stay intact.
  private static func hlsAttributes(_ line: String) -> [String: String] {
    guard let colon = line.firstIndex(of: ":") else { return [:] }
    var quoted = false
    var fields: [String] = []
    var field = ""
    for character in line[line.index(after: colon)...] {
      if character == "\"" { quoted.toggle() }
      if character == ",", !quoted {
        fields.append(field)
        field = ""
      } else {
        field.append(character)
      }
    }
    guard !quoted else { return [:] }
    fields.append(field)
    var attributes: [String: String] = [:]
    for field in fields {
      guard let equals = field.firstIndex(of: "=") else { continue }
      let key = field[..<equals].trimmingCharacters(in: .whitespaces)
      var value = field[field.index(after: equals)...].trimmingCharacters(in: .whitespaces)
      if value.count >= 2, value.first == "\"", value.last == "\"" {
        value.removeFirst()
        value.removeLast()
      }
      attributes[key] = value
    }
    return attributes
  }

  private static func mediaURL(_ value: String, relativeTo base: URL) -> URL? {
    guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
      url.scheme == "https", let host = url.host,
      host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
    else { return nil }
    return url
  }

  private func hlsData(
    _ url: URL, userAgent: String, transport: URLSession, limit: Int, range: Bool = false
  ) async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    if range { request.setValue("bytes=0-1023", forHTTPHeaderField: "Range") }
    let (bytes, response) = try await transport.bytes(for: request)
    guard let http = response as? HTTPURLResponse,
      [200, 206].contains(http.statusCode),
      let final = http.url, Self.mediaURL(final.absoluteString, relativeTo: url) != nil
    else { throw AudioPlaybackError.unavailable }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      data.append(byte)
      if data.count == limit {
        guard range else { throw AudioPlaybackError.unavailable }
        break
      }
    }
    guard !data.isEmpty else { throw AudioPlaybackError.unavailable }
    return data
  }

}

/// Async loads and interruption callbacks must never resurrect a paused/changed track.
public struct PlaybackIntent: Sendable {
  public private(set) var revision = UUID()
  public private(set) var wantsPlayback = false
  private var interrupted: UUID?
  public init() {}
  @discardableResult public mutating func load() -> UUID {
    revision = UUID()
    wantsPlayback = true
    interrupted = nil
    return revision
  }
  public mutating func play() {
    wantsPlayback = true
    interrupted = nil
  }
  public mutating func pause() {
    wantsPlayback = false
    interrupted = nil
  }
  public mutating func interruptionBegan() {
    interrupted = wantsPlayback ? revision : nil
    wantsPlayback = false
  }
  @discardableResult public mutating func interruptionEnded(shouldResume: Bool) -> Bool {
    guard let interrupted else { return false }
    let resume = shouldResume && interrupted == revision
    self.interrupted = nil
    wantsPlayback = resume
    return resume
  }
}

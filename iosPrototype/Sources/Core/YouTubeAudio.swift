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
  public let resolutionReport: String
  public init(accountDiagnostic: String, networkDiagnostic: String, resolutionReport: String = "") {
    self.accountDiagnostic = accountDiagnostic
    self.networkDiagnostic = networkDiagnostic
    self.resolutionReport = resolutionReport
  }
  public var errorDescription: String? { AudioPlaybackError.unavailable.localizedDescription }

  static func detail(_ error: Error) -> String {
    if case AudioPlaybackError.rejectedRange(let offset, let status) = error {
      return "CDN offset \(offset): "
        + (status.map { "HTTP \($0), intervallo non valido" } ?? "risposta non valida")
    }
    if error is PlayerCipherError { return "decodifica indirizzo audio non disponibile" }
    if case DecodingError.keyNotFound(let key, _) = error {
      let field = String(key.stringValue.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40))
      return "risposta player incompleta (\(field))"
    }
    if error is DecodingError { return "formato risposta player non riconosciuto" }
    if case LibraryError.authentication = error { return "sessione rifiutata da YouTube Music" }
    if case LibraryError.http(let status) = error { return "player HTTP \(status)" }
    if let error = error as? URLError { return "rete \(error.code.rawValue)" }
    return "nessuno stream completo validato"
  }
}

/// Per-resolution bounded metadata only. Never retains URLs, cookies, response
/// bodies, header values other than a validated numeric range, or track identity.
final class AudioResolutionTrace: @unchecked Sendable {
  private let lock = NSLock()
  private let began = DispatchTime.now().uptimeNanoseconds
  private var lines: [String] = []
  private let receive: (@Sendable (String) -> Void)?
  init(receive: (@Sendable (String) -> Void)? = nil) { self.receive = receive }
  var report: String { lock.withLock { lines.joined(separator: "\n") } }
  func record(_ message: String) {
    let snapshot = lock.withLock {
      let ms = (DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
      lines.append("+\(ms)ms " + String(message.prefix(500)))
      if lines.count > 96 { lines.removeFirst(lines.count - 96) }
      return lines.joined(separator: "\n")
    }
    receive?(snapshot)
  }
  static func range(_ http: HTTPURLResponse) -> String {
    guard let value = http.value(forHTTPHeaderField: "Content-Range") else { return "none" }
    guard value.count < 100,
      value.range(of: #"^bytes ([0-9]+-[0-9]+|\*)/[0-9]+$"#, options: .regularExpression) != nil
    else { return "invalid" }
    return value
  }
  static func response(_ http: HTTPURLResponse, requested: URL, bytes: Int, ms: Int) -> String {
    let allowed = ["audio/mp4", "audio/mpeg", "video/mp4", "application/octet-stream",
      "text/html", "text/plain", "application/vnd.apple.mpegurl", "application/x-mpegurl"]
    let mime = http.mimeType.map { allowed.contains($0) ? $0 : "other" } ?? "none"
    let redirect: String
    if http.url?.host == requested.host { redirect = "same-host" }
    else if let host = http.url?.host, host.hasSuffix(".googlevideo.com") { redirect = "googlevideo" }
    else { redirect = "other" }
    return "HTTP \(http.statusCode), bytes \(bytes), range \(range(http)), mime \(mime), redirect \(redirect), \(ms)ms"
  }
  static func addressMetadata(_ url: URL) -> String {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
    let expiry: String
    if let seconds = value("expire").flatMap(Double.init), seconds.isFinite,
      abs(seconds - Date().timeIntervalSince1970) < 7 * 86400
    { expiry = seconds > Date().timeIntervalSince1970 ? "valid" : "expired" }
    else { expiry = "unknown" }
    let signed = (value("sparams") ?? "").split(separator: ",")
    return "expiry=\(expiry), n=\(value("n") != nil), signature=\(value("sig") != nil || value("signature") != nil), pot=\(value("pot") != nil), ip_bound=\(value("ip") != nil), range_signed=\(signed.contains("range"))"
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
    public let resolutionReport: String
    public init(
      url: URL, duration: Double, userAgent: String, byteCount: Int64?, isHLS: Bool,
      authenticated: Bool = false, accountDiagnostic: String = "", resolutionReport: String = ""
    ) {
      self.url = url
      self.duration = duration
      self.userAgent = userAgent
      self.byteCount = byteCount
      self.isHLS = isHLS
      self.authenticated = authenticated
      self.accountDiagnostic = accountDiagnostic
      self.resolutionReport = resolutionReport
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
    excluding: Set<URL> = [], preferHLS: Bool = false, preferHLSForLongTracks: Bool = false,
    diagnostic: (@Sendable (String) -> Void)? = nil
  ) async throws
    -> Source
  {
    let trace = AudioResolutionTrace(receive: diagnostic)
    trace.record("Audio report v1; account=\(account != nil); recovery=\(preferHLS)")
    func completed(_ source: Source, path: String) -> Source {
      trace.record("Selected \(path); validation complete")
      return Source(url: source.url, duration: source.duration, userAgent: source.userAgent,
        byteCount: source.byteCount, isHLS: source.isHLS, authenticated: source.authenticated,
        accountDiagnostic: source.accountDiagnostic, resolutionReport: trace.report)
    }
    var accountDiagnostic = "Nessuna sessione YouTube Music disponibile"
    var publicDiagnostic = "IOS pubblico: non verificato"
    var appleDiagnostic = ""
    if preferHLS { await YouTubePlayerCipher.shared.invalidate() }
    if let account {
      do {
        trace.record("ACCOUNT_WEB player start")
        let video = try await webVideo(videoID: videoID, account: account, trace: trace)
        let selected = try await source(
          video: video, userAgent: ClientConfig.webRemix.userAgent, authenticated: true,
          quality: quality, excluding: excluding, preferHLS: preferHLS,
          preferHLSForLongTracks: preferHLSForLongTracks,
          diagnostic: { trace.record("ACCOUNT_WEB " + $0) })
        return completed(selected, path: "ACCOUNT_WEB")
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
        if case DecodingError.keyNotFound(let key, _) = error {
          let field = String(
            key.stringValue.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40))
          accountDiagnostic = "Account: risposta player incompleta (" + field + ")"
        } else {
          accountDiagnostic = "Account: " + AudioResolutionFailure.detail(error)
        }
        trace.record("ACCOUNT_WEB failed: " + accountDiagnostic)
      }
    }
    // Some public mobile responses expose only a readable prefix. Bootstrap a
    // fresh anonymous visitor for the Apple player, then apply the SAME complete
    // range/HLS validation as every other source. Account playback stays first.
    do {
      trace.record("PUBLIC_APPLE player start")
      let video = try await YouTubeApplePlayer().video(id: videoID,
        diagnostic: { trace.record("PUBLIC_APPLE " + $0) })
      let fallback = try await source(video: video, userAgent: YouTubeApplePlayer.userAgent,
        authenticated: false, quality: quality, excluding: excluding, preferHLS: preferHLS,
        preferHLSForLongTracks: preferHLSForLongTracks,
        diagnostic: { trace.record("PUBLIC_APPLE " + $0) })
      return completed(Source(url: fallback.url, duration: fallback.duration,
        userAgent: fallback.userAgent, byteCount: fallback.byteCount, isHLS: fallback.isHLS,
        authenticated: false,
        accountDiagnostic: accountDiagnostic + "; sorgente Apple pubblica validata"), path: "PUBLIC_APPLE")
    } catch is CancellationError { throw CancellationError() } catch {
      try Task.checkCancellation()
      appleDiagnostic = "Apple pubblico: " + AudioResolutionFailure.detail(error)
      trace.record("PUBLIC_APPLE failed: " + appleDiagnostic)
    }
    do {
      trace.record("PUBLIC_IOS player start; client_version=" + ClientConfig.ios.version)
      let video = try await YouTubeClient().video(id: videoID)
      let fallback = try await source(
        video: video, userAgent: ClientConfig.ios.userAgent, authenticated: false, quality: quality,
        excluding: excluding, preferHLS: preferHLS,
        preferHLSForLongTracks: preferHLSForLongTracks,
        diagnostic: { trace.record("PUBLIC_IOS " + $0) })
      return completed(Source(
        url: fallback.url, duration: fallback.duration, userAgent: fallback.userAgent,
        byteCount: fallback.byteCount, isHLS: fallback.isHLS, authenticated: false,
        accountDiagnostic: accountDiagnostic + "; sorgente IOS pubblica validata"), path: "PUBLIC_IOS")
    } catch is CancellationError { throw CancellationError() } catch {
      try Task.checkCancellation()
      publicDiagnostic = "IOS pubblico: " + AudioResolutionFailure.detail(error)
      trace.record("PUBLIC_IOS failed: " + publicDiagnostic)
    }
    // Native IOS can serve a valid prefix but reject the rest. Try the web player
    // with its actual signature timestamp and local s/n decoding before giving up.
    do {
      trace.record("PUBLIC_WEB player start")
      let video = try await webVideo(videoID: videoID, account: nil, trace: trace)
      let fallback = try await source(
        video: video, userAgent: ClientConfig.webRemix.userAgent, authenticated: false,
        quality: quality, excluding: excluding, preferHLS: preferHLS,
        preferHLSForLongTracks: preferHLSForLongTracks,
        diagnostic: { trace.record("PUBLIC_WEB " + $0) })
      return completed(Source(
        url: fallback.url, duration: fallback.duration, userAgent: fallback.userAgent,
        byteCount: fallback.byteCount, isHLS: fallback.isHLS, authenticated: false,
        accountDiagnostic: accountDiagnostic + "; sorgente WEB pubblica decodificata e validata"), path: "PUBLIC_WEB")
    } catch is CancellationError { throw CancellationError() } catch {
      try Task.checkCancellation()
      trace.record("PUBLIC_WEB failed: " + AudioResolutionFailure.detail(error))
      throw AudioResolutionFailure(
        accountDiagnostic: accountDiagnostic,
        networkDiagnostic: appleDiagnostic + "; " + publicDiagnostic + "; WEB pubblico: "
          + AudioResolutionFailure.detail(error), resolutionReport: trace.report)
    }
  }

  private func webVideo(videoID: String, account: YouTubeSession?, trace: AudioResolutionTrace)
    async throws -> YouTubeVideo {
    let cipher = YouTubePlayerCipher.shared
    let info: YouTubePlayerCipher.PlayerInfo?
    do { info = try await cipher.playerInfo() } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      trace.record("WEB cipher metadata unavailable: " + AudioResolutionFailure.detail(error))
      info = nil
    }
    if let info {
      trace.record("WEB cipher player=\(info.id), timestamp=\(info.signatureTimestamp)")
    }
    let video = try await YouTubeBrowse(session: account).player(
      videoID: videoID, signatureTimestamp: info?.signatureTimestamp,
      diagnostic: { trace.record("WEB player " + $0) })
    // An unavailable decoder registry must not break already playable direct/HLS
    // responses. source() still validates actual media access beyond the prefix.
    guard let info else { return video }
    let decoded = try await cipher.decipher(video: video, player: info)
    trace.record("WEB cipher completed")
    return decoded
  }

  func source(
    video: YouTubeVideo, userAgent: String, authenticated: Bool, quality: AudioQuality,
    excluding: Set<URL> = [], preferHLS: Bool = false, preferHLSForLongTracks: Bool = false,
    diagnostic: (@Sendable (String) -> Void)? = nil
  ) async throws
    -> Source
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let transport = self.transport ?? URLSession(configuration: configuration)
    defer { if self.transport == nil { transport.invalidateAndCancel() } }
    var candidates = Self.candidates(video, quality: quality).filter { !excluding.contains($0) }
    // Long fragmented AAC files can make AVFoundation inspect the entire file
    // before its first sample. A validated HLS timeline starts from a few segments.
    // Playback opts in; offline downloads retain their AAC-first behavior.
    let longStream = preferHLSForLongTracks && (Double(video.lengthInSeconds) ?? 0) >= 600
    if preferHLS || longStream, let hls = video.hlsURL, candidates.contains(hls) {
      candidates.removeAll { $0 == hls }
      candidates.insert(hls, at: 0)
      diagnostic?(longStream ? "long-track HLS preferred" : "recovery HLS preferred")
    }
    var lastError: Error = AudioPlaybackError.unavailable
    diagnostic?("player AAC=\((video.streamingData?.adaptiveFormats ?? []).filter { $0.mimeType.hasPrefix("audio/mp4") }.count), candidates=\(candidates.count), hls=\(video.hlsURL != nil)")
    for (index, url) in candidates.enumerated() {
      let label = "candidate \(index + 1)/\(candidates.count)"
      let record: @Sendable (String) -> Void = { diagnostic?(label + " " + $0) }
      if let format = video.streamingData?.adaptiveFormats.first(where: { $0.url == url.absoluteString }) {
        record("itag=\(format.itag), bitrate=\(format.bitrate), declared_bytes=\(format.contentLength.flatMap(Int64.init) ?? -1)")
      }
      record(AudioResolutionTrace.addressMetadata(url))
      do {
        if url == video.hlsURL {
          let playlist = try await validateHLS(url: url, userAgent: userAgent, transport: transport,
            diagnostic: record)
          guard !excluding.contains(playlist) else { continue }
          return Source(
            url: playlist, duration: Double(video.lengthInSeconds) ?? 0,
            userAgent: userAgent, byteCount: nil, isHLS: true, authenticated: authenticated,
            accountDiagnostic: authenticated ? "Account: segmenti HLS verificati" : "")
        }
        let length = try await validateRange(
          url: url, userAgent: userAgent, transport: transport, first: 0, last: 1023,
          diagnostic: record)
        // A readable prefix is not a playable song. Validate the exact failure boundary
        // and the tail for BOTH account and public streams before giving one to AVPlayer.
        try await withThrowingTaskGroup(of: Void.self) { group in
          if length > 1_048_576 {
            group.addTask {
              _ = try await validateRange(url: url, userAgent: userAgent, transport: transport,
                first: 1_048_576, last: min(length - 1, 1_049_599), expectedLength: length,
                diagnostic: record)
            }
          }
          if length > 1024 {
            group.addTask {
              _ = try await validateRange(url: url, userAgent: userAgent, transport: transport,
                first: length - 1024, last: length - 1, expectedLength: length,
                diagnostic: record)
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
        record("rejected: " + AudioResolutionFailure.detail(error))
      }
    }
    throw lastError
  }

  private func validateRange(
    url: URL, userAgent: String, transport: URLSession, first: Int64, last: Int64,
    expectedLength: Int64? = nil, diagnostic: (@Sendable (String) -> Void)? = nil
  ) async throws -> Int64 {
    let source = Source(
      url: url, duration: 0, userAgent: userAgent, byteCount: expectedLength, isHLS: false)
    let request = try AudioRangeLoader.rangeRequest(source: source, offset: first, last: last)
    let began = Date()
    diagnostic?("request bytes=\(first)-\(last)")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await transport.data(for: request)
    } catch {
      diagnostic?("bytes=\(first)-\(last) transport: " + AudioResolutionFailure.detail(error))
      throw error
    }
    if let http = response as? HTTPURLResponse {
      diagnostic?("bytes=\(first)-\(last) " + AudioResolutionTrace.response(http,
        requested: url, bytes: data.count, ms: Int(max(0, Date().timeIntervalSince(began) * 1000))))
    }
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
    url: URL, userAgent: String, transport: URLSession, depth: Int = 0,
    diagnostic: (@Sendable (String) -> Void)? = nil
  ) async throws -> URL {
    guard depth < 3 else { throw AudioPlaybackError.unavailable }
    diagnostic?("HLS manifest depth=\(depth)")
    // A one-hour playlist can exceed 512 KiB because every segment has a signed
    // address. Keep a hard bound without rejecting valid long-form streaming.
    let data = try await hlsData(url, userAgent: userAgent, transport: transport, limit: 4 * 1024 * 1024,
      diagnostic: diagnostic)
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
        url: child, userAgent: userAgent, transport: transport, depth: depth + 1,
        diagnostic: diagnostic)
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
    var probes = [("head", segments[0].url), ("tail", segments[segments.count - 1].url)]
    if let afterMinute = segments.first(where: { $0.start >= 60 }) {
      probes.append(("after-minute", afterMinute.url))
    }
    try await withThrowingTaskGroup(of: Void.self) { group in
      var seen = Set<URL>()
      for (name, segment) in probes where seen.insert(segment).inserted {
        group.addTask {
          _ = try await hlsData(segment, userAgent: userAgent, transport: transport,
            limit: 1024, range: true, diagnostic: { diagnostic?("HLS segment \(name) " + $0) })
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
    _ url: URL, userAgent: String, transport: URLSession, limit: Int, range: Bool = false,
    diagnostic: (@Sendable (String) -> Void)? = nil
  ) async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    if range { request.setValue("bytes=0-1023", forHTTPHeaderField: "Range") }
    let began = Date()
    let (bytes, response) = try await transport.bytes(for: request)
    defer { bytes.task.cancel() }
    if let http = response as? HTTPURLResponse {
      diagnostic?("headers " + AudioResolutionTrace.response(http, requested: url, bytes: 0,
        ms: Int(max(0, Date().timeIntervalSince(began) * 1000))))
    }
    guard let http = response as? HTTPURLResponse,
      [200, 206].contains(http.statusCode),
      let final = http.url, Self.mediaURL(final.absoluteString, relativeTo: url) != nil
    else { throw AudioPlaybackError.unavailable }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      data.append(byte)
      if data.count == limit {
        guard range else {
          diagnostic?("manifest size limit reached: \(limit) bytes")
          throw AudioPlaybackError.unavailable
        }
        break
      }
    }
    guard !data.isEmpty else { throw AudioPlaybackError.unavailable }
    diagnostic?("sample bytes=\(data.count)")
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

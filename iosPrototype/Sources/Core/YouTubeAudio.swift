import Foundation
import YouTubeSDK

public enum AudioPlaybackError: LocalizedError {
  case unavailable
  public var errorDescription: String? {
    "Audio non disponibile per questo brano. Prova un altro risultato oppure apri il video su YouTube."
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
  public init() {}

  public static func candidates(_ video: YouTubeVideo) -> [URL] {
    let aac = (video.streamingData?.adaptiveFormats ?? []).filter {
      $0.mimeType.hasPrefix("audio/mp4") && $0.mimeType.contains("mp4a")
    }.sorted { $0.bitrate > $1.bitrate }.compactMap { $0.url.flatMap(URL.init(string:)) }
    var seen = Set<URL>()
    return (aac + [video.hlsURL].compactMap { $0 }).filter { url in
      guard url.scheme == "https", let host = url.host,
        host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
      else { return false }
      return seen.insert(url).inserted
    }
  }

  public func resolve(videoID: String, session account: YouTubeSession? = nil) async throws
    -> Source
  {
    var accountDiagnostic = "Nessuna sessione YouTube Music disponibile"
    if let account {
      do {
        let video = try await YouTubeBrowse(session: account).player(videoID: videoID)
        return try await source(
          video: video, userAgent: ClientConfig.webRemix.userAgent, validateTail: true)
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
        if case DecodingError.keyNotFound(let key, _) = error {
          let field = String(
            key.stringValue.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40))
          accountDiagnostic = "Account: risposta player incompleta (" + field + ")"
        } else if case LibraryError.authentication = error {
          accountDiagnostic = "Account: sessione rifiutata da YouTube Music"
        } else if case LibraryError.http(let status) = error {
          accountDiagnostic = "Account: player HTTP \(status)"
        } else {
          accountDiagnostic = "Account: nessuno stream completo validato"
        }
      }
    }
    let video = try await YouTubeClient().video(id: videoID)
    let fallback = try await source(
      video: video, userAgent: ClientConfig.ios.userAgent, validateTail: false)
    return Source(
      url: fallback.url, duration: fallback.duration, userAgent: fallback.userAgent,
      byteCount: fallback.byteCount, isHLS: fallback.isHLS, authenticated: false,
      accountDiagnostic: accountDiagnostic)
  }

  private func source(video: YouTubeVideo, userAgent: String, validateTail: Bool) async throws
    -> Source
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let transport = URLSession(configuration: configuration)
    defer { transport.invalidateAndCancel() }
    for url in Self.candidates(video) {
      var request = URLRequest(url: url, timeoutInterval: 15)
      request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
      request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
      do {
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode), !data.isEmpty
        else { continue }
        let length = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last
          .flatMap { Int64($0) }
        if validateTail, url != video.hlsURL, let length, length > 1_048_576 {
          let first = length - 1024
          request.setValue("bytes=\(first)-\(length - 1)", forHTTPHeaderField: "Range")
          request.cachePolicy = .reloadIgnoringLocalCacheData
          let (tail, response) = try await transport.data(for: request)
          guard let response = response as? HTTPURLResponse, response.statusCode == 206,
            tail.count == 1024,
            response.value(forHTTPHeaderField: "Content-Range")
              == "bytes \(first)-\(length - 1)/\(length)"
          else { continue }
        }
        return Source(
          url: url, duration: Double(video.lengthInSeconds) ?? 0,
          userAgent: userAgent, byteCount: length, isHLS: url == video.hlsURL,
          authenticated: validateTail)
      } catch is CancellationError { throw CancellationError() } catch {
        try Task.checkCancellation()
      }
    }
    throw AudioPlaybackError.unavailable
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

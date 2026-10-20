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

  public func resolve(videoID: String) async throws -> Source {
    let video = try await YouTubeClient().video(id: videoID)
    try Task.checkCancellation()
    for url in Self.candidates(video) {
      var request = URLRequest(url: url, timeoutInterval: 15)
      request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
      request.setValue(ClientConfig.ios.userAgent, forHTTPHeaderField: "User-Agent")
      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode), !data.isEmpty
        {
          return Source(
            url: url, duration: Double(video.lengthInSeconds) ?? 0,
            userAgent: ClientConfig.ios.userAgent,
            byteCount: http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last
              .flatMap { Int64($0) }, isHLS: url == video.hlsURL)
        }
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

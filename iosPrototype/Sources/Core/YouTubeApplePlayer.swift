import Foundation
import YouTubeSDK

/// Anonymous Apple player fallback. Keep the visitor identity consistent between
/// bootstrap and player; never reuse Music account cookies with this client.
/// Client contract: yt-dlp PR #17184 and extractor/youtube/_base.py (2026-11-01).
public struct YouTubeApplePlayer: Sendable {
  public static let userAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
  private let transport: URLSession?
  public init(transport: URLSession? = nil) { self.transport = transport }

  public func video(
    id: String, diagnostic: (@Sendable (String) -> Void)? = nil
  ) async throws -> YouTubeVideo {
    guard id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else {
      throw AudioPlaybackError.unavailable
    }
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    let transport = self.transport ?? URLSession(
      configuration: config, delegate: ApplePlayerNoRedirect(), delegateQueue: nil)
    defer { if self.transport == nil { transport.invalidateAndCancel() } }
    var bootstrap = URLRequest(url: URL(string: "https://www.youtube.com/")!, timeoutInterval: 15)
    bootstrap.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    bootstrap.cachePolicy = .reloadIgnoringLocalCacheData
    let (page, pageResponse) = try await transport.data(for: bootstrap)
    try Task.checkCancellation()
    guard (pageResponse as? HTTPURLResponse)?.statusCode == 200, page.count <= 4 * 1024 * 1024,
      let visitor = Self.visitorData(in: page)
    else { throw AudioPlaybackError.unavailable }
    diagnostic?("client=VISIONOS, version=1.02, anonymous visitor ready")
    var request = URLRequest(
      url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!,
      timeoutInterval: 15)
    request.httpMethod = "POST"
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("101", forHTTPHeaderField: "X-YouTube-Client-Name")
    request.setValue("1.02", forHTTPHeaderField: "X-YouTube-Client-Version")
    request.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
    request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
    request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "context": ["client": [
        "clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple",
        "deviceModel": "RealityDevice17,1", "userAgent": Self.userAgent,
        "osName": "visionOS", "osVersion": "26.5.23O471", "hl": "en", "gl": "US",
        "visitorData": visitor,
      ]],
      "videoId": id, "contentCheckOk": true, "racyCheckOk": true,
      "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
    ])
    let began = Date()
    let (data, response) = try await transport.data(for: request)
    try Task.checkCancellation()
    if let http = response as? HTTPURLResponse {
      diagnostic?(AudioResolutionTrace.response(http, requested: request.url!, bytes: data.count,
        ms: Int(max(0, Date().timeIntervalSince(began) * 1000))))
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4 * 1024 * 1024,
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      (root["playabilityStatus"] as? [String: Any])?["status"] as? String == "OK"
    else { throw AudioPlaybackError.unavailable }
    let video = try JSONDecoder().decode(YouTubeVideo.self, from: data)
    guard video.id == id else { throw AudioPlaybackError.unavailable }
    return video
  }

  static func visitorData(in data: Data) -> String? {
    guard let text = String(data: data, encoding: .utf8),
      let expression = try? NSRegularExpression(
        pattern: #""VISITOR_DATA"\s*:\s*("(?:[^"\\]|\\.)*")"#),
      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: 1), in: text),
      let value = try? JSONDecoder().decode(String.self, from: Data(text[range].utf8)),
      (1...4096).contains(value.count),
      value.range(of: #"^[A-Za-z0-9_%.+/=-]+$"#, options: .regularExpression) != nil
    else { return nil }
    return value
  }
}

private final class ApplePlayerNoRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}

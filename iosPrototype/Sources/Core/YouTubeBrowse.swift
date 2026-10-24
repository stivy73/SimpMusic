import Foundation
import YouTubeSDK

/// Shared WEB_REMIX browse transport for the remote library and personalized discovery.
/// Cookie identity, account index and delegated account match the confirmed login session.
public final class YouTubeBrowse: Sendable {
  private let session: YouTubeSession?
  private let transport: URLSession
  private let visitor = BrowseVisitor()

  public init(session: YouTubeSession?, transport: URLSession? = nil) {
    self.session = session
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    self.transport =
      transport
      ?? URLSession(
        configuration: configuration, delegate: NoBrowseRedirect(), delegateQueue: nil)
  }

  deinit { transport.invalidateAndCancel() }

  public func request(browseId: String, params: String? = nil, token: String? = nil) async throws
    -> Data
  {
    var fields: [String: Any] = [:]
    if let token {
      guard !token.isEmpty else { throw LibraryError.malformed }
      fields["continuation"] = token
    } else {
      fields["browseId"] = browseId
      if let params { fields["params"] = params }
    }
    return try await send(endpoint: "browse", fields: fields)
  }

  public func search(query: String, filter: MusicSearchFilter) async throws -> Data {
    try await send(endpoint: "search", fields: ["query": query, "params": filter.params])
  }

  /// Reuse the confirmed account identity for media, not just the library.
  public func player(videoID: String) async throws -> YouTubeVideo {
    let data = try await send(
      endpoint: "player",
      fields: [
        "videoId": videoID,
        "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
      ])
    return try JSONDecoder().decode(YouTubeVideo.self, from: data)
  }

  private func send(endpoint: String, fields: [String: Any]) async throws -> Data {
    let context = InnerTubeContext(client: .webRemix, cookies: session?.cookies, gl: "IT", hl: "it")
    var request = URLRequest(
      url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!,
      timeoutInterval: endpoint == "player" ? 15 : 45)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = context.headers
    request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
    request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
    var payload = context.body
    if let visitorID = visitor.value {
      request.setValue(visitorID, forHTTPHeaderField: "X-Goog-Visitor-Id")
      var config = payload["context"] as? [String: Any] ?? [:]
      var client = config["client"] as? [String: Any] ?? [:]
      client["visitorData"] = visitorID
      config["client"] = client
      payload["context"] = config
    }
    if let session {
      request.setValue(try session.authorization(), forHTTPHeaderField: "Authorization")
      request.setValue(session.accountIndex, forHTTPHeaderField: "X-Goog-AuthUser")
      request.setValue(session.delegatedID, forHTTPHeaderField: "X-Goog-PageId")
      request.setValue(session.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
      var config = payload["context"] as? [String: Any] ?? [:]
      var client = config["client"] as? [String: Any] ?? [:]
      client["clientVersion"] = session.clientVersion
      config["client"] = client
      if let delegated = session.delegatedID { config["user"] = ["onBehalfOfUser": delegated] }
      payload["context"] = config
    }
    payload.merge(fields) { _, new in new }
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (data, response) = try await transport.data(for: request)
    try Task.checkCancellation()
    guard let status = (response as? HTTPURLResponse)?.statusCode else {
      throw LibraryError.malformed
    }
    if status == 401 || status == 403 || (300..<400).contains(status) {
      throw LibraryError.authentication
    }
    guard status == 200 else { throw LibraryError.http(status) }
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    let responseContext = root["responseContext"] as? [String: Any]
    if let id = responseContext?["visitorData"] as? String { visitor.set(id) }
    if session != nil {
      let context = root["responseContext"] as? [String: Any]
      for tracking in context?["serviceTrackingParams"] as? [[String: Any]] ?? [] {
        for value in tracking["params"] as? [[String: Any]] ?? [] {
          if value["key"] as? String == "logged_in", value["value"] as? String == "0" {
            throw LibraryError.authentication
          }
        }
      }
    }
    return data
  }
}

private final class BrowseVisitor: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: String?
  var value: String? { lock.withLock { stored } }
  func set(_ value: String) { lock.withLock { stored = value } }
}

private final class NoBrowseRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}

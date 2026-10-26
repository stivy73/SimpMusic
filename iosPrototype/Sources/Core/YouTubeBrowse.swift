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

  public func request(
    browseId: String, params: String? = nil, token: String? = nil, country: String? = nil
  ) async throws
    -> Data
  {
    var fields: [String: Any] = [:]
    if let token {
      guard !token.isEmpty else { throw LibraryError.malformed }
      fields["continuation"] = token
    } else {
      fields["browseId"] = browseId
      if let params { fields["params"] = params }
      if let country {
        guard
          country == "ZZ" || country.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil
        else { throw LibraryError.malformed }
        fields["formData"] = ["selectedValues": [country]]
      }
    }
    return try await send(endpoint: "browse", fields: fields)
  }

  public func search(query: String, filter: MusicSearchFilter, continuation: String? = nil)
    async throws -> Data
  {
    if let continuation {
      guard !continuation.isEmpty else { throw LibraryError.malformed }
      return try await send(
        endpoint: "search", fields: ["continuation": continuation], continuationQuery: continuation)
    }
    return try await send(endpoint: "search", fields: ["query": query, "params": filter.params])
  }

  public func next(endpoint: RadioEndpoint, continuation: String? = nil) async throws -> Data {
    guard endpoint.videoID?.isEmpty == false || endpoint.playlistID?.isEmpty == false else {
      throw RadioError.unavailable
    }
    var fields = endpoint.fields
    if let continuation { fields["continuation"] = continuation }
    return try await send(endpoint: "next", fields: fields)
  }

  /// The same authenticated rate endpoints used by the Android fork. Never send anonymously.
  public func setLiked(videoID: String, liked: Bool) async throws {
    guard session != nil else { throw LibraryError.authentication }
    guard !videoID.isEmpty else { throw LibraryError.malformed }
    let data = try await send(
      endpoint: liked ? "like/like" : "like/removelike", fields: ["target": ["videoId": videoID]])
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    if let status = root["status"] as? String, status != "STATUS_SUCCEEDED" {
      throw LibraryError.rejected
    }
  }

  public func playlist(id: String) async throws -> RemotePlaylist {
    guard session != nil else { throw LibraryError.authentication }
    let browseID = id.hasPrefix("VL") ? id : "VL" + id
    return try await RemotePlaylist.completed { token in
      try await self.request(browseId: browseID, token: token)
    }
  }

  public func canEditPlaylist(id: String) async throws -> Bool {
    guard session != nil else { throw LibraryError.authentication }
    let data = try await request(browseId: id.hasPrefix("VL") ? id : "VL" + id)
    return try await YouTubeMusicClient().decodeEditablePlaylistPage(from: data).editable
  }

  private func confirmedWrite(endpoint: String, fields: [String: Any]) async throws -> [String: Any]
  {
    guard session != nil else { throw LibraryError.authentication }
    let data = try await send(endpoint: endpoint, fields: fields)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      root["error"] == nil
    else { throw LibraryError.rejected }
    if let status = root["status"] as? String, status != "STATUS_SUCCEEDED" {
      throw LibraryError.rejected
    }
    return root
  }

  public func createPlaylist(title: String, videoIDs: [String] = []) async throws -> String {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !title.contains("<"), !title.contains(">") else {
      throw LibraryError.malformed
    }
    let root = try await confirmedWrite(
      endpoint: "playlist/create",
      fields: [
        "title": title, "privacyStatus": "PRIVATE", "videoIds": videoIDs,
      ])
    guard let id = root["playlistId"] as? String, !id.isEmpty else { throw LibraryError.rejected }
    return id
  }

  public func editPlaylist(id: String, action: PlaylistAction) async throws {
    let id = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    guard !id.isEmpty, id != "LM" else { throw LibraryError.malformed }
    _ = try await confirmedWrite(
      endpoint: "browse/edit_playlist",
      fields: [
        "playlistId": id, "actions": [action.fields],
      ])
  }

  public func deletePlaylist(id: String) async throws {
    let id = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    guard !id.isEmpty, id != "LM" else { throw LibraryError.malformed }
    _ = try await confirmedWrite(endpoint: "playlist/delete", fields: ["playlistId": id])
  }

  public func setFollowed(artistID: String, followed: Bool) async throws {
    guard artistID.hasPrefix("UC"),
      artistID.range(of: #"^[A-Za-z0-9_-]{3,100}$"#, options: .regularExpression) != nil
    else { throw LibraryError.malformed }
    _ = try await confirmedWrite(
      endpoint: followed ? "subscription/subscribe" : "subscription/unsubscribe",
      fields: ["channelIds": [artistID]])
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

  private func send(endpoint: String, fields: [String: Any], continuationQuery: String? = nil)
    async throws -> Data
  {
    let context = InnerTubeContext(client: .webRemix, cookies: session?.cookies, gl: "IT", hl: "it")
    var url = URLComponents(
      string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!
    if let token = continuationQuery {
      url.queryItems =
        (url.queryItems ?? []) + [
          URLQueryItem(name: "continuation", value: token),
          URLQueryItem(name: "ctoken", value: token),
        ]
      // A literal plus in opaque tokens must not become a form-encoded space.
      url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
    var request = URLRequest(
      url: url.url!,
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
    guard root["error"] == nil else { throw LibraryError.rejected }
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

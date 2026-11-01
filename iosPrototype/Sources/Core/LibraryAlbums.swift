import CryptoKit
import Foundation

public struct YouTubeSession: Codable, Sendable, Equatable {
  public let cookies: String
  public let accountIndex: String
  public let delegatedID: String?
  public let identity: String
  public let clientVersion: String

  public init(
    cookies: String, accountIndex: String = "0", delegatedID: String? = nil,
    identity: String, clientVersion: String
  ) {
    self.cookies = cookies
    self.accountIndex = accountIndex
    self.delegatedID = delegatedID
    self.identity = identity
    self.clientVersion = clientVersion
  }

  public func authorization(timestamp: Int = Int(Date().timeIntervalSince1970)) throws -> String {
    let values = cookies.split(separator: ";").reduce(into: [String: String]()) { result, part in
      let pair = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
      if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
    }
    guard let sid = values["SAPISID"] ?? values["__Secure-3PAPISID"], !sid.isEmpty else {
      throw LibraryError.authentication
    }
    let input = "\(timestamp) \(sid) https://music.youtube.com"
    let hash = Insecure.SHA1.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }
      .joined()
    return "SAPISIDHASH \(timestamp)_\(hash)"
  }
}

public enum LibraryError: LocalizedError {
  case authentication, malformed, repeatedContinuation, rejected
  case http(Int)
  case unsupported(String)
  public var errorDescription: String? {
    switch self {
    case .authentication: "La sessione YouTube Music è scaduta. Accedi nuovamente."
    case .rejected: "YouTube Music non ha confermato la richiesta. Aggiorna e riprova."
    case .malformed:
      "Formato della libreria non riconosciuto. Nessuna lista incompleta è stata salvata."
    case .unsupported(let detail):
      "Formato della libreria non riconosciuto (\(detail)). Nessuna lista incompleta è stata salvata."
    case .repeatedContinuation: "YouTube Music ha ripetuto una pagina. Aggiorna la libreria."
    case .http(let status): "Impossibile caricare la libreria (HTTP \(status)). Riprova."
    }
  }
}

public struct LibraryAlbum: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let artist: String
  public let artwork: URL?
  public init(id: String, title: String, artist: String, artwork: URL?) {
    self.id = id
    self.title = title
    self.artist = artist
    self.artwork = artwork
  }
}

/// Normalize only the selected library page. Never search menus, inactive tabs or recommendations.
enum LibraryBrowseEnvelope {
  static func normalize(_ data: Data) throws -> Data {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw LibraryError.malformed
    }
    if root["error"] != nil { throw LibraryError.authentication }
    let context = root["responseContext"] as? [String: Any]
    for tracking in context?["serviceTrackingParams"] as? [[String: Any]] ?? [] {
      for parameter in tracking["params"] as? [[String: Any]] ?? [] {
        if parameter["key"] as? String == "logged_in", parameter["value"] as? String == "0" {
          throw LibraryError.authentication
        }
      }
    }
    func message(_ value: [String: Any]) throws {
      func signIn(_ value: Any) -> Bool {
        if let list = value as? [Any] { return list.contains(where: signIn) }
        guard let object = value as? [String: Any] else { return false }
        return object["signInEndpoint"] != nil || object.values.contains(where: signIn)
      }
      if signIn(value) { throw LibraryError.authentication }
      let field = value["text"] as? [String: Any] ?? [:]
      let raw = (field["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        ?? field["simpleText"] as? String ?? value["text"] as? String ?? ""
      let text = String(raw.prefix(2000)).folding(options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "it_IT")).replacingOccurrences(of: "’", with: "'")
      if ["sign in", "log in", "accedi", "effettua l'accesso", "esegui l'accesso"].contains(where: text.contains) {
        throw LibraryError.authentication
      }
      if ["error", "errore", "riprova", "try again", "unavailable", "non disponibile", "cannot load"]
        .contains(where: text.contains) { throw LibraryError.rejected }
      let empty = ["no albums", "no liked albums", "no saved albums", "no playlists", "no songs",
        "no liked songs", "no saved songs", "no artists", "nothing here", "library is empty",
        "nessun album", "nessuna playlist", "nessun brano", "nessuna canzone",
        "nessun artista", "libreria e vuota", "raccolta e vuota",
        "appariranno qui", "verranno visualizzati qui", "saranno visualizzati qui"]
      let collection = ["album", "playlist", "brani", "canzon", "artist", "libreria", "raccolta", "song", "music"]
        .contains(where: text.contains)
      let emptyContext = ["haven't added", "haven't saved", "haven't liked", "don't have any", "do not have any",
        "appear here", "show up here", "non hai ancora", "non ci sono"].contains(where: text.contains)
      guard empty.contains(where: text.contains) || (collection && emptyContext) else {
        // No provider message, identifiers or account details enter diagnostics.
        throw LibraryError.unsupported("messageRenderer:stato-raccolta-non-riconosciuto")
      }
    }
    func rows(_ values: [[String: Any]], depth: Int) throws -> [[String: Any]] {
      guard depth < 24 else { throw LibraryError.malformed }
      var result: [[String: Any]] = []
      let supported = ["gridRenderer", "musicShelfRenderer", "musicPlaylistShelfRenderer",
        "musicCarouselShelfRenderer", "musicDescriptionShelfRenderer", "musicResponsiveListItemRenderer",
        "musicTwoRowItemRenderer", "musicMultiRowListItemRenderer", "continuationItemRenderer"]
      for value in values {
        let rendererKeys = value.keys.filter { $0.hasSuffix("Renderer") }
        guard rendererKeys.allSatisfy({ supported.contains($0) || ["itemSectionRenderer", "messageRenderer"].contains($0) }) else {
          throw LibraryError.unsupported("library-section:unknown-renderer")
        }
        if let section = value["itemSectionRenderer"] as? [String: Any] {
          guard let contents = section["contents"] as? [[String: Any]] else { throw LibraryError.malformed }
          result += try rows(contents, depth: depth + 1)
          if let raw = section["continuations"] {
            guard let continuations = raw as? [[String: Any]] else { throw LibraryError.malformed }
            for entry in continuations {
              guard let next = (entry["nextContinuationData"] ?? entry["reloadContinuationData"]) as? [String: Any],
                let token = next["continuation"] as? String, !token.isEmpty else { throw LibraryError.malformed }
              result.append(["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": token]]]])
            }
          }
        } else if let notice = value["messageRenderer"] as? [String: Any] {
          try message(notice)
          result.append(value)
        } else if supported.contains(where: { value[$0] != nil }) {
          result.append(try rewrite(value, depth: depth + 1))
        } else {
          throw LibraryError.unsupported("library-section:unknown-renderer")
        }
      }
      return result
    }
    func rewrite(_ object: [String: Any], depth: Int) throws -> [String: Any] {
      guard depth < 24 else { throw LibraryError.malformed }
      var output = object
      if var tabs = object["tabs"] as? [[String: Any]] {
        let selected = tabs.firstIndex { ($0["tabRenderer"] as? [String: Any])?["selected"] as? Bool == true }
          ?? tabs.firstIndex { ($0["tabRenderer"] as? [String: Any])?["content"] != nil }
        if let selected { tabs[selected] = try rewrite(tabs[selected], depth: depth + 1) }
        output["tabs"] = tabs
      }
      for key in ["sectionListRenderer", "sectionListContinuation", "gridRenderer", "gridContinuation",
        "singleColumnBrowseResultsRenderer", "twoColumnBrowseResultsRenderer", "tabRenderer", "content",
        "continuationContents", "appendContinuationItemsAction", "reloadContinuationItemsCommand"] {
        if let child = object[key] as? [String: Any] { output[key] = try rewrite(child, depth: depth + 1) }
      }
      for key in ["contents", "items", "continuationItems"] {
        if let children = object[key] as? [[String: Any]] {
          let normalized = try rows(children, depth: depth + 1)
          output[key] = key == "items" ? normalized.filter { $0["messageRenderer"] == nil } : normalized
        } else if let child = object[key] as? [String: Any] {
          output[key] = try rewrite(child, depth: depth + 1)
        }
      }
      for key in ["onResponseReceivedActions", "onResponseReceivedEndpoints"] {
        if let children = object[key] as? [[String: Any]] {
          output[key] = try children.map { try rewrite($0, depth: depth + 1) }
        }
      }
      return output
    }
    return try JSONSerialization.data(withJSONObject: rewrite(root, depth: 0))
  }
}

/// Adapts the same grid/section envelopes handled by Android LibraryAlbumsPage.
/// SDK album initializers are internal and expect flattened dictionaries, not InnerTube renderers.
public struct LibraryAlbumsPage: Sendable {
  public let albums: [LibraryAlbum]
  public let continuations: [String]

  public static func parse(_ data: Data) throws -> Self {
    let data = try LibraryBrowseEnvelope.normalize(data)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw LibraryError.malformed
    }
    if root["error"] != nil { throw LibraryError.authentication }
    let context = root["responseContext"] as? [String: Any]
    for tracking in context?["serviceTrackingParams"] as? [[String: Any]] ?? [] {
      for value in tracking["params"] as? [[String: Any]] ?? [] {
        if value["key"] as? String == "logged_in", value["value"] as? String == "0" {
          throw LibraryError.authentication
        }
      }
    }
    // Only schema keys from known browse envelopes, never values, cookies or identifiers.
    func unsupported(_ location: String, _ object: [String: Any]) -> LibraryError {
      let keys = object.keys.filter {
        $0.range(
          of: "^[a-zA-Z]{1,80}(Renderer|Continuation|Action|Command)$", options: .regularExpression)
          != nil
      }.sorted().prefix(8).joined(separator: ",")
      let names: Set<String> = [
        "tabRenderer", "sectionListRenderer", "gridRenderer", "gridContinuation",
        "musicTwoRowItemRenderer", "messageRenderer", "musicShelfRenderer",
      ]
      var counts: [String: Int] = [:]
      func count(_ value: Any) {
        if let list = value as? [Any] { list.forEach(count) }
        if let dictionary = value as? [String: Any] {
          for (key, child) in dictionary {
            if names.contains(key) { counts[key, default: 0] += 1 }
            count(child)
          }
        }
      }
      count(root)
      let shape = counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: ",")
      return .unsupported(location + ":" + (keys.isEmpty ? "unknown" : keys) + "; " + shape)
    }
    var albums: [LibraryAlbum] = []
    var tokens: [String] = []
    var recognized = false
    func addTokens(_ object: [String: Any]) throws {
      guard let raw = object["continuations"] else { return }
      guard let values = raw as? [[String: Any]] else { throw unsupported("continuations", object) }
      for value in values {
        guard let next = value["nextContinuationData"] as? [String: Any],
          let token = next["continuation"] as? String, !token.isEmpty
        else {
          throw unsupported("nextContinuationData", value)
        }
        tokens.append(token)
      }
    }
    func text(_ object: Any?) -> String {
      let object = object as? [String: Any] ?? [:]
      return (object["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        ?? object["simpleText"] as? String ?? ""
    }
    func item(_ object: [String: Any]) throws {
      if let continuation = object["continuationItemRenderer"] as? [String: Any] {
        guard let endpoint = continuation["continuationEndpoint"] as? [String: Any],
          let command = endpoint["continuationCommand"] as? [String: Any],
          let token = command["token"] as? String, !token.isEmpty
        else { throw unsupported("continuationItem", continuation) }
        tokens.append(token)
        return
      }
      guard let renderer = object["musicTwoRowItemRenderer"] as? [String: Any],
        let endpoint = renderer["navigationEndpoint"] as? [String: Any],
        let browse = endpoint["browseEndpoint"] as? [String: Any],
        let id = browse["browseId"] as? String, !id.isEmpty
      else { throw unsupported("item", object) }
      let config = browse["browseEndpointContextSupportedConfigs"] as? [String: Any]
      let music = config?["browseEndpointContextMusicConfig"] as? [String: Any]
      guard music?["pageType"] as? String == "MUSIC_PAGE_TYPE_ALBUM" || id.hasPrefix("MPRE") else {
        throw unsupported("album-type", music ?? browse)
      }
      let title = text(renderer["title"])
      guard !title.isEmpty else { throw unsupported("album-title", renderer) }
      let thumbnail = renderer["thumbnailRenderer"] as? [String: Any]
      let musicThumbnail = thumbnail?["musicThumbnailRenderer"] as? [String: Any]
      let image = musicThumbnail?["thumbnail"] as? [String: Any]
      let images = image?["thumbnails"] as? [[String: Any]]
      let artwork = (images?.last?["url"] as? String).flatMap(URL.init(string:))
      albums.append(
        LibraryAlbum(id: id, title: title, artist: text(renderer["subtitle"]), artwork: artwork))
    }
    func visit(_ value: Any) throws {
      if let list = value as? [Any] {
        for element in list { try visit(element) }
        return
      }
      guard let object = value as? [String: Any] else { return }
      for key in ["gridRenderer", "gridContinuation"] {
        if let grid = object[key] as? [String: Any] {
          recognized = true
          guard let items = grid["items"] as? [[String: Any]] else {
            throw unsupported("grid-items", grid)
          }
          try items.forEach(item)
          try addTokens(grid)
          return
        }
      }
      for key in ["sectionListRenderer", "sectionListContinuation"] {
        if let section = object[key] as? [String: Any] {
          recognized = true
          guard let contents = section["contents"] as? [Any] else {
            throw unsupported("section-contents", section)
          }
          for content in contents {
            if let entry = content as? [String: Any], entry["continuationItemRenderer"] != nil || entry["musicTwoRowItemRenderer"] != nil {
              try item(entry)
              continue
            }
            guard let entry = content as? [String: Any],
              entry["gridRenderer"] != nil || entry["messageRenderer"] != nil
                || entry["musicDescriptionShelfRenderer"] != nil
            else { throw unsupported("section", content as? [String: Any] ?? [:]) }
            try visit(entry)
          }
          try addTokens(section)
          return
        }
      }
      for key in ["appendContinuationItemsAction", "reloadContinuationItemsCommand"] {
        if let action = object[key] as? [String: Any] {
          recognized = true
          guard let items = action["continuationItems"] as? [[String: Any]] else {
            throw unsupported("action-items", action)
          }
          try items.forEach(item)
          return
        }
      }
      // Browse includes lazy placeholders for inactive tabs. Only the selected tab is a page.
      if let tabs = object["tabs"] as? [[String: Any]] {
        let renderers = tabs.compactMap { $0["tabRenderer"] as? [String: Any] }
        guard
          let tab = renderers.first(where: { $0["selected"] as? Bool == true })
            ?? renderers.first(where: { $0["content"] != nil }), let content = tab["content"]
        else { throw unsupported("selected-tab", object) }
        try visit(content)
        return
      }
      // Only walk known browse wrappers, never menus, recommendations or headers.
      for key in [
        "contents", "continuationContents", "singleColumnBrowseResultsRenderer",
        "twoColumnBrowseResultsRenderer", "tabRenderer", "content",
        "onResponseReceivedActions", "onResponseReceivedEndpoints",
      ] {
        if let child = object[key] { try visit(child) }
      }
    }
    try visit(root)
    guard recognized else { throw unsupported("root", root["contents"] as? [String: Any] ?? root) }
    return Self(albums: albums, continuations: tokens)
  }

  public static func completed(
    fetch: @Sendable (String?) async throws -> LibraryAlbumsPage
  ) async throws -> [LibraryAlbum] {
    var result: [LibraryAlbum] = []
    var albumIDs = Set<String>()
    var seenTokens = Set<String>()
    var pending: [String] = []
    var cursor = 0
    var token: String?
    while true {
      try Task.checkCancellation()
      let page = try await fetch(token)
      try Task.checkCancellation()
      for album in page.albums where albumIDs.insert(album.id).inserted { result.append(album) }
      for continuation in page.continuations {
        guard !continuation.isEmpty, seenTokens.insert(continuation).inserted else {
          throw LibraryError.repeatedContinuation
        }
        pending.append(continuation)
      }
      guard cursor < pending.count else { return result }
      token = pending[cursor]
      cursor += 1
    }
  }
}

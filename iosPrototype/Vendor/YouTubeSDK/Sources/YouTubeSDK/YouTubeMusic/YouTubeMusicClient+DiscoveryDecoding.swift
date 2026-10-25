// Narrow public decoding entry points for an authenticated browse transport.
// Item decoding remains in the existing SDK models; see LOCAL_CHANGES.md.
import Foundation

public struct YouTubeMusicBrowseEndpoint: Hashable, Codable, Sendable {
  public let browseId: String
  public let params: String?
  public init(browseId: String, params: String? = nil) {
    self.browseId = browseId
    self.params = params
  }
}

public struct YouTubeMusicCategory: Identifiable, Sendable {
  public var id: String { endpoint.browseId + ":" + (endpoint.params ?? "") }
  public let title: String
  public let stripeColor: UInt32
  public let endpoint: YouTubeMusicBrowseEndpoint
}

public struct YouTubeMusicCategorySection: Sendable {
  public let title: String
  public let items: [YouTubeMusicCategory]
}

extension YouTubeMusicClient {
  /// Filtered search owns its result shelf's continuation, even beside spelling/filter rows.
  public func decodeSearchPage(from data: Data) throws -> YouTubeMusicHomePage {
    try decodeDiscoveryPage(from: data, searchResults: true)
  }

  /// Reads only the page's own continuation, never a nested shelf's token.
  /// Preserves section order, account strapline, "More" endpoints and category buttons.
  public func decodeDiscoveryPage(
    from data: Data, strictItems: Bool = false, searchResults: Bool = false
  ) throws
    -> YouTubeMusicHomePage
  {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      root["error"] == nil
    else { throw URLError(.cannotParseResponse) }
    var containers: [[String: Any]] = []
    func visit(_ value: Any) {
      if let array = value as? [Any] {
        array.forEach(visit)
        return
      }
      guard let object = value as? [String: Any] else { return }
      for key in [
        "sectionListRenderer", "sectionListContinuation", "musicShelfContinuation",
        "musicPlaylistShelfContinuation", "gridContinuation", "appendContinuationItemsAction",
        "reloadContinuationItemsCommand",
      ] {
        if let list = object[key] as? [String: Any] {
          containers.append(list)
          return
        }
      }
      if let tabs = object["tabs"] as? [[String: Any]] {
        let selected = tabs.filter {
          ($0["tabRenderer"] as? [String: Any])?["selected"] as? Bool == true
        }
        (selected.isEmpty ? tabs : selected).forEach(visit)
      }
      for key in [
        "contents", "singleColumnBrowseResultsRenderer", "twoColumnBrowseResultsRenderer",
        "tabRenderer", "tabbedSearchResultsRenderer", "twoColumnSearchResultsRenderer",
        "content", "secondaryContents", "continuationContents",
        "onResponseReceivedActions", "onResponseReceivedEndpoints",
      ] {
        if let child = object[key] { visit(child) }
      }
    }
    visit(root)
    guard !containers.isEmpty else { throw URLError(.cannotParseResponse) }
    var sections: [YouTubeMusicSection] = []
    var categories: [YouTubeMusicCategorySection] = []
    var tokens: [String] = []
    var trackTokens: [String] = []
    var recognizedContent = false
    func validateItems(_ items: [[String: Any]]) throws {
      guard strictItems else { return }
      for item in items {
        if item["continuationItemRenderer"] != nil { continue }
        // YouTube inserts a Create playlist tile. It isn't an empty/unknown media item.
        func isCreate(_ value: Any) -> Bool {
          if let values = value as? [Any] { return values.contains(where: isCreate) }
          guard let object = value as? [String: Any] else { return false }
          if object["createPlaylistEndpoint"] != nil { return true }
          return object.values.contains(where: isCreate)
        }
        if isCreate(item) { continue }
        guard let section = YouTubeMusicSection(from: ["contents": [item]]), !section.items.isEmpty
        else {
          throw URLError(.cannotParseResponse)
        }
      }
    }
    for list in containers {
      guard
        let rows = (list["contents"] ?? list["items"] ?? list["continuationItems"])
          as? [[String: Any]]
      else {
        throw URLError(.cannotParseResponse)
      }
      if rows.isEmpty { recognizedContent = true }
      if let continuations = list["continuations"] as? [Any], !continuations.isEmpty,
        discoveryContinuation(list) == nil
      {
        throw URLError(.cannotParseResponse)
      }
      if let token = discoveryContinuation(list) { tokens.append(token) }
      var looseItems: [[String: Any]] = []
      for row in rows {
        if let continuation = row["continuationItemRenderer"] as? [String: Any] {
          guard let token = discoveryContinuation(continuation) else {
            throw URLError(.cannotParseResponse)
          }
          tokens.append(token)
          recognizedContent = true
        } else if let shelf =
          (row["musicCarouselShelfRenderer"] ?? row["musicShelfRenderer"]
          ?? row["musicPlaylistShelfRenderer"]) as? [String: Any]
        {
          recognizedContent = true
          try validateItems(shelf["contents"] as? [[String: Any]] ?? [])
          if let section = YouTubeMusicSection(from: shelf), !section.items.isEmpty {
            sections.append(section)
          }
          if row["musicPlaylistShelfRenderer"] != nil
            || ((searchResults || rows.count == 1) && row["musicShelfRenderer"] != nil),
            let token = discoveryContinuation(shelf)
          {
            trackTokens.append(token)
          }
        } else if let grid = row["gridRenderer"] as? [String: Any],
          let items = grid["items"] as? [[String: Any]]
        {
          recognizedContent = true
          try validateItems(items)
          if let token = discoveryContinuation(grid) { trackTokens.append(token) }
          let header = (grid["header"] as? [String: Any])?["gridHeaderRenderer"] as? [String: Any]
          let title = discoveryText(header?["title"])
          let buttons = items.compactMap { item -> YouTubeMusicCategory? in
            guard let renderer = item["musicNavigationButtonRenderer"] as? [String: Any],
              let endpoint = discoveryBrowseEndpoint(renderer["clickCommand"])
            else { return nil }
            let label = discoveryText(renderer["buttonText"])
            guard !label.isEmpty else { return nil }
            let solid = renderer["solid"] as? [String: Any]
            let color = (solid?["leftStripeColor"] as? NSNumber)?.uint32Value ?? 0xFF57_C6DC
            return YouTubeMusicCategory(title: label, stripeColor: color, endpoint: endpoint)
          }
          if !buttons.isEmpty { categories.append(.init(title: title, items: buttons)) }
          if let section = YouTubeMusicSection(from: [
            "title": header?["title"] ?? [:], "contents": items,
          ]),
            !section.items.isEmpty
          {
            sections.append(section)
          }
        } else if row["musicResponsiveListItemRenderer"] != nil
          || row["musicTwoRowItemRenderer"] != nil
        {
          recognizedContent = true
          looseItems.append(row)
        } else if row["messageRenderer"] != nil {
          recognizedContent = true
        }
      }
      if !looseItems.isEmpty, let section = YouTubeMusicSection(from: ["contents": looseItems]) {
        try validateItems(looseItems)
        sections.append(section)
      }
    }
    guard recognizedContent else { throw URLError(.cannotParseResponse) }
    if tokens.isEmpty { tokens = trackTokens }
    let unique = Set(tokens)
    guard unique.count <= 1 else { throw URLError(.cannotParseResponse) }
    return YouTubeMusicHomePage(
      sections: sections, continuationToken: tokens.first, categories: categories)
  }
}

func discoveryText(_ value: Any?) -> String {
  if let string = value as? String { return string }
  guard let text = value as? [String: Any] else { return "" }
  return (text["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
    ?? text["simpleText"] as? String ?? ""
}

func discoveryBrowseEndpoint(_ value: Any?) -> YouTubeMusicBrowseEndpoint? {
  guard let nav = value as? [String: Any], let browse = nav["browseEndpoint"] as? [String: Any],
    let id = browse["browseId"] as? String, !id.isEmpty
  else { return nil }
  return .init(browseId: id, params: browse["params"] as? String)
}

func discoveryThumbnails(_ value: Any?) -> [[String: Any]] {
  guard let container = value as? [String: Any] else { return [] }
  if let values = container["thumbnails"] as? [[String: Any]] { return values }
  for key in ["musicThumbnailRenderer", "thumbnail"] {
    if let child = container[key] {
      let result = discoveryThumbnails(child)
      if !result.isEmpty { return result }
    }
  }
  return []
}

func discoveryThumbnail(_ value: Any?) -> URL? {
  discoveryThumbnails(value).last.flatMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
}

private func discoveryContinuation(_ value: [String: Any]) -> String? {
  if let next = (value["continuations"] as? [[String: Any]])?.first,
    let data = (next["nextContinuationData"] ?? next["reloadContinuationData"]) as? [String: Any],
    let token = data["continuation"] as? String, !token.isEmpty
  {
    return token
  }
  let endpoint = value["continuationEndpoint"] as? [String: Any]
  let command = endpoint?["continuationCommand"] as? [String: Any]
  if let token = command?["token"] as? String, !token.isEmpty { return token }
  return nil
}

public struct YouTubeEditablePlaylistPage: Sendable {
  public struct Entry: Sendable {
    public let song: YouTubeMusicSong
    public let setVideoID: String?
  }
  public let editable: Bool
  public let entries: [Entry]
  public let continuation: String?
}

extension YouTubeMusicClient {
  /// Playlist occurrence IDs are intentionally preserved, including repeated songs.
  public func decodeEditablePlaylistPage(from data: Data) throws -> YouTubeEditablePlaylistPage {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      root["error"] == nil
    else {
      throw URLError(.cannotParseResponse)
    }
    var editable = false
    var rows: [[String: Any]] = []
    var tokens: [String] = []
    var recognized = false
    func visit(_ value: Any) throws {
      if let list = value as? [Any] {
        for child in list { try visit(child) }
        return
      }
      guard let object = value as? [String: Any] else { return }
      if object["musicEditablePlaylistDetailHeaderRenderer"] != nil { editable = true }
      for key in [
        "musicPlaylistShelfRenderer", "musicPlaylistShelfContinuation",
        "appendContinuationItemsAction", "reloadContinuationItemsCommand",
      ] {
        if let shelf = object[key] as? [String: Any] {
          guard let contents = (shelf["contents"] ?? shelf["continuationItems"]) as? [[String: Any]]
          else {
            throw URLError(.cannotParseResponse)
          }
          recognized = true
          rows += contents
          if let token = discoveryContinuation(shelf) { tokens.append(token) }
          return
        }
      }
      if let tabs = object["tabs"] as? [[String: Any]] {
        let selected = tabs.filter {
          ($0["tabRenderer"] as? [String: Any])?["selected"] as? Bool == true
        }
        try (selected.isEmpty ? Array(tabs.prefix(1)) : selected).forEach(visit)
      }
      for key in [
        "header", "contents", "singleColumnBrowseResultsRenderer", "twoColumnBrowseResultsRenderer",
        "tabRenderer", "content", "sectionListRenderer", "sectionListContinuation",
        "secondaryContents", "continuationContents", "onResponseReceivedActions",
        "onResponseReceivedEndpoints",
      ] {
        if let child = object[key] { try visit(child) }
      }
    }
    try visit(root)
    guard recognized else { throw URLError(.cannotParseResponse) }
    var entries: [YouTubeEditablePlaylistPage.Entry] = []
    for row in rows {
      if let continuation = row["continuationItemRenderer"] as? [String: Any] {
        guard let token = discoveryContinuation(continuation) else {
          throw URLError(.cannotParseResponse)
        }
        tokens.append(token)
        continue
      }
      guard let renderer = row["musicResponsiveListItemRenderer"] as? [String: Any],
        let song = YouTubeMusicSong(from: renderer)
      else { throw URLError(.cannotParseResponse) }
      let playlistData = renderer["playlistItemData"] as? [String: Any]
      let setID = playlistData?["playlistSetVideoId"] as? String
      entries.append(.init(song: song, setVideoID: setID))
    }
    guard Set(tokens).count <= 1 else { throw URLError(.cannotParseResponse) }
    return YouTubeEditablePlaylistPage(
      editable: editable, entries: entries, continuation: tokens.first)
  }
}

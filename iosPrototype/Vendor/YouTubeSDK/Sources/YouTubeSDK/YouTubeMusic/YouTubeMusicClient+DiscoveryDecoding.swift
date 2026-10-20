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
  /// Reads only the page's own continuation, never a nested shelf's token.
  /// Preserves section order, account strapline, "More" endpoints and category buttons.
  public func decodeDiscoveryPage(from data: Data) throws -> YouTubeMusicHomePage {
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
        "tabRenderer", "content", "secondaryContents", "continuationContents",
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
          if let section = YouTubeMusicSection(from: shelf), !section.items.isEmpty {
            sections.append(section)
          }
          if row["musicPlaylistShelfRenderer"] != nil
            || (rows.count == 1 && row["musicShelfRenderer"] != nil),
            let token = discoveryContinuation(shelf)
          {
            trackTokens.append(token)
          }
        } else if let grid = row["gridRenderer"] as? [String: Any],
          let items = grid["items"] as? [[String: Any]]
        {
          recognizedContent = true
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

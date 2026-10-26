// YouTubeSDK, Aarav Gupta. Extended for NoteNarrate discovery; see LOCAL_CHANGES.md.
import Foundation

public struct YouTubeMusicSection: Identifiable, Sendable {
  public let id = UUID()
  public let title: String
  public let items: [YouTubeMusicItem]
  public let subtitle: String
  public let thumbnailURL: URL?
  public let moreEndpoint: YouTubeMusicBrowseEndpoint?

  init?(from data: [String: Any]) {
    let header = data["header"] as? [String: Any] ?? [:]
    let basic =
      header["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any]
      ?? header["musicShelfHeaderRenderer"] as? [String: Any] ?? [:]
    title =
      discoveryText(basic["title"]).isEmpty
      ? discoveryText(data["title"]) : discoveryText(basic["title"])
    subtitle = discoveryText(basic["strapline"])
    thumbnailURL = discoveryThumbnail(basic["thumbnail"])
    let more = basic["moreContentButton"] as? [String: Any]
    let button = more?["buttonRenderer"] as? [String: Any]
    let titleRuns = (basic["title"] as? [String: Any])?["runs"] as? [[String: Any]]
    moreEndpoint =
      discoveryBrowseEndpoint(button?["navigationEndpoint"])
      ?? discoveryBrowseEndpoint(titleRuns?.first?["navigationEndpoint"])
    guard let contents = data["contents"] as? [[String: Any]] else { return nil }
    items = contents.compactMap(Self.item)
  }

  private static func item(_ data: [String: Any]) -> YouTubeMusicItem? {
    if let episode = data["musicMultiRowListItemRenderer"] as? [String: Any] {
      var box = episode
      box["navigationEndpoint"] = episode["onTap"]
      box["subtitle"] = episode["secondTitle"] ?? episode["subtitle"]
      box["thumbnailRenderer"] = episode["thumbnail"]
      return item(["musicTwoRowItemRenderer": box])
    }
    if let row = data["musicResponsiveListItemRenderer"] as? [String: Any],
      let song = YouTubeMusicSong(from: row)
    {
      return .song(song)
    }
    if let row = data["musicResponsiveListItemRenderer"] as? [String: Any] {
      let columns = row["flexColumns"] as? [[String: Any]] ?? []
      func text(_ index: Int) -> Any {
        guard columns.indices.contains(index),
          let renderer = columns[index]["musicResponsiveListItemFlexColumnRenderer"]
            as? [String: Any]
        else { return [:] as [String: Any] }
        return renderer["text"] ?? [:]
      }
      var box = row
      box["title"] = text(0)
      box["subtitle"] = text(1)
      box["thumbnailRenderer"] = row["thumbnail"]
      return item(["musicTwoRowItemRenderer": box])
    }
    guard let box = data["musicTwoRowItemRenderer"] as? [String: Any] else { return nil }
    let runs = (box["title"] as? [String: Any])?["runs"] as? [[String: Any]]
    let nav =
      box["navigationEndpoint"] as? [String: Any]
      ?? runs?.first?["navigationEndpoint"] as? [String: Any] ?? [:]
    let watch = nav["watchEndpoint"] as? [String: Any]
    let browse = nav["browseEndpoint"] as? [String: Any] ?? [:]
    let configs = browse["browseEndpointContextSupportedConfigs"] as? [String: Any]
    let music = configs?["browseEndpointContextMusicConfig"] as? [String: Any]
    let type = music?["pageType"] as? String ?? ""
    let subtitleRuns = (box["subtitle"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
    let artists = subtitleRuns.filter {
      discoveryBrowseEndpoint($0["navigationEndpoint"])?.browseId.hasPrefix("UC") == true
    }.compactMap { $0["text"] as? String }
    var normalized = box
    normalized["title"] = discoveryText(box["title"])
    normalized["browseId"] = browse["browseId"]
    normalized["thumbnails"] = discoveryThumbnails(box["thumbnailRenderer"])
    normalized["artists"] = artists.map { ["name": $0] }
    normalized["authors"] = artists.map { ["name": $0] }
    let browseId = browse["browseId"] as? String ?? ""
    if let videoId = watch?["videoId"] as? String, !videoId.isEmpty {
      var row = box
      row["videoId"] = videoId
      row["flexColumns"] = [
        ["musicResponsiveListItemFlexColumnRenderer": ["text": box["title"] ?? [:]]],
        ["musicResponsiveListItemFlexColumnRenderer": ["text": box["subtitle"] ?? [:]]],
      ]
      row["thumbnail"] = box["thumbnailRenderer"]
      if let song = YouTubeMusicSong(from: row) { return .song(song) }
    }
    if type == "MUSIC_PAGE_TYPE_ALBUM" || browseId.hasPrefix("MPRE") {
      normalized["year"] = subtitleRuns.compactMap { $0["text"] as? String }
        .first { $0.count == 4 && Int($0) != nil }
      return YouTubeMusicAlbum(from: normalized).map(YouTubeMusicItem.album)
    }
    if type == "MUSIC_PAGE_TYPE_PLAYLIST" || type == "MUSIC_PAGE_TYPE_PODCAST_SHOW"
      || browseId.hasPrefix("VL") || browseId.hasPrefix("MPSP")
    {
      return YouTubeMusicPlaylist(from: normalized).map(YouTubeMusicItem.playlist)
    }
    if type == "MUSIC_PAGE_TYPE_ARTIST" || browseId.hasPrefix("UC") {
      normalized["name"] = normalized["title"]
      return YouTubeMusicArtist(from: normalized).map(YouTubeMusicItem.artist)
    }
    if let playlistId = watch?["playlistId"] as? String {
      normalized["browseId"] = "VL" + playlistId
      return YouTubeMusicPlaylist(from: normalized).map(YouTubeMusicItem.playlist)
    }
    return nil
  }
}

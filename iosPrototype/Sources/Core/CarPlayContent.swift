import Foundation

/// Window over the complete library. Navigation buttons do not consume album slots.
public struct CarPlayPage: Equatable, Sendable {
  public let range: Range<Int>
  public let previous: Int?
  public let next: Int?
  public init(count: Int, offset: Int, capacity: Int) {
    let count = max(0, count)
    let size = max(1, capacity)
    let last = count == 0 ? 0 : ((count - 1) / size) * size
    let start = min(last, max(0, offset) / size * size)
    let end = min(count, start + size)
    range = start..<end
    previous = start > 0 ? max(0, start - size) : nil
    next = end < count ? end : nil
  }
}

public enum ArtworkSource {
  public static func candidates(primary: URL?, videoID: String? = nil) -> [URL] {
    var urls: [URL] = []
    if let primary, primary.scheme == "https", primary.host != nil { urls.append(primary) }
    if let id = videoID, id.count == 11,
      id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
      let url = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"), !urls.contains(url)
    {
      urls.append(url)
    }
    return urls
  }
}

/// Album rows omit per-track artists; retain the selected album's real metadata.
public enum AlbumTrackMetadata {
  public static func artist(from subtitle: String?) -> String? {
    guard let subtitle else { return nil }
    let parts = subtitle.components(separatedBy: CharacterSet(charactersIn: "•·"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { value in
        guard !value.isEmpty, !["album", "single", "ep"].contains(value.lowercased()) else {
          return false
        }
        return !(value.count == 4 && Int(value).map { (1800...2200).contains($0) } == true)
      }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

import Foundation

public struct AutoEqEntry: Identifiable, Codable, Sendable {
  public var id: String { path }
  public let name: String
  public let path: String
  public let source: String
  public static func parse(_ markdown: String) -> [Self] {
    let regex = try! NSRegularExpression(
      pattern: #"^-\s+\[(.+)\]\((\S+)\)\s+by\s+(.+?)(?:\s+on\s+.+)?$"#)
    return markdown.components(separatedBy: .newlines).compactMap { line in
      let s = line as NSString
      guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: s.length)) else {
        return nil
      }
      let path = s.substring(with: m.range(at: 2)).replacingOccurrences(
        of: "^\\./", with: "", options: .regularExpression)
      guard !path.contains(".."), !path.contains(":"), !path.hasPrefix("/"), path.contains("/")
      else { return nil }
      return Self(
        name: s.substring(with: m.range(at: 1)), path: path,
        source: s.substring(with: m.range(at: 3)))
    }
  }
  public var profileURL: URL? {
    let folder = path.split(separator: "/").last.map(String.init) ?? ""
    return URL(
      string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/" + path + "/"
        + folder + "%20FixedBandEQ.txt")
  }
}
public struct AutoEqCatalog: Sendable {
  public init() {}
  public func entries() async throws -> [AutoEqEntry] {
    let url = URL(
      string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/INDEX.md")!
    let (data, response) = try await URLSession.shared.data(
      for: URLRequest(url: url, timeoutInterval: 20))
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 4_000_000 else {
      throw OfflineError.incomplete
    }
    let entries = AutoEqEntry.parse(String(decoding: data, as: UTF8.self))
    guard !entries.isEmpty else { throw OfflineError.incomplete }
    return entries
  }
  public func profile(_ entry: AutoEqEntry) async throws -> AudioEffects {
    guard let url = entry.profileURL else { throw OfflineError.incomplete }
    let (data, response) = try await URLSession.shared.data(
      for: URLRequest(url: url, timeoutInterval: 15))
    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 50000 else {
      throw OfflineError.incomplete
    }
    var result = try AudioEffects.autoEq(String(decoding: data, as: UTF8.self))
    result.profile = entry.name + " · " + entry.source
    return result
  }
}

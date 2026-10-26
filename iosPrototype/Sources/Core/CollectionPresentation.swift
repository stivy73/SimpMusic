import Foundation

public enum CollectionLayout: String, Codable, CaseIterable, Sendable {
  case list, grid
  public var title: String { self == .list ? "Lista" : "Griglia" }
  public var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}
public enum CollectionOrder: String, Codable, CaseIterable, Sendable {
  case original, title, artist
  public var title: String {
    switch self {
    case .original: "Ordine della raccolta"
    case .title: "Titolo"
    case .artist: "Artista"
    }
  }
}
public struct CollectionPresentation: Codable, Equatable, Sendable {
  public var layout: CollectionLayout
  public var order: CollectionOrder = .original
  public var descending = false
  public var alphabeticalIndex = false
  public init(layout: CollectionLayout = .list) { self.layout = layout }

  public func sorted<T>(_ items: [T], title: (T) -> String, artist: (T) -> String) -> [T] {
    guard order != .original else { return descending ? Array(items.reversed()) : items }
    return items.enumerated().sorted { a, b in
      let lhs = order == .artist ? artist(a.element) : title(a.element)
      let rhs = order == .artist ? artist(b.element) : title(b.element)
      let primary = lhs.localizedStandardCompare(rhs)
      let secondary = title(a.element).localizedStandardCompare(title(b.element))
      let result = primary == .orderedSame ? secondary : primary
      if result == .orderedSame { return a.offset < b.offset }
      return descending ? result == .orderedDescending : result == .orderedAscending
    }.map(\.element)
  }
  public func indexKey(title: String, artist: String) -> String {
    Self.letter(order == .artist ? artist : title)
  }
  public static func letter(_ value: String) -> String {
    let folded = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "it_IT")
      )
      .uppercased(with: Locale(identifier: "it_IT"))
    guard let first = folded.first, first.isLetter else { return "#" }
    return String(first)
  }
}

@MainActor
public final class CollectionPreferences {
  private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  public func load(_ collection: String, layout: CollectionLayout) -> CollectionPresentation {
    guard let data = defaults.data(forKey: "collectionPresentation." + collection),
      let value = try? JSONDecoder().decode(CollectionPresentation.self, from: data)
    else { return CollectionPresentation(layout: layout) }
    return value
  }
  public func save(_ value: CollectionPresentation, collection: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: "collectionPresentation." + collection)
  }
}

import Foundation

enum BrowseKind:String,CaseIterable,Identifiable,Codable,Sendable {
  case songs,albums,playlists,artists
  var id:String {rawValue}
  var title:String {switch self {case .songs:"Brani";case .albums:"Album";case .playlists:"Playlist";case .artists:"Artisti"}}
}
enum BrowseOrder:String,CaseIterable,Codable {case original,title,artist
  var title:String {switch self {case .original:"Ordine originale";case .title:"Titolo";case .artist:"Artista"}}
}
enum BrowseLayout:String,CaseIterable,Codable {case list,grid
  var title:String {self == .list ? "Elenco":"Griglia"}
}
struct BrowsePreferences:Codable,Equatable {
  var layout:BrowseLayout = .list
  var order:BrowseOrder = .original
  var descending=false
  var alphabet=false
  func sorted<T>(_ items:[T],title:(T)->String,artist:(T)->String)->[T] {
    guard order != .original else {return items}
    return items.enumerated().sorted {a,b in
      let keyA=order == .title ? title(a.element):artist(a.element)
      let keyB=order == .title ? title(b.element):artist(b.element)
      let comparison=keyA.localizedStandardCompare(keyB)
      if comparison == .orderedSame {return a.offset < b.offset}
      return descending ? comparison == .orderedDescending:comparison == .orderedAscending
    }.map(\.element)
  }
  func letter(title:String,artist:String)->String {
    let value=(order == .artist ? artist:title).trimmingCharacters(in:.whitespacesAndNewlines)
      .folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"it_IT")).uppercased()
    guard let scalar=value.unicodeScalars.first,CharacterSet.letters.contains(scalar) else {return "#"}
    return String(Character(String(scalar)))
  }
  static func load(_ key:String,defaults:UserDefaults = .standard)->Self {
    guard let data=defaults.data(forKey:"browse."+key),let value=try? JSONDecoder().decode(Self.self,from:data) else {return .init()};return value
  }
  func save(_ key:String,defaults:UserDefaults = .standard) {if let data=try? JSONEncoder().encode(self) {defaults.set(data,forKey:"browse."+key)}}
}
enum BrowseHistory {
  static func adding(_ term:String,to previous:[String])->[String] {
    let value=term.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !value.isEmpty else {return previous}
    return Array(([value]+previous.filter{$0.compare(value,options:[.caseInsensitive,.diacriticInsensitive]) != .orderedSame}).prefix(20))
  }
  static func merging<T:Identifiable>(_ first:[T],_ second:[T])->[T] where T.ID:Hashable {
    var seen=Set<T.ID>();return (first+second).filter{seen.insert($0.id).inserted}
  }
  static func matches(_ query:String,title:String,artist:String)->Bool {
    let terms=query.split(whereSeparator:\.isWhitespace).map(String.init)
    let text=title+" "+artist
    return terms.allSatisfy{text.range(of:$0,options:[.caseInsensitive,.diacriticInsensitive]) != nil}
  }
}

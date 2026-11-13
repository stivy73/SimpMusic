import Foundation

enum DiscoveryPolicy {
  /// Dates supplied by Apple, not the date when an album was added to the library.
  static func recent<T>(_ values:[T],now:Date,id:(T)->String,date:(T)->Date?)->[T] {
    let start=now.addingTimeInterval(-90*24*60*60)
    var seen=Set<String>()
    return values.filter {value in
      guard let released=date(value),released>=start,released<=now else{return false}
      return seen.insert(id(value)).inserted
    }.sorted {a,b in
      let first=date(a)!,second=date(b)!
      return first==second ? id(a)<id(b):first>second
    }
  }
}

enum MusicMood:String,CaseIterable,Identifiable,Sendable {
  case relax,energy,focus,sleep,workout,happy,melancholy,romantic
  var id:String {rawValue}
  var title:String {switch self {
    case .relax:"Relax";case .energy:"Energia";case .focus:"Concentrazione";case .sleep:"Sonno"
    case .workout:"Allenamento";case .happy:"Buonumore";case .melancholy:"Malinconia";case .romantic:"Romantica"
  }}
  // These are explicit playlist searches, not invented Apple editorial categories.
  var query:String {switch self {
    case .relax:"chill relax";case .energy:"energy";case .focus:"focus concentration";case .sleep:"sleep"
    case .workout:"workout";case .happy:"happy feel good";case .melancholy:"sad melancholy";case .romantic:"romance love"
  }}
}

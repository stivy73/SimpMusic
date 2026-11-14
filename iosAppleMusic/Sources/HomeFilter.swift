// Adapted from iosPrototype/Sources/Core/HomeDiscovery.swift at 5a277798. SHA256 7525358fc584b8c9f84e4a9bfb1ec30c6b4ded6a0301d5a48d8f82ae9f2a1ea2
// Reproduce with Scripts/import_youtube_discovery.py. No YouTube browse parameters.
import Foundation

struct AppleHomeFilter:Identifiable,Hashable,Sendable {
  let id:String
  let title:String
  static let all=AppleHomeFilter(id:"all",title:"Tutto")
  static let values:[Self]=[
    all,
    .init(id:"relax",title:"Relax"),
    .init(id:"sleep",title:"Riposo"),
    .init(id:"energize",title:"Energetico"),
    .init(id:"sad",title:"Triste"),
    .init(id:"romance",title:"Romantico"),
    .init(id:"feel_good",title:"Buonumore"),
    .init(id:"workout",title:"Allenamento"),
    .init(id:"party",title:"Festa"),
    .init(id:"commute",title:"In viaggio"),
    .init(id:"focus",title:"Concentrazione"),
  ]
}

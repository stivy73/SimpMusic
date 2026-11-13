#if DEBUG && ARTWORK_LAYOUT_FIXTURE
import Foundation
@preconcurrency import MusicKit

/// Exact catalog metadata from Apple, with the artwork removed from queue snapshots.
@MainActor enum MusicArtworkFixture {
  static let json = #"""
[
  {
    "id": "1821941447",
    "type": "songs",
    "attributes": {
      "name": "Heaven Is a Place on Earth",
      "artistName": "Belinda Carlisle",
      "albumName": "Heaven on Earth (Deluxe Edition)",
      "durationInMillis": 247093,
      "artwork": {
        "width": 1500,
        "url": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/63/7e/3b/637e3b1b-afd2-5a89-84b7-c5ce4dff1c65/5032698671663.jpg/{w}x{h}{c}.{f}",
        "height": 1500,
        "textColor3": "d2d6da",
        "textColor2": "d4e2f1",
        "textColor4": "b9c6d8",
        "textColor1": "f4f6f3",
        "bgColor": "4c5577",
        "hasP3": false
      },
      "playParams": {
        "id": "1821941447",
        "kind": "song"
      }
    }
  },
  {
    "id": "1821941462",
    "type": "songs",
    "attributes": {
      "name": "Heaven Is a Place on Earth (Promo 7\" Edit)",
      "artistName": "Belinda Carlisle",
      "albumName": "Heaven on Earth (Deluxe Edition)",
      "durationInMillis": 233667,
      "artwork": {
        "width": 1500,
        "url": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/63/7e/3b/637e3b1b-afd2-5a89-84b7-c5ce4dff1c65/5032698671663.jpg/{w}x{h}{c}.{f}",
        "height": 1500,
        "textColor3": "d2d6da",
        "textColor2": "d4e2f1",
        "textColor4": "b9c6d8",
        "textColor1": "f4f6f3",
        "bgColor": "4c5577",
        "hasP3": false
      },
      "playParams": {
        "id": "1821941462",
        "kind": "song"
      }
    }
  }
]
"""#
  static var rich:[Song] {(try? JSONDecoder().decode([Song].self,from:Data(json.utf8))) ?? []}
  static func url(_ id:String)->URL? {rich.first{$0.id.rawValue==id}?.artwork?.url(width:900,height:900)}
  static func configure(_ model:MusicLibraryModel) {
    guard var values=try? JSONSerialization.jsonObject(with:Data(json.utf8)) as? [[String:Any]] else{return}
    for index in values.indices {
      var attrs=values[index]["attributes"] as? [String:Any] ?? [:];attrs.removeValue(forKey:"artwork");values[index]["attributes"]=attrs
    }
    guard let data=try? JSONSerialization.data(withJSONObject:values),let thin=try? JSONDecoder().decode([Song].self,from:data),let first=thin.first else{return}
    model.nowPlaying=first;model.position=17;model.duration=first.duration ?? 0;model.showPlayer=true
    model.artworkFixtureQueue=thin.map{MusicPlayer.Queue.Entry($0)}
    // First cover must survive the thin snapshot. The second is hydrated on opening the queue.
    if let selected=rich.first {model.rememberArtwork([selected])}
    model.songs=rich;model.queueSongs=thin
    model.accessReport="Artwork regression: raw player and queue artwork=nil; exact selected catalog image retained."
  }
}
#endif

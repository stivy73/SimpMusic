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
  // Public Apple lookup metadata for the reported ID. Deliberately break only the native image.
  static let sealJSON = #"{"id":"302788219","type":"songs","attributes":{"name":"Kiss from a Rose","artistName":"Seal","albumName":"Seal II","durationInMillis":288427,"playParams":{"id":"302788219","kind":"song"},"artwork":{"width":100,"height":100,"url":"https://127.0.0.1:18714/missing.jpg"}}}"#
  static var rich:[Song] {
    let belinda=(try? JSONDecoder().decode([Song].self,from:Data(json.utf8))) ?? []
    let seal=try? JSONDecoder().decode(Song.self,from:Data(sealJSON.utf8))
    return belinda+[seal].compactMap{$0}
  }
  static func url(_ id:String)->URL? {rich.first{$0.id.rawValue==id}?.artwork?.url(width:900,height:900)}
  static func configure(_ model:MusicLibraryModel) {
    guard var values=try? JSONSerialization.jsonObject(with:Data(json.utf8)) as? [[String:Any]] else{return}
    for index in values.indices {
      var attrs=values[index]["attributes"] as? [String:Any] ?? [:];attrs.removeValue(forKey:"artwork");values[index]["attributes"]=attrs
    }
    guard let data=try? JSONSerialization.data(withJSONObject:values),let thin=try? JSONDecoder().decode([Song].self,from:data),let first=thin.first else{return}
    guard let seal=rich.last else{return}
    model.nowPlaying=seal;model.position=48;model.duration=seal.duration ?? 0;model.showPlayer=true
    let entries=([seal]+thin).map{MusicPlayer.Queue.Entry($0)}
    model.artworkFixtureQueue=[]
    model.playbackQueueSnapshot.capture(entries,current:entries.first?.id)
    // Native queue is empty, as in the device report. Seal must use the live public-ID fallback.
    if let selected=rich.first {model.rememberArtwork([selected])}
    model.rememberArtwork([seal]);model.songs=rich;model.queueSongs=[seal]+thin
    model.accessReport="Artwork regression: Seal image unavailable; native queue empty; real queue snapshot retained."
  }
}
#endif

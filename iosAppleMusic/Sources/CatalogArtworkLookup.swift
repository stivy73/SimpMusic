import Foundation
import CoreFoundation

/// Public Apple metadata for the exact catalog ID. Never matches a title or substitutes audio.
enum CatalogArtworkLookup {
  enum Failure:Error {case invalidRequest,invalidResponse}
  static func request(id:String,country:String) throws -> URLRequest {
    guard ArtworkIdentity.isCatalogSong(id),country.count==2,country.utf8.allSatisfy({(65...90).contains($0)||(97...122).contains($0)}) else{throw Failure.invalidRequest}
    var url=URLComponents(string:"https://itunes.apple.com/lookup")!
    url.queryItems=[.init(name:"id",value:id),.init(name:"country",value:country.lowercased()),.init(name:"entity",value:"song")]
    var request=URLRequest(url:url.url!);request.timeoutInterval=15
    return request
  }
  static func artwork(_ data:Data,status:Int,id:String) throws -> URL? {
    guard status==200,data.count<=1024*1024,
      let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],
      let values=root["results"] as? [[String:Any]] else{throw Failure.invalidResponse}
    let matches=values.filter { item in
      guard item["wrapperType"] as? String=="track",item["kind"] as? String=="song",
        let number=item["trackId"] as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID() else{return false}
      return number.stringValue==id
    }
    guard matches.count<=1 else{throw Failure.invalidResponse}
    guard let item=matches.first else{return nil}
    for key in ["artworkUrl600","artworkUrl100","artworkUrl60"] {
      if let raw=item[key] as? String,let url=URL(string:raw),url.scheme=="https",
        let host=url.host?.lowercased(),host=="mzstatic.com" || host.hasSuffix(".mzstatic.com"),url.user==nil,url.password==nil {return url}
    }
    return nil
  }
}

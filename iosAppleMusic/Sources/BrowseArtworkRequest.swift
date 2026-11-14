import Foundation

enum BrowseArtworkRequest {
  enum Kind:String,Sendable {case songs,albums,playlists,artists}
  struct Identity:Sendable {
    let kind:Kind
    let id:String
    var library:Bool {
      switch kind {case .songs:id.hasPrefix("i.");case .albums:id.hasPrefix("l.");case .playlists:id.hasPrefix("p.");case .artists:id.hasPrefix("r.")}
    }
  }
  enum Failure:Error,CustomNSError {
    case invalidIdentity,invalidResponse,http(Int)
    static var errorDomain:String {"AppleBrowseArtwork"}
    var errorCode:Int {switch self {case .invalidIdentity:-1;case .invalidResponse:-2;case .http(let code):code}}
  }
  private static func validID(_ id:String)->Bool {id != "0" && id.count<=200 && id.range(of:#"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,options:.regularExpression) != nil}
  static func identity(_ key:String) throws -> Identity {
    let parts=key.split(separator:":",maxSplits:1).map(String.init)
    guard parts.count==2,let kind=["s":Kind.songs,"a":.albums,"p":.playlists,"r":.artists][parts[0]],
      validID(parts[1]) else{throw Failure.invalidIdentity}
    return .init(kind:kind,id:parts[1])
  }
  static func request(_ identity:Identity,country:String,catalogMapping:Bool=false) throws -> URLRequest {
    guard country.count==2,country.utf8.allSatisfy({(65...90).contains($0)||(97...122).contains($0)}),
      validID(identity.id),
      !catalogMapping || identity.library else{throw Failure.invalidIdentity}
    let root=identity.library ? "/v1/me/library":"/v1/catalog/"+country.lowercased()
    let path=root+"/"+identity.kind.rawValue+"/"+identity.id+(catalogMapping ? "/catalog":"")
    var request=URLRequest(url:URL(string:"https://api.music.apple.com"+path)!)
    request.timeoutInterval=15;return request
  }
  private static func rows(_ data:Data,status:Int) throws -> [[String:Any]] {
    guard status==200 else{throw Failure.http(status)}
    guard data.count<=5*1024*1024,
      let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["errors"]==nil,
      let values=root["data"] as? [[String:Any]],values.count<=1 else{throw Failure.invalidResponse}
    return values
  }
  static func artwork(_ data:Data,status:Int,identity:Identity) throws -> URL? {
    guard let row=try rows(data,status:status).first else{return nil}
    let type=(identity.library ? "library-":"")+identity.kind.rawValue
    guard row["id"] as? String==identity.id,row["type"] as? String==type else{throw Failure.invalidResponse}
    guard let attrs=row["attributes"] as? [String:Any],let art=attrs["artwork"] as? [String:Any],let raw=art["url"] as? String else{return nil}
    guard var parts=URLComponents(string:raw),parts.scheme=="https",parts.user==nil,parts.password==nil,
      let host=parts.host?.lowercased(),host=="mzstatic.com" || host.hasSuffix(".mzstatic.com") else{throw Failure.invalidResponse}
    for (token,value) in [("w","600"),("h","600"),("c","bb"),("f","jpg")] {
      parts.percentEncodedPath=parts.percentEncodedPath.replacingOccurrences(of:"%7B"+token+"%7D",with:value,options:.caseInsensitive)
    }
    return parts.url
  }
  static func catalogIdentity(_ data:Data,status:Int,source:Identity) throws -> Identity? {
    guard source.library else{throw Failure.invalidIdentity}
    guard let row=try rows(data,status:status).first else{return nil}
    guard row["type"] as? String==source.kind.rawValue,let id=row["id"] as? String,
      validID(id) else{throw Failure.invalidResponse}
    let result=Identity(kind:source.kind,id:id)
    guard !result.library else{throw Failure.invalidResponse}
    return result
  }
}

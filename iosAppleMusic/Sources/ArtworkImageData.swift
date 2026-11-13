import Foundation

/// Shared image transfers with an explicit deadline and observable HTTP failures.
actor ArtworkImageData {
  static let shared=ArtworkImageData()
  typealias Fetch=@Sendable (URLRequest) async throws -> (Data,HTTPURLResponse)
  struct Failure:Error,CustomNSError {
    let code:Int
    static var errorDomain:String {"AppleArtworkImage"}
    var errorCode:Int {code}
  }
  private let cache=NSCache<NSURL,NSData>()
  private var jobs:[URL:Task<Data,Error>]=[:]
  private let fetch:Fetch
  init(fetch:@escaping Fetch=ArtworkImageData.network) {
    self.fetch=fetch;cache.totalCostLimit=40*1024*1024;cache.countLimit=256
  }
  private static let session:URLSession = {
    let config=URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest=8;config.timeoutIntervalForResource=12
    config.waitsForConnectivity=false;config.httpMaximumConnectionsPerHost=4
    return URLSession(configuration:config)
  }()
  private static func network(_ request:URLRequest) async throws -> (Data,HTTPURLResponse) {
    let (data,response)=try await session.data(for:request)
    guard let response=response as? HTTPURLResponse else{throw Failure(code:-1)}
    return(data,response)
  }
  static func candidates(_ url:URL)->[URL] {
    guard var parts=URLComponents(url:url,resolvingAgainstBaseURL:false),parts.query==nil,parts.fragment==nil,
      let host=parts.host?.lowercased(),host=="mzstatic.com" || host.hasSuffix(".mzstatic.com"),
      parts.path.hasPrefix("/image/thumb/"),["100x100bb.jpg","60x60bb.jpg"].contains(url.lastPathComponent) else{return [url]}
    parts.path=(parts.path as NSString).deletingLastPathComponent+"/900x900bb.jpg"
    guard let large=parts.url else{return [url]}
    return [large,url]
  }
  func load(_ url:URL) async throws -> Data {
    guard url.scheme=="https",url.user==nil,url.password==nil else{throw Failure(code:-2)}
    if let data=cache.object(forKey:url as NSURL) {return data as Data}
    if let job=jobs[url] {return try await job.value}
    let fetch=fetch
    let job=Task<Data,Error> {
      var last:Error=Failure(code:-1)
      for candidate in Self.candidates(url) {
        do {
          var request=URLRequest(url:candidate);request.timeoutInterval=8
          let (data,response)=try await fetch(request)
          guard (200...299).contains(response.statusCode) else{throw Failure(code:response.statusCode)}
          guard !data.isEmpty,data.count<=15*1024*1024,response.mimeType?.hasPrefix("image/")==true else{throw Failure(code:-3)}
          return data
        } catch {try Task.checkCancellation();last=error}
      }
      throw last
    }
    jobs[url]=job
    do {let data=try await job.value;cache.setObject(data as NSData,forKey:url as NSURL,cost:data.count);jobs[url]=nil;return data}
    catch {jobs[url]=nil;throw error}
  }
}

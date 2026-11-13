import Foundation
import Combine

private actor ArtworkReadGate {
  private var active=0
  private var waiting:[CheckedContinuation<Void,Never>]=[]
  func acquire() async {
    if active<3 {active+=1;return}
    await withCheckedContinuation{waiting.append($0)}
  }
  func release() {
    if waiting.isEmpty {active-=1} else {waiting.removeFirst().resume()}
  }
}

/// Artwork belongs to a media ID, never to a queue position or a matching title.
/// A thin queue snapshot cannot erase a cover obtained from the selected song.
@MainActor final class PlaybackArtwork:ObservableObject {
  @Published private(set) var urls:[String:URL]=[:]
  @Published private(set) var status:[String:String]=[:]
  private var jobs:[String:Task<Void,Never>]=[:]
  private var unavailableUntil:[String:Date]=[:]
  private var order:[String]=[]
  private var revision=UUID()
  private let gate=ArtworkReadGate()
  private let fetch:@Sendable (String) async throws -> URL?
  private let now:()->Date
  init(now:@escaping ()->Date=Date.init,fetch:@escaping @Sendable (String) async throws -> URL?) {self.now=now;self.fetch=fetch}
  func remember(id:String,url:URL?,replace:Bool=true) {
    guard !id.isEmpty,let url=PlaybackArtworkURL.resolve(url),replace || urls[id]==nil else{return}
    guard urls[id] != url else{return}
    urls[id]=url;unavailableUntil[id]=nil;status[id]="disponibile"
    order.removeAll{$0==id};order.append(id)
    while order.count>512 {let removed=order.removeFirst();urls[removed]=nil;status[removed]=nil}
  }
  func url(id:String,native:URL?=nil)->URL? {PlaybackArtworkURL.resolve(native) ?? urls[id]}
  func reset() {
    revision=UUID();jobs.values.forEach{$0.cancel()};jobs=[:];urls=[:];status=[:];order=[];unavailableUntil=[:]
  }
  func load(id:String) async {
    guard !id.isEmpty,urls[id]==nil else{return}
    if let job=jobs[id] {await job.value;return}
    if let until=unavailableUntil[id],until>now() {return}
    let gate=gate,fetch=fetch,token=revision
    status[id]="recupero in corso"
    let job=Task { [weak self] in
      await gate.acquire()
      do {
        try Task.checkCancellation()
        let result=try await fetch(id)
        await gate.release()
        guard let self,self.revision==token,!Task.isCancelled else{return}
        if let result {self.remember(id:id,url:result,replace:false)}
        else if self.urls[id]==nil {self.status[id]="non restituita da Apple Music";self.unavailableUntil[id]=self.now().addingTimeInterval(30)}
      } catch {
        await gate.release()
        guard let self,self.revision==token,!Task.isCancelled,self.urls[id]==nil else{return}
        let value=error as NSError
        self.status[id]="errore \(value.domain) \(value.code)"
        self.unavailableUntil[id]=self.now().addingTimeInterval(30)
      }
    }
    jobs[id]=job;await job.value;guard revision==token else{return};jobs[id]=nil
    if unavailableUntil.count>512 {unavailableUntil=unavailableUntil.filter{$0.value>now()};status=status.filter{urls[$0.key] != nil || jobs[$0.key] != nil || unavailableUntil[$0.key] != nil}}
  }
}

enum PlaybackArtworkURL {
  /// MusicKit resolves width/height but some Apple templates retain crop/format tokens.
  static func resolve(_ url:URL?)->URL? {
    guard let url else{return nil}
    guard var parts=URLComponents(url:url,resolvingAgainstBaseURL:false),parts.scheme=="https",
      let host=parts.host?.lowercased(),host=="mzstatic.com" || host.hasSuffix(".mzstatic.com") else{return url}
    parts.percentEncodedPath=parts.percentEncodedPath
      .replacingOccurrences(of:"%7Bc%7D",with:"bb",options:.caseInsensitive)
      .replacingOccurrences(of:"%7Bf%7D",with:"jpg",options:.caseInsensitive)
    return parts.url
  }
}

enum ArtworkIdentity {
  static func isCatalogSong(_ id:String)->Bool {!id.isEmpty && id != "0" && id.count<=24 && id.utf8.allSatisfy{(48...57).contains($0)}}
  static func isLibrarySong(_ id:String)->Bool {id.hasPrefix("i.") && id.count>2 && id.count<=160 && id.range(of:#"^[A-Za-z0-9._-]+$"#,options:.regularExpression) != nil}
}

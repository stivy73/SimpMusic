import XCTest
@testable import LyricsContract

private actor ArtworkFetchProbe {
  var calls=0,active=0,maximum=0
  let result:URL?
  init(_ result:URL?=URL(string:"https://example.test/catalog.jpg")){self.result=result}
  func fetch(_ id:String) async throws -> URL? {
    calls+=1;active+=1;maximum=max(maximum,active)
    defer{active-=1}
    try await Task.sleep(for:.milliseconds(40))
    return result
  }
}
final class PlaybackArtworkTests:XCTestCase {
  @MainActor func testAppleImageTemplatesBecomeLoadableInPlayerAndQueue() {
    let cache=PlaybackArtwork(fetch:{_ in nil})
    let template=URL(string:"https://is1-ssl.mzstatic.com/image/thumb/catalog/source/900x900{c}.{f}")!
    let image=URL(string:"https://is1-ssl.mzstatic.com/image/thumb/catalog/source/900x900bb.jpg")!
    cache.remember(id:"1",url:template)
    XCTAssertEqual(cache.url(id:"1"),image)
    XCTAssertEqual(cache.url(id:"2",native:template),image)
    let formatOnly=URL(string:"https://is1.mzstatic.com/image/thumb/source/300x300bb.%7bf%7d")!
    XCTAssertEqual(PlaybackArtworkURL.resolve(formatOnly)?.lastPathComponent,"300x300bb.jpg")
  }
  func testImageURLResolutionPreservesConcreteURLsAndDoesNotRewriteOtherHostsOrQuery() {
    for raw in ["https://is1.mzstatic.com/image/900x900bb.png?format=%7Bf%7D",
      "https://example.test/image/900x900%7Bc%7D.%7Bf%7D",
      "https://mzstatic.com.example.test/image/900x900%7Bc%7D.%7Bf%7D"] {
      let url=URL(string:raw)!
      XCTAssertEqual(PlaybackArtworkURL.resolve(url),url)
    }
    XCTAssertNil(PlaybackArtworkURL.resolve(nil))
  }
  @MainActor func testThinQueueSnapshotCannotEraseKnownCoverOrLeakItToAnotherTrack() {
    let cache=PlaybackArtwork(fetch:{_ in nil}),url=URL(string:"https://example.test/exact-album.jpg")!
    cache.remember(id:"song-1",url:url);cache.remember(id:"song-1",url:nil)
    XCTAssertEqual(cache.url(id:"song-1"),url);XCTAssertNil(cache.url(id:"song-2"))
    cache.remember(id:"song-1",url:URL(string:"https://example.test/fallback.jpg"),replace:false)
    XCTAssertEqual(cache.url(id:"song-1"),url)
  }
  @MainActor func testPlayerAndQueueShareOneInFlightLookup() async {
    let fetch=ArtworkFetchProbe(),cache=PlaybackArtwork(fetch:fetch.fetch)
    async let player:Void=cache.load(id:"1821941447")
    async let queue:Void=cache.load(id:"1821941447")
    _ = await(player,queue)
    let calls=await fetch.calls;XCTAssertEqual(calls,1);XCTAssertNotNil(cache.url(id:"1821941447"))
  }
  @MainActor func testNativeMetadataArrivingDuringLookupTakesPriority() async throws {
    let fetch=ArtworkFetchProbe(),cache=PlaybackArtwork(fetch:fetch.fetch)
    let work=Task{await cache.load(id:"1")}
    while await fetch.calls==0 {await Task.yield()}
    let native=URL(string:"https://example.test/native.jpg")!;cache.remember(id:"1",url:native)
    await work.value;XCTAssertEqual(cache.url(id:"1"),native)
  }
  @MainActor func testFailedLookupDoesNotRepeatOnEveryPlaybackTickAndCanRetry() async {
    let fetch=ArtworkFetchProbe(nil);var now=Date(timeIntervalSince1970:1_000)
    let cache=PlaybackArtwork(now:{now},fetch:fetch.fetch)
    await cache.load(id:"1");await cache.load(id:"1")
    let first=await fetch.calls;XCTAssertEqual(first,1)
    now=now.addingTimeInterval(31);await cache.load(id:"1")
    let second=await fetch.calls;XCTAssertEqual(second,2)
  }
  @MainActor func testQueueArtworkReadsHaveBoundedConcurrency() async {
    let fetch=ArtworkFetchProbe(),cache=PlaybackArtwork(fetch:fetch.fetch)
    await withTaskGroup(of:Void.self){group in for id in 1...10 {group.addTask{await cache.load(id:String(id))}}}
    let peak=await fetch.maximum,calls=await fetch.calls
    XCTAssertEqual(calls,10);XCTAssertLessThanOrEqual(peak,3);XCTAssertEqual(cache.urls.count,10)
  }
  @MainActor func testResetDiscardsOutstandingLookup() async {
    let fetch=ArtworkFetchProbe(),cache=PlaybackArtwork(fetch:fetch.fetch)
    let work=Task{await cache.load(id:"1")}
    while await fetch.calls==0 {await Task.yield()}
    cache.reset();await work.value;XCTAssertNil(cache.url(id:"1"));XCTAssertTrue(cache.status.isEmpty)
  }
  func testOnlyExactNativeSongIDsCanBeResolved() {
    XCTAssertTrue(ArtworkIdentity.isCatalogSong("1821941447"));XCTAssertTrue(ArtworkIdentity.isLibrarySong("i.x123ABC"))
    for id in ["0","","Heaven Is a Place on Earth","entry-uuid","123/../../songs","https://example.test/x"] {XCTAssertFalse(ArtworkIdentity.isCatalogSong(id))}
    for id in ["i.","i.foo/bar","i.foo?token=x","r.artist","p.playlist"] {XCTAssertFalse(ArtworkIdentity.isLibrarySong(id))}
  }
}

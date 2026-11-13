import XCTest
@testable import LyricsContract

private actor ImageTransferProbe {
  var calls=0
  func fetch(_ request:URLRequest) async throws -> (Data,HTTPURLResponse) {
    calls+=1;try await Task.sleep(for:.milliseconds(30))
    return(Data([1,2,3]),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"image/jpeg"])!)
  }
}
final class ArtworkImageDataTests:XCTestCase {
  func testAppleThumbnailCanUseSameAssetAtHighResolutionWithoutRewritingSignedURLs() {
    let url=URL(string:"https://is1-ssl.mzstatic.com/image/thumb/Features115/source.jpg/100x100bb.jpg")!
    XCTAssertEqual(ArtworkImageData.candidates(url).map(\.lastPathComponent),["900x900bb.jpg","100x100bb.jpg"])
    for raw in [url.absoluteString+"?token=private","https://other.test/image/thumb/source/100x100bb.jpg","https://is1.mzstatic.com/other/100x100bb.jpg"] {
      let original=URL(string:raw)!;XCTAssertEqual(ArtworkImageData.candidates(original),[original])
    }
  }
  func testUnavailableHighResolutionFallsBackToExactOriginalThumbnail() async throws {
    let loader=ArtworkImageData(fetch:{request in
      let large=request.url!.lastPathComponent=="900x900bb.jpg"
      return(Data([1]),HTTPURLResponse(url:request.url!,statusCode:large ? 404:200,httpVersion:nil,headerFields:["Content-Type":large ? "text/plain":"image/jpeg"])!)
    })
    let data=try await loader.load(URL(string:"https://is1.mzstatic.com/image/thumb/source/100x100bb.jpg")!)
    XCTAssertEqual(data,Data([1]))
  }
  func testPlayerAndQueueShareTransferAndCachedBytes() async throws {
    let probe=ImageTransferProbe(),loader=ArtworkImageData(fetch:probe.fetch),url=URL(string:"https://is1.mzstatic.com/cover.jpg")!
    async let player=loader.load(url);async let queue=loader.load(url)
    let (a,b)=try await(player,queue);XCTAssertEqual(a,b)
    let cached=try await loader.load(url);XCTAssertEqual(cached,a)
    let calls=await probe.calls;XCTAssertEqual(calls,1)
  }
  func test403AndHTMLCannotBeReportedAsLoadedImages() async {
    let url=URL(string:"https://is1.mzstatic.com/cover.jpg")!
    for (status,mime,code) in [(403,"text/plain",403),(200,"text/html",-3)] {
      let loader=ArtworkImageData(fetch:{request in (Data([1]),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":mime])!)})
      do {_ = try await loader.load(url);XCTFail("Invalid image accepted")}
      catch {XCTAssertEqual((error as NSError).domain,"AppleArtworkImage");XCTAssertEqual((error as NSError).code,code)}
    }
  }
  func testNetworkFailureReachesRecoveryAndRequestHasDeadline() async {
    let loader=ArtworkImageData(fetch:{request in
      XCTAssertEqual(request.timeoutInterval,8)
      throw URLError(.timedOut)
    })
    do {_ = try await loader.load(URL(string:"https://is1.mzstatic.com/cover.jpg")!);XCTFail("Timeout ignored")}
    catch {XCTAssertEqual((error as NSError).code,NSURLErrorTimedOut)}
  }
}

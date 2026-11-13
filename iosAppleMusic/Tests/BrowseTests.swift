import XCTest
@testable import LyricsContract

private struct Record:Identifiable,Sendable,Equatable {let id:Int;var title:String="";var artist:String=""}
final class BrowseTests:XCTestCase {
  func testSortingOnlyChangesPresentationAndKeepsTiesStable() {
    let values=[Record(id:1,title:"Zulu"),Record(id:2,title:"Alpha"),Record(id:3,title:"Alpha")]
    var p=BrowsePreferences();XCTAssertEqual(p.sorted(values,title:{$0.title},artist:{$0.artist}).map(\.id),[1,2,3])
    p.order = .title;XCTAssertEqual(p.sorted(values,title:{$0.title},artist:{$0.artist}).map(\.id),[2,3,1])
    p.descending=true;XCTAssertEqual(p.sorted(values,title:{$0.title},artist:{$0.artist}).map(\.id),[1,2,3])
    XCTAssertEqual(values.map(\.id),[1,2,3])
  }
  func testIndexFilterAndHistoryNormalizeWithoutInventingItems() {
    var p=BrowsePreferences();p.order = .title
    XCTAssertEqual(p.letter(title:"Écho",artist:""),"E");XCTAssertEqual(p.letter(title:"1984",artist:""),"#")
    XCTAssertTrue(BrowseHistory.matches("belinda earth",title:"Heaven on Earth",artist:"Belinda Carlisle"))
    XCTAssertFalse(BrowseHistory.matches("seal earth",title:"Heaven on Earth",artist:"Belinda Carlisle"))
    XCTAssertEqual(BrowseHistory.adding("  SEAL ",to:["Seal","Other"]),["SEAL","Other"])
    XCTAssertEqual(BrowseHistory.adding("new",to:(0...30).map(String.init)).count,20)
    XCTAssertEqual(BrowseHistory.merging([Record(id:1),Record(id:2)],[Record(id:2),Record(id:3)]).map(\.id),[1,2,3])
  }
  func testPreferencesPersistPerCollection() {
    let name="BrowseTests."+UUID().uuidString;let defaults=UserDefaults(suiteName:name)!
    defer{defaults.removePersistentDomain(forName:name)}
    var p=BrowsePreferences();p.layout = .grid;p.order = .artist;p.alphabet=true;p.save("albums",defaults:defaults)
    XCTAssertEqual(BrowsePreferences.load("albums",defaults:defaults),p)
    XCTAssertEqual(BrowsePreferences.load("songs",defaults:defaults),BrowsePreferences())
  }
  @MainActor func testOlderQueryCannotPublishAfterNewQuery() async {
    let page=BrowsePage<Record>(),started=expectation(description:"old request started")
    var finish:CheckedContinuation<BrowseBatch<Record>,Never>?
    let old=Task {await page.load {await withCheckedContinuation {finish=$0;started.fulfill()}}}
    await fulfillment(of:[started],timeout:2)
    await page.load {BrowseBatch(items:[Record(id:2)])}
    finish?.resume(returning:BrowseBatch(items:[Record(id:1)]));await old.value
    XCTAssertEqual(page.items.map(\.id),[2]);XCTAssertFalse(page.busy)
  }
  @MainActor func testPaginationFailureKeepsResultsAndRetryCursor() async {
    let page=BrowsePage<Record>();var attempts=0
    await page.load {BrowseBatch(items:[Record(id:1)],next:{
      attempts+=1
      if attempts==1 {throw URLError(.timedOut)}
      return BrowseBatch(items:[Record(id:1),Record(id:2)])
    })}
    await page.more();XCTAssertEqual(page.items.map(\.id),[1]);XCTAssertNotNil(page.moreError);XCTAssertTrue(page.hasMore)
    await page.more();XCTAssertEqual(page.items.map(\.id),[1,2]);XCTAssertNil(page.moreError);XCTAssertFalse(page.hasMore)
  }
  @MainActor func testResetDiscardsOutstandingNextPage() async {
    let page=BrowsePage<Record>(),started=expectation(description:"next started")
    var finish:CheckedContinuation<BrowseBatch<Record>,Never>?
    await page.load {BrowseBatch(items:[Record(id:1)],next:{await withCheckedContinuation{finish=$0;started.fulfill()}})}
    let old=Task{await page.more()};await fulfillment(of:[started],timeout:2)
    page.reset();finish?.resume(returning:BrowseBatch(items:[Record(id:2)]));await old.value
    XCTAssertTrue(page.items.isEmpty);XCTAssertFalse(page.hasMore);XCTAssertFalse(page.moreBusy)
  }
}

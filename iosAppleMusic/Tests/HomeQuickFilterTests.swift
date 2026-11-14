import XCTest
@testable import LyricsContract

private struct FilterItem:Identifiable,Sendable {let id:String}
final class HomeQuickFilterTests:XCTestCase {
  private func filter(_ id:String)->AppleHomeFilter {AppleHomeFilter.values.first{$0.id==id}!}

  @MainActor func testNewFilterWinsEvenIfCanceledProviderCompletesLate() async {
    let started=expectation(description:"Relax request started")
    var complete:CheckedContinuation<BrowseBatch<FilterItem>,Never>?
    let home=HomeQuickFilterStore<FilterItem> {filter in
      if filter.id=="relax" {return await withCheckedContinuation{complete=$0;started.fulfill()}}
      return .init(items:[.init(id:filter.id)])
    }
    let old=Task{await home.select(filter("relax"))}
    await fulfillment(of:[started],timeout:2)
    await home.select(filter("workout"))
    complete?.resume(returning:.init(items:[.init(id:"late-relax")]))
    await old.value
    XCTAssertEqual(home.selectedFilter.id,"workout")
    XCTAssertEqual(home.page.items.map(\.id),["workout"])
    XCTAssertFalse(home.page.busy);XCTAssertNil(home.page.error)
  }
  @MainActor func testAllCancelsFilterAndRestoresUnfilteredHomeWithoutCatalogSearch() async {
    let started=expectation(description:"Filter started")
    var complete:CheckedContinuation<BrowseBatch<FilterItem>,Never>?
    var calls:[String]=[]
    let home=HomeQuickFilterStore<FilterItem> {filter in
      calls.append(filter.id)
      return await withCheckedContinuation{complete=$0;started.fulfill()}
    }
    let old=Task{await home.select(filter("sleep"))}
    await fulfillment(of:[started],timeout:2)
    await home.select(.all);await home.refresh()
    complete?.resume(returning:.init(items:[.init(id:"late-sleep")]))
    await old.value
    XCTAssertEqual(home.selectedFilter,.all);XCTAssertTrue(home.page.items.isEmpty)
    XCTAssertFalse(home.page.busy);XCTAssertEqual(calls,["sleep"])
  }
  @MainActor func testRefreshKeepsSelectedFilterAndSameTapDoesNotDuplicateRequest() async {
    var calls:[String]=[]
    let home=HomeQuickFilterStore<FilterItem> {filter in
      calls.append(filter.id);return .init(items:[.init(id:String(calls.count))])
    }
    await home.select(filter("commute"));await home.select(filter("commute"))
    XCTAssertEqual(calls,["commute"])
    await home.refresh()
    XCTAssertEqual(home.selectedFilter.id,"commute")
    XCTAssertEqual(calls,["commute","commute"])
    XCTAssertEqual(home.page.items.map(\.id),["2"])
  }
  @MainActor func testRetryRecoversFailedSelectionWithoutFallingBackToAll() async {
    var calls=0
    let home=HomeQuickFilterStore<FilterItem> {filter in
      calls+=1
      if calls==1 {throw URLError(.timedOut)}
      return .init(items:[.init(id:filter.id)])
    }
    await home.select(filter("party"))
    XCTAssertNotNil(home.page.error);XCTAssertFalse(home.page.busy)
    await home.refresh()
    XCTAssertNil(home.page.error);XCTAssertEqual(home.selectedFilter.id,"party")
    XCTAssertEqual(home.page.items.map(\.id),["party"])
  }
  @MainActor func testChangingFilterDiscardsOldNextPageAndRetainsNewCursor() async {
    let started=expectation(description:"Old continuation started")
    var complete:CheckedContinuation<BrowseBatch<FilterItem>,Never>?
    let home=HomeQuickFilterStore<FilterItem> {filter in
      if filter.id=="relax" {return .init(items:[.init(id:"relax")],next:{
        await withCheckedContinuation{complete=$0;started.fulfill()}
      })}
      return .init(items:[.init(id:"focus")],next:{.init(items:[.init(id:"focus-2")])})
    }
    await home.select(filter("relax"))
    let old=Task{await home.page.more()}
    await fulfillment(of:[started],timeout:2)
    await home.select(filter("focus"))
    complete?.resume(returning:.init(items:[.init(id:"late-relax")]))
    await old.value;await home.page.more()
    XCTAssertEqual(home.page.items.map(\.id),["focus","focus-2"])
    XCTAssertFalse(home.page.hasMore)
  }
  func testOnlyAllUsesPersonalHomeAndEveryOriginalFilterHasAppleQuery() {
    XCTAssertEqual(AppleHomeFilter.values.count,11)
    XCTAssertEqual(Set(AppleHomeFilter.values.map(\.id)).count,11)
    XCTAssertNil(AppleHomeFilter.all.catalogQuery)
    XCTAssertTrue(AppleHomeFilter.values.dropFirst().allSatisfy{!($0.catalogQuery ?? "").isEmpty})
    XCTAssertNil(AppleHomeFilter(id:"unsupported",title:"Unsupported").catalogQuery)
  }
}

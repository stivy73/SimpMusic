import Foundation
import Combine

extension AppleHomeFilter {
  // Apple exposes catalog playlist search rather than YouTube's Home params.
  // These terms retrieve new catalog results, not guesses about library moods.
  var catalogQuery:String? {
    switch id {
    case "relax":"chill relax"
    case "sleep":"sleep"
    case "energize":"energy"
    case "sad":"sad melancholy"
    case "romance":"romance love"
    case "feel_good":"happy feel good"
    case "workout":"workout"
    case "party":"party"
    case "commute":"road trip driving"
    case "focus":"focus concentration"
    default:nil
    }
  }
}

/// Mirrors HomeModel.select/invalidate from the YouTube version. The provider
/// returns native Apple batches; BrowsePage retains each result's cursor.
@MainActor final class HomeQuickFilterStore<Item:Identifiable & Sendable>:ObservableObject where Item.ID:Hashable {
  typealias Fetch=@MainActor (AppleHomeFilter) async throws -> BrowseBatch<Item>
  @Published private(set) var selectedFilter=AppleHomeFilter.all
  let page=BrowsePage<Item>()
  private let fetch:Fetch
  private var request:Task<Void,Never>?
  private var changes:AnyCancellable?
  init(fetch:@escaping Fetch) {
    self.fetch=fetch
    changes=page.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
  }
  func select(_ filter:AppleHomeFilter) async {
    guard filter != selectedFilter else{return}
    selectedFilter=filter
    request?.cancel();page.reset()
    guard filter != .all else{return}
    await refresh()
  }
  func refresh() async {
    request?.cancel();page.reset()
    let filter=selectedFilter
    guard filter != .all else{return}
    let job=Task { [weak self] in
      guard let self,self.selectedFilter==filter,!Task.isCancelled else{return}
      await self.page.load{try await self.fetch(filter)}
    }
    request=job
    await withTaskCancellationHandler {await job.value} onCancel:{job.cancel()}
  }
}

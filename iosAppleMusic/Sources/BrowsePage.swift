import Foundation
import Combine

@MainActor struct BrowseBatch<Item:Identifiable & Sendable> where Item.ID:Hashable {
  let items:[Item]
  var warning:String?=nil
  var next:(@MainActor () async throws -> BrowseBatch<Item>)?=nil
}
/// Each section owns its cursor. Old responses cannot replace a newer query.
@MainActor final class BrowsePage<Item:Identifiable & Sendable>:ObservableObject where Item.ID:Hashable {
  @Published private(set) var items:[Item]=[]
  @Published private(set) var busy=false
  @Published private(set) var moreBusy=false
  @Published private(set) var error:String?
  @Published private(set) var moreError:String?
  @Published private(set) var warning:String?
  @Published private(set) var hasMore=false
  private var revision=UUID()
  private var next:(@MainActor () async throws -> BrowseBatch<Item>)?
  func reset() {revision=UUID();items=[];busy=false;moreBusy=false;error=nil;moreError=nil;warning=nil;next=nil;hasMore=false}
  func load(_ fetch:@MainActor () async throws -> BrowseBatch<Item>) async {
    reset();let token=revision;busy=true
    defer{if token==revision {busy=false}}
    do {
      let batch=try await fetch();try Task.checkCancellation();guard token==revision else{return}
      items=BrowseHistory.merging(batch.items,[]);next=batch.next;hasMore=next != nil;warning=batch.warning
    } catch {if token==revision && !Task.isCancelled {self.error=error.localizedDescription}}
  }
  func more() async {
    guard !busy,!moreBusy,let fetch=next else{return}
    let token=revision;moreBusy=true;moreError=nil
    defer{if token==revision {moreBusy=false}}
    do {
      let batch=try await fetch();try Task.checkCancellation();guard token==revision else{return}
      items=BrowseHistory.merging(items,batch.items);next=batch.next;hasMore=next != nil
      if let warning=batch.warning {self.warning=warning}
    } catch {if token==revision && !Task.isCancelled {moreError=error.localizedDescription}}
  }
}

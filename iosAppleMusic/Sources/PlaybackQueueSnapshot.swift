import Foundation

/// Retains real queue occurrences, including duplicate songs, across native queue loss.
struct PlaybackQueueSnapshot<Entry:Identifiable & Equatable> {
  private(set) var entries:[Entry]=[]
  private(set) var currentID:Entry.ID?
  mutating func capture(_ native:[Entry],current:Entry.ID?) {
    guard !native.isEmpty else{return}
    entries=native
    let selected=current ?? currentID
    currentID=native.contains(where:{$0.id==selected}) ? selected:native.first?.id
  }
  mutating func clear() {entries=[];currentID=nil}
  var current:Entry? {entries.first{$0.id==currentID} ?? entries.first}
  func displayed(_ native:[Entry])->[Entry] {native.isEmpty ? entries:native}
}

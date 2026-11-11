import Foundation
import Combine
@preconcurrency import MusicKit

@MainActor final class MusicWatchBridge {
  private let music:MusicLibraryModel
  private let narration:NarrationModel
  private let link=WatchSessionLink()
  private var timer:AnyCancellable?
  private var ids:[String:UUID]=[:]
  init(music:MusicLibraryModel,narration:NarrationModel) {
    self.music=music;self.narration=narration
    link.onCommand={ [weak self] command in
      guard let self else { throw WatchCommandError.noTrack }
      try command.validate(against:self.snapshot())
      switch command.action {
      case .refresh:break
      case .play: Task { await self.music.resume() }
      case .pause:self.music.player.pause();self.narration.stop()
      case .next:Task { await self.music.next() }
      case .previous:Task { await self.music.previous() }
      case .stopExplanation:self.narration.stop()
      case .explain: self.narration.error="Apri Significato su iPhone per autorizzare il servizio testi e Gemini."
      case .radio: self.narration.error="La radio è disponibile dalle funzioni Apple Music su iPhone."
      case .playOccurrence:
        guard let id=command.occurrenceID,let entry=self.music.player.queue.entries.first(where:{ self.ids[String(describing:$0.id)]?.uuidString == id }) else { throw WatchCommandError.stale }
        self.music.player.queue.currentEntry=entry
        Task { do { try await self.music.player.play() } catch { self.music.error=error.localizedDescription } }
      }
      return self.snapshot()
    }
    timer=Timer.publish(every:2,on:.main,in:.common).autoconnect().sink { [weak self] _ in MainActor.assumeIsolated { guard let self else {return};self.link.publish(self.snapshot()) } }
  }
  private func snapshot()->WatchSnapshot {
    var value=WatchSnapshot()
    let entries=Array(music.player.queue.entries)
    let keys=Set(entries.map { String(describing:$0.id) })
    ids=ids.filter { keys.contains($0.key) }
    for key in keys where ids[key]==nil { ids[key]=UUID() }
    if let song=music.nowPlaying {
      let entryKey=music.player.queue.currentEntry.map { String(describing:$0.id) } ?? song.id.rawValue
      value.track = .init(id:ids[entryKey]?.uuidString ?? song.id.rawValue,title:song.title,artist:song.artistName)
    }
    value.playing=music.playing;value.elapsed=music.position;value.duration=music.duration
    value.preparingMeaning=narration.busy;value.meaning=narration.text;value.progress=narration.error ?? music.error ?? ""
    value.queueTotal=entries.count
    let current=entries.firstIndex(where:{$0.id==music.player.queue.currentEntry?.id}) ?? 0
    value.queue=entries[WatchSnapshot.queueRange(count:entries.count,currentOffset:current)].compactMap { entry in
      guard case .song(let song)=entry.item,let uuid=ids[String(describing:entry.id)] else { return nil }
      return .init(id:uuid.uuidString,title:song.title,artist:song.artistName)
    }
    return value
  }
}

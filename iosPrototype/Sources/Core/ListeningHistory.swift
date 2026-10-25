import Combine
import Foundation

public struct ListeningEntry: Codable, Identifiable, Sendable {
  public let id: UUID
  public let track: PlaybackTrack
  public let started: Date
  public var seconds: Double
  public var counted: Bool
}
public struct ListeningRank: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let artwork: URL?
  public let seconds: Double
  public let plays: Int
}
public struct ListeningReport: Sendable {
  public let seconds: Double
  public let plays: Int
  public let days: Int
  public let tracks: [ListeningRank]
  public let artists: [ListeningRank]
  public let albums: [ListeningRank]
  public var durationLabel: String {
    seconds < 60 ? "\(Int(seconds)) secondi" : "\(Int(seconds / 60)) minuti"
  }
  public var countLabel: String {
    "\(plays) " + (plays == 1 ? "ascolto" : "ascolti") + " · \(days) "
      + (days == 1 ? "giorno" : "giorni")
  }
  public var shareText: String {
    "NoteNarrate · " + durationLabel + " · " + countLabel + "\n"
      + tracks.prefix(5).enumerated().map {
        "\($0.offset + 1). \($0.element.title) — \($0.element.subtitle)"
      }.joined(separator: "\n")
  }
}
@MainActor public final class ListeningHistory: ObservableObject {
  @Published public private(set) var entries: [ListeningEntry]
  @Published public private(set) var error: String?
  private let url: URL
  private var previous: (token: UUID, position: Double, time: Date)?
  private var active: (token: UUID, entry: UUID)?
  private var lastSave = Date.distantPast
  public init(url: URL = LocalFiles.directory("Listening").appendingPathComponent("history.json")) {
    self.url = url
    entries = (LocalFiles.read([ListeningEntry].self, from: url) ?? []).filter {
      $0.seconds.isFinite && $0.seconds >= 0
    }
  }
  public func sample(
    track: PlaybackTrack?, token: UUID, position: Double, duration: Double,
    playing: Bool, now: Date = Date()
  ) {
    guard let track, playing, position.isFinite else {
      previous = nil
      return
    }
    defer { previous = (token, position, now) }
    guard let old = previous, old.token == token else { return }
    let wall = now.timeIntervalSince(old.time)
    let delta = position - old.position
    // Reject seeks, buffering jumps, suspended-process catchup and time spent in narration.
    guard wall > 0, wall <= 5, delta > 0, delta <= min(5, wall * 1.5 + 0.1) else { return }
    let index: Int
    if let active, active.token == token,
      let found = entries.firstIndex(where: { $0.id == active.entry })
    {
      index = found
    } else {
      let entry = ListeningEntry(
        id: UUID(), track: track, started: old.time, seconds: 0, counted: false)
      entries.append(entry)
      index = entries.count - 1
      active = (token, entry.id)
    }
    entries[index].seconds += min(delta, wall)
    let threshold = duration.isFinite && duration > 0 ? min(30, duration / 2) : 30
    entries[index].counted = entries[index].seconds >= threshold
    if now.timeIntervalSince(lastSave) >= 15 {
      save()
      lastSave = now
    }
  }
  public func endSession() {
    previous = nil
    active = nil
    save()
  }
  public func save() {
    do {
      try LocalFiles.write(entries, to: url)
      error = nil
    } catch { self.error = "Impossibile salvare le statistiche di ascolto." }
  }
  public func clear() {
    entries = []
    previous = nil
    active = nil
    save()
  }
  public func report(in interval: DateInterval? = nil, calendar: Calendar = .current)
    -> ListeningReport
  {
    let selected = entries.filter { row in
      interval.map { row.started >= $0.start && row.started < $0.end } ?? true
    }
    func rank(
      _ key: (PlaybackTrack) -> String?, title: (PlaybackTrack) -> String,
      subtitle: (PlaybackTrack) -> String
    ) -> [ListeningRank] {
      let groups = Dictionary(
        grouping: selected.filter { key($0.track) != nil }, by: { key($0.track)! })
      return groups.map { id, rows in
        ListeningRank(
          id: id, title: title(rows[0].track), subtitle: subtitle(rows[0].track),
          artwork: rows[0].track.artwork, seconds: rows.reduce(0) { $0 + $1.seconds },
          plays: rows.filter(\.counted).count)
      }.sorted { $0.seconds == $1.seconds ? $0.id < $1.id : $0.seconds > $1.seconds }
    }
    return ListeningReport(
      seconds: selected.reduce(0) { $0 + $1.seconds }, plays: selected.filter(\.counted).count,
      days: Set(selected.map { calendar.startOfDay(for: $0.started) }).count,
      tracks: rank({ $0.id }, title: { $0.title }, subtitle: { $0.artist }),
      artists: rank(
        { $0.artistBrowseID ?? $0.artist }, title: { $0.artist }, subtitle: { _ in "Artista" }),
      albums: rank(
        {
          $0.albumBrowseID ?? ($0.albumTitle == nil ? nil : $0.artist + "\u{1F}" + $0.albumTitle!)
        }, title: { $0.albumTitle ?? "Album" }, subtitle: { $0.artist }))
  }
  public func periods(_ component: Calendar.Component, calendar: Calendar = .current)
    -> [DateInterval]
  {
    let starts = Set(
      entries.compactMap { calendar.dateInterval(of: component, for: $0.started)?.start })
    return starts.sorted(by: >).compactMap { calendar.dateInterval(of: component, for: $0) }
  }
}

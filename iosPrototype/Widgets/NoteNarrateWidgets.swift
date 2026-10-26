import AppIntents
import SwiftUI
import WidgetKit

struct MusicWidgetEntry: TimelineEntry {
  var date: Date
  var snapshot: WidgetSnapshot
}
struct MusicWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> MusicWidgetEntry {
    MusicWidgetEntry(date: Date(), snapshot: WidgetSnapshot())
  }
  func getSnapshot(in context: Context, completion: @escaping (MusicWidgetEntry) -> Void) {
    completion(MusicWidgetEntry(date: Date(), snapshot: .read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<MusicWidgetEntry>) -> Void)
  {
    completion(
      Timeline(
        entries: [MusicWidgetEntry(date: Date(), snapshot: .read())],
        policy: .after(Date().addingTimeInterval(900))))
  }
}
private struct Cover: View {
  let file: String?
  var body: some View {
    Group {
      if let url = WidgetSnapshot.artworkURL(file), let image = UIImage(contentsOfFile: url.path) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Image(systemName: "music.note").font(.largeTitle).frame(
          maxWidth: .infinity, maxHeight: .infinity
        ).background(.indigo.gradient)
      }
    }.clipped().clipShape(RoundedRectangle(cornerRadius: 12))
  }
}
struct PlayerWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: MusicWidgetEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let track = entry.snapshot.track {
        HStack {
          Cover(file: track.artworkFile).frame(width: 56, height: 56)
          if family != .systemSmall {
            VStack(alignment: .leading) {
              Text(track.title).font(.headline).lineLimit(2)
              Text(track.artist).font(.caption).lineLimit(1)
            }
          }
          Spacer(minLength: 0)
          Button(intent: WidgetPlaybackIntent()) {
            Image(systemName: track.playing ? "pause.fill" : "play.fill")
          }.buttonStyle(.borderedProminent).tint(.cyan).accessibilityLabel(
            track.playing ? "Pausa" : "Riproduci")
          if family != .systemSmall {
            Button(intent: WidgetNextIntent()) { Image(systemName: "forward.end.fill") }
              .accessibilityLabel("Successivo")
          }
        }
        if family == .systemSmall {
          Text(track.title).font(.headline).lineLimit(2)
          Text(track.artist).font(.caption).lineLimit(1)
        }
        if track.duration > 0 {
          if track.playing {
            let start = entry.snapshot.date.addingTimeInterval(-track.elapsed)
            ProgressView(
              timerInterval:
                start...max(start.addingTimeInterval(track.duration), Date().addingTimeInterval(1)),
              countsDown: false
            ).labelsHidden()
          } else {
            ProgressView(value: track.elapsed, total: max(1, track.duration)).labelsHidden()
          }
        }
      } else {
        Label("NoteNarrate", systemImage: "music.note").font(.headline)
        Text("Scegli un brano nell’app").font(.caption)
      }
    }.widgetURL(AppRoute.player.url).containerBackground(.fill.tertiary, for: .widget)
  }
}
struct PlaylistWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: MusicWidgetEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Le tue playlist", systemImage: "music.note.list").font(.headline)
      if entry.snapshot.playlists.isEmpty {
        Text("Accedi a YouTube Music e apri Playlist nella Libreria.").font(.caption)
      } else {
        HStack(alignment: .top) {
          ForEach(entry.snapshot.playlists.prefix(family == .systemSmall ? 1 : 3)) { playlist in
            Link(destination: AppRoute.playlist(playlist.id).url) {
              VStack(alignment: .leading, spacing: 5) {
                Cover(file: playlist.artworkFile).frame(height: family == .systemSmall ? 65 : 70)
                Text(playlist.title).font(.caption.weight(.semibold)).lineLimit(2)
              }.frame(maxWidth: .infinity)
            }
          }
        }
      }
    }.widgetURL(AppRoute.library.url).containerBackground(.fill.tertiary, for: .widget)
  }
}
struct InsightsWidgetView: View {
  let entry: MusicWidgetEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("I tuoi ascolti", systemImage: "chart.bar.fill").font(.headline)
      if Calendar.current.isDateInToday(entry.snapshot.date) {
        Text("\(Int(entry.snapshot.todaySeconds / 60)) min oggi").font(.title2.bold())
      } else {
        Text("Apri per aggiornare gli ascolti").font(.headline)
      }
      Text(
        "Ultimi 7 giorni: \(Int(entry.snapshot.weekSeconds / 60)) min · \(entry.snapshot.weekPlays) ascolti"
      ).font(.caption)
      if let artist = entry.snapshot.topArtist {
        Text(artist).font(.caption.weight(.semibold)).lineLimit(1)
      } else {
        Text("Le statistiche iniziano dai tuoi ascolti nell’app.").font(.caption)
      }
      Text(entry.snapshot.date, style: .date).font(.caption2).foregroundStyle(.secondary)
    }.widgetURL(AppRoute.statistics.url).containerBackground(.fill.tertiary, for: .widget)
  }
}
struct PlayerWidget: Widget {
  let kind = "NoteNarratePlayer"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: MusicWidgetProvider()) { PlayerWidgetView(entry: $0) }
      .configurationDisplayName("Player").description("Copertina e controlli del brano corrente.")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}
struct PlaylistsWidget: Widget {
  let kind = "NoteNarratePlaylists"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: MusicWidgetProvider()) {
      PlaylistWidgetView(entry: $0)
    }
    .configurationDisplayName("Playlist").description("Apri le tue playlist di YouTube Music.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
struct ListeningWidget: Widget {
  let kind = "NoteNarrateListening"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: MusicWidgetProvider()) {
      InsightsWidgetView(entry: $0)
    }
    .configurationDisplayName("Ascolti").description("Tempo di ascolto e artista della settimana.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
@main struct NoteNarrateWidgets: WidgetBundle {
  var body: some Widget {
    PlayerWidget()
    PlaylistsWidget()
    ListeningWidget()
  }
}

import SwiftUI

struct DownloadAction: View {
  @EnvironmentObject private var model: MusicModel
  let song: Song
  var body: some View {
    if model.downloads.library.url(for: song.id) != nil {
      Label("Disponibile offline", systemImage: "checkmark.circle.fill")
    } else {
      Button {
        model.download(song)
      } label: {
        Label("Scarica per ascoltare offline", systemImage: "arrow.down.circle")
      }
    }
  }
}

struct OfflineScreen: View {
  @EnvironmentObject private var model: MusicModel
  @ObservedObject var downloads: MusicDownloads
  var body: some View {
    VStack(spacing: 0) {
      DisclosureGroup("Impostazioni download") {
        Toggle("Scarica solo con Wi-Fi", isOn: $downloads.wifiOnly)
        Picker("Spazio massimo", selection: $downloads.limitGB) {
          ForEach([1, 5, 10, 20], id: \.self) { Text("\($0) GB").tag($0) }
        }
      }.padding(.horizontal).padding(.vertical, 8)
      Text(
        ByteCountFormatter.string(fromByteCount: downloads.library.totalBytes, countStyle: .file)
          + " · \(downloads.library.ready.count) brani completi"
      )
      .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("offline-count")
      if let error = downloads.library.persistenceError { Text(error).foregroundStyle(.orange) }
      if downloads.library.records.isEmpty {
        Text(
          "Usa Scarica dal menu di un brano. Qui troverai i file completi disponibili senza connessione."
        )
        .foregroundStyle(.secondary)
      }
      LibraryCollection(
        items: downloads.library.records.sorted { $0.added > $1.added }, key: "offline",
        defaultLayout: .list, title: { $0.track.title }, artist: { $0.track.artist }
      ) { record, layout, ordered in
        VStack(alignment: .leading, spacing: 8) {
          Button {
            if record.state == .ready {
              model.play(record.track, queue: ordered.filter { $0.state == .ready }.map(\.track))
            }
          } label: {
            LibraryItemLabel(
              title: record.track.title, subtitle: record.track.artist,
              artwork: record.track.artwork, layout: layout, playable: record.state == .ready)
          }.disabled(record.state != .ready).accessibilityIdentifier("offline-" + record.id)
          switch record.state {
          case .preparing: ProgressView("In attesa / preparazione…")
          case .downloading:
            ProgressView(value: record.progress)
            Button("Metti in pausa") { downloads.pause(record.id) }
          case .verifying: ProgressView("Verifico il file completo…")
          case .paused, .failed:
            if let error = record.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button(record.state == .paused ? "Riprendi download" : "Riprova download") {
              model.download(record.track)
            }
          case .ready: EmptyView()
          }
        }.padding(.vertical, 4)
          .contextMenu {
            Button("Elimina download", role: .destructive) { model.removeDownload(record.id) }
          }
      }
    }.navigationTitle("Download e offline")
  }
}

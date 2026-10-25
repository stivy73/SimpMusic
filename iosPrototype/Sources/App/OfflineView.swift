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
    List {
      Section {
        Toggle("Scarica solo con Wi-Fi", isOn: $downloads.wifiOnly)
        Picker("Spazio massimo", selection: $downloads.limitGB) {
          ForEach([1, 5, 10, 20], id: \.self) { Text("\($0) GB").tag($0) }
        }
        Text(
          ByteCountFormatter.string(fromByteCount: downloads.library.totalBytes, countStyle: .file)
            + " · \(downloads.library.ready.count) brani completi"
        )
        .font(.caption).accessibilityIdentifier("offline-count")
        if let error = downloads.library.persistenceError { Text(error).foregroundStyle(.orange) }
      }
      if downloads.library.records.isEmpty {
        Text(
          "Usa Scarica dal menu di un brano. Qui troverai i file completi disponibili senza connessione."
        )
        .foregroundStyle(.secondary)
      }
      ForEach(downloads.library.records.sorted { $0.added > $1.added }) { record in
        VStack(alignment: .leading, spacing: 8) {
          Button {
            if record.state == .ready {
              model.play(record.track, queue: downloads.library.ready.map(\.track))
            }
          } label: {
            HStack {
              Image(
                systemName: record.state == .ready ? "arrow.down.circle.fill" : "arrow.down.circle")
              VStack(alignment: .leading) {
                Text(record.track.title).fontWeight(.semibold)
                Text(record.track.artist).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if record.state == .ready { Image(systemName: "play.fill") }
            }
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
          .swipeActions {
            Button("Elimina", role: .destructive) { model.removeDownload(record.id) }
          }
          .contextMenu {
            Button("Elimina download", role: .destructive) { model.removeDownload(record.id) }
          }
      }
    }.navigationTitle("Download e offline")
  }
}

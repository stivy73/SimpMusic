import SwiftUI

struct DownloadAction: View {
  @EnvironmentObject private var model: MusicModel
  let song: Song
  var inlineProgress = false

  var body: some View {
    let record = model.downloads.library.records.first { $0.id == song.id }
    if let record, record.isDownloading {
      if inlineProgress {
        DownloadProgressIndicator(record: record)
      } else {
        switch record.state {
        case .preparing, .downloading:
          Button { model.downloads.pause(song.id) } label: {
            Label(record.percentage.map { "Metti in pausa il download (\($0))" } ?? "Metti in pausa il download",
              systemImage: "pause.circle")
          }
        default:
          Label("Verifica download in corso", systemImage: "checkmark.circle")
        }
      }
    } else if model.downloads.library.url(for: song.id) != nil {
      Label("Disponibile offline", systemImage: "checkmark.circle.fill")
    } else {
      let title = switch record?.state {
      case .paused: "Riavvia download"
      case .failed: "Riprova download"
      default: "Scarica per ascoltare offline"
      }
      Button {
        model.download(song)
      } label: {
        Label(title, systemImage: "arrow.down.circle")
      }.accessibilityIdentifier("download-song-" + song.id)
    }
  }
}

private extension OfflineRecord {
  var isDownloading: Bool {
    state == .preparing || state == .downloading || state == .verifying
  }

  var percentage: String? {
    guard state == .downloading, (expectedBytes ?? 0) > 0 || progress > 0 else { return nil }
    return progress.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
  }
}

struct DownloadProgressIndicator: View {
  let record: OfflineRecord

  var body: some View {
    switch record.state {
    case .preparing, .downloading, .verifying:
      let title = record.state == .preparing ? "Download in attesa"
        : record.state == .verifying ? "Verifica del file…" : "Download"
      let percentage = record.percentage
      let amount = percentage ?? (record.state == .downloading && record.bytes > 0
        ? ByteCountFormatter.string(fromByteCount: record.bytes, countStyle: .file) : nil)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          if percentage == nil {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "arrow.down.circle")
          }
          Text(title)
          Spacer(minLength: 4)
          if let amount {
            Text(amount).monospacedDigit()
          }
        }.font(.subheadline)
        if percentage != nil {
          ProgressView(value: record.progress).progressViewStyle(.linear)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(title)
      .accessibilityValue(amount ?? "")
      .accessibilityIdentifier("download-progress-" + record.id)
    case .paused, .ready, .failed:
      EmptyView()
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
          DownloadProgressIndicator(record: record)
          switch record.state {
          case .preparing, .downloading:
            Button("Metti in pausa") { downloads.pause(record.id) }
          case .paused, .failed:
            if let error = record.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button(record.state == .paused ? "Riavvia download" : "Riprova download") {
              model.download(record.track)
            }
          case .ready, .verifying: EmptyView()
          }
        }.padding(.vertical, 4)
          .contextMenu {
            Button("Elimina download", role: .destructive) { model.removeDownload(record.id) }
          }
      }
    }.navigationTitle("Download e offline")
  }
}

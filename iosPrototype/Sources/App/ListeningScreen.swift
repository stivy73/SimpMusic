import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct ListeningScreen: View {
  @EnvironmentObject private var model: MusicModel
  var body: some View { ListeningReportScreen(history: model.listening) }
}
struct ListeningReportScreen: View {
  @ObservedObject var history: ListeningHistory
  @State private var interval: DateInterval?
  @State private var title = "Tutti gli ascolti"
  @State private var imageURL: URL?
  @State private var confirmClear = false
  private var report: ListeningReport { history.report(in: interval) }
  var body: some View {
    List {
      Section {
        Menu("Periodo: " + title) {
          Button("Tutti gli ascolti") { select(nil, "Tutti gli ascolti") }
          ForEach([7, 30, 90], id: \.self) { days in
            Button("Ultimi \(days) giorni") {
              select(
                DateInterval(start: Date().addingTimeInterval(-Double(days) * 86400), end: Date()),
                "Ultimi \(days) giorni")
            }
          }
          Section("Riepiloghi mensili") {
            ForEach(history.periods(.month), id: \.start) { period in
              Button(period.start.formatted(.dateTime.month(.wide).year())) {
                select(period, period.start.formatted(.dateTime.month(.wide).year()))
              }
            }
          }
          Section("Wrapped annuale") {
            ForEach(history.periods(.year), id: \.start) { period in
              Button(period.start.formatted(.dateTime.year())) {
                select(period, "Wrapped " + period.start.formatted(.dateTime.year()))
              }
            }
          }
        }.accessibilityIdentifier("listening-period")
        Text("\(Int(report.seconds / 60)) minuti · \(report.plays) ascolti · \(report.days) giorni")
          .accessibilityIdentifier("listening-summary")
        Text(
          "Conteggio locale dal momento dell’aggiornamento: esclude pause, buffering, salti e lettura TTS. Un ascolto conta dopo 30 secondi, o metà di un brano più breve."
        ).font(.caption).foregroundStyle(.secondary)
        if let error = history.error { Text(error).foregroundStyle(.orange) }
      }
      if report.tracks.isEmpty {
        Text("Ascolta qualche brano per iniziare le tue statistiche e i riepiloghi.")
      }
      ranking("Brani più ascoltati", report.tracks)
      ranking("Artisti", report.artists)
      ranking("Album", report.albums)
      if !report.tracks.isEmpty {
        Section("Condividi il riepilogo") {
          ShareLink(item: title + "\n" + report.shareText) {
            Label("Condividi statistiche", systemImage: "square.and.arrow.up")
          }
          Button("Crea immagine", systemImage: "photo") {
            imageURL = ShareArtwork.render(
              RecapCard(title: title, report: report), name: "NoteNarrate-riepilogo")
          }.accessibilityIdentifier("create-recap-image")
          if let imageURL { ShareLink("Condividi immagine", item: imageURL) }
        }
      }
      Section { Button("Cancella statistiche", role: .destructive) { confirmClear = true } }
    }.navigationTitle("Statistiche e Wrapped")
      .confirmationDialog("Cancellare tutti gli ascolti locali?", isPresented: $confirmClear) {
        Button("Cancella statistiche", role: .destructive) {
          history.clear()
          imageURL = nil
        }
      }
  }
  private func select(_ value: DateInterval?, _ label: String) {
    interval = value
    title = label
    imageURL = nil
  }
  private func ranking(_ title: String, _ rows: [ListeningRank]) -> some View {
    Section(title) {
      ForEach(Array(rows.prefix(20).enumerated()), id: \.element.id) { index, row in
        HStack {
          Text("\(index + 1)").foregroundStyle(.secondary)
          Artwork(url: row.artwork).frame(width: 44, height: 44).clipShape(
            RoundedRectangle(cornerRadius: 8))
          VStack(alignment: .leading) {
            Text(row.title)
            Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(Int(row.seconds / 60)) min\n\(row.plays) ascolti").font(.caption)
            .multilineTextAlignment(.trailing)
        }
      }
    }
  }
}
struct RecapCard: View {
  let title: String
  let report: ListeningReport
  var body: some View {
    VStack(alignment: .leading, spacing: 30) {
      Text("NoteNarrate").font(.system(size: 28, weight: .bold))
      Text(title.capitalized).font(.system(size: 46, weight: .heavy))
      Text(
        report.durationLabel + " di musica\n" + report.countLabel
      ).font(.system(size: 28, weight: .semibold))
      ForEach(Array(report.tracks.prefix(5).enumerated()), id: \.element.id) { index, row in
        Text("\(index + 1). \(row.title)\n\(row.subtitle)").font(.system(size: 23, weight: .medium))
          .lineLimit(3)
      }
      if let artist = report.artists.first {
        Text("Artista più ascoltato\n" + artist.title).font(.system(size: 25, weight: .bold))
      }
      Text("I tuoi ascolti, le tue storie.").font(.system(size: 20))
    }.padding(48).frame(width: 640, alignment: .leading).foregroundStyle(.white)
      .background(
        LinearGradient(
          colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
  }
}
@MainActor enum ShareArtwork {
  static func render<V: View>(_ view: V, name: String) -> URL? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    #if os(iOS)
      let data = renderer.uiImage?.pngData()
    #else
      let data = renderer.nsImage?.tiffRepresentation.flatMap {
        NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
      }
    #endif
    guard let data else { return nil }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NoteNarrate-shares")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name + ".png")
    do {
      try data.write(to: url, options: .atomic)
      return url
    } catch { return nil }
  }
}

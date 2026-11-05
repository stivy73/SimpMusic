import SwiftUI
import WatchKit

@main struct NoteNarrateWatchApp: App {
  @StateObject private var link = WatchSessionLink()
  var body: some Scene { WindowGroup { WatchPlayerView().environmentObject(link) } }
}

struct WatchPlayerView: View {
  @EnvironmentObject private var link: WatchSessionLink
  @Environment(\.scenePhase) private var phase
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          if let track = link.snapshot.track {
            if let data = link.snapshot.artwork, let image = UIImage(data: data) {
              Image(uiImage: image).resizable().scaledToFit().frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            } else {
              Image(systemName: link.snapshot.narrating ? "waveform" : "music.note")
                .font(.largeTitle).foregroundStyle(.cyan).accessibilityHidden(true)
            }
            Text(track.title).font(.headline).multilineTextAlignment(.center)
            Text(track.artist).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(
              .center)
            ProgressView(
              value: min(link.snapshot.elapsed, max(1, link.snapshot.duration)),
              total: max(1, link.snapshot.duration)
            )
            .tint(.cyan).accessibilityLabel("Avanzamento del brano")
            HStack {
              Text(clock(link.snapshot.elapsed))
              Spacer()
              Text(clock(link.snapshot.duration))
            }
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            if link.snapshot.loading { ProgressView("Preparazione su iPhone") }
            HStack {
              command("Precedente", symbol: "backward.end.fill", action: .previous)
              command(
                link.snapshot.playing || link.snapshot.narrating ? "Pausa" : "Riprendi",
                symbol: link.snapshot.playing || link.snapshot.narrating
                  ? "pause.fill" : "play.fill",
                action: link.snapshot.playing || link.snapshot.narrating ? .pause : .play)
              command("Successivo", symbol: "forward.end.fill", action: .next)
            }
            NavigationLink {
              WatchMeaningView()
            } label: {
              Label("Significato", systemImage: "lightbulb")
            }
            NavigationLink {
              WatchQueueView()
            } label: {
              Label("Coda", systemImage: "list.bullet")
            }
            Button {
              link.send(.radio)
            } label: {
              Label("Radio del brano", systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(!link.reachable || link.pending)
          } else {
            ContentUnavailableView(
              "NoteNarrate", systemImage: "music.note",
              description: Text(
                "Seleziona un brano su iPhone. Musica e voce vengono riprodotte dal telefono."))
          }
          WatchConnectionView()
        }.padding(.horizontal, 4)
      }
      .navigationTitle("NoteNarrate")
      .onChange(of: phase) { _, value in if value == .active { link.send(.refresh) } }
    }
  }
  private func command(_ label: String, symbol: String, action: WatchCommand.Action) -> some View {
    Button {
      link.send(action)
    } label: {
      Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 36)
    }
    .accessibilityLabel(label).disabled(!link.reachable || link.pending)
  }
  private func clock(_ seconds: Double) -> String {
    let value = Int(seconds.isFinite ? max(0, seconds) : 0)
    return "\(value / 60):\(String(format: "%02d", value % 60))"
  }
}
struct WatchMeaningView: View {
  @EnvironmentObject private var link: WatchSessionLink
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("La voce viene riprodotta su iPhone o sul suo dispositivo audio.").font(.caption)
          .foregroundStyle(.secondary)
        if link.snapshot.preparingMeaning { ProgressView("Preparazione interpretazione") }
        if !link.snapshot.progress.isEmpty { Text(link.snapshot.progress).font(.caption) }
        if !link.snapshot.meaning.isEmpty { Text(link.snapshot.meaning).font(.body) }
        if link.snapshot.preparingMeaning || link.snapshot.narrating {
          Button("Interrompi e riprendi musica") { link.send(.stopExplanation) }
            .disabled(!link.reachable || link.pending)
        } else {
          Button("Spiega e leggi") { link.send(.explain) }
            .disabled(
              !link.reachable || link.pending || link.snapshot.loading || link.snapshot.track == nil
            )
        }
        WatchConnectionView()
      }
    }.navigationTitle("Significato")
  }
}
struct WatchQueueView: View {
  @EnvironmentObject private var link: WatchSessionLink
  var body: some View {
    List {
      if link.snapshot.queue.isEmpty { Text("Coda vuota") }
      ForEach(link.snapshot.queue) { track in
        Button {
          link.send(.playOccurrence, occurrenceID: track.id)
        } label: {
          VStack(alignment: .leading) {
            Text(track.title).font(.headline)
            Text(track.artist).font(.caption).foregroundStyle(.secondary)
            if track.id == link.snapshot.track?.id {
              Text("Brano corrente").font(.caption2).foregroundStyle(.cyan)
            }
          }
        }.disabled(!link.reachable || link.pending)
      }
      if link.snapshot.queue.count < link.snapshot.queueTotal {
        Text("Mostrate \(link.snapshot.queue.count) di \(link.snapshot.queueTotal) tracce").font(
          .caption2)
      }
      WatchConnectionView()
    }.navigationTitle("Coda")
  }
}
struct WatchConnectionView: View {
  @EnvironmentObject private var link: WatchSessionLink
  var body: some View {
    VStack(spacing: 6) {
      if !link.reachable {
        Label("iPhone non raggiungibile", systemImage: "iphone.slash").font(.caption)
      }
      if let message = link.message { Text(message).font(.caption).foregroundStyle(.orange) }
      if link.pending { ProgressView("Invio comando") }
      Button("Aggiorna") { link.send(.refresh) }.disabled(link.pending)
      Text("Controllo di iPhone").font(.caption2).foregroundStyle(.secondary)
    }
  }
}

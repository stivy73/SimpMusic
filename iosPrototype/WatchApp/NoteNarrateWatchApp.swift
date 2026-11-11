import OSLog
import SwiftUI
@preconcurrency import WatchConnectivity
import WatchKit

@main struct NoteNarrateWatchApp: App {
  @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
  var body: some Scene { WindowGroup { WatchPlayerView().environmentObject(delegate.link) } }
}

/// WatchConnectivity can launch the app without a visible scene. Always finish its runtime tasks.
@MainActor final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  let link = WatchSessionLink()
  private var connectivityTasks: [ObjectIdentifier: WKWatchConnectivityRefreshBackgroundTask] = [:]
  private var observations: [NSKeyValueObservation] = []
  private let logger = Logger(
    subsystem: "com.stivy.simpmusic.prototype.watchapp", category: "Lifecycle")
  override init() {
    super.init()
    let session = WCSession.default
    observations = [
      session.observe(\.activationState, options: [.new]) { @Sendable [weak self] _, _ in
        Task { @MainActor in self?.finishConnectivityTasksIfReady() }
      },
      session.observe(\.hasContentPending, options: [.new]) { @Sendable [weak self] _, _ in
        Task { @MainActor in self?.finishConnectivityTasksIfReady() }
      },
    ]
    logger.info("Watch application initialized")
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--watch-launch-fixture") {
        var value = WatchSnapshot()
        value.track = .init(id: "fixture-1", title: "Brano di prova", artist: "NoteNarrate")
        value.duration = 261
        value.elapsed = 45
        value.queue = [value.track!]
        value.queueTotal = 1
        link.accept(value)
      }
    #endif
  }
  func applicationDidFinishLaunching() {
    logger.info("Watch launch finished")
    link.activate()
  }
  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    logger.info("Watch background tasks received: \(backgroundTasks.count)")
    for task in backgroundTasks {
      if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
        let id = ObjectIdentifier(connectivity)
        connectivityTasks[id] = connectivity
        connectivity.expirationHandler = { @Sendable [weak self] in
          Task { @MainActor in self?.complete(id) }
        }
      } else if let snapshot = task as? WKSnapshotRefreshBackgroundTask {
        snapshot.setTaskCompleted(
          restoredDefaultState: false, estimatedSnapshotExpiration: .distantFuture, userInfo: nil)
      } else {
        task.setTaskCompletedWithSnapshot(false)
      }
    }
    finishConnectivityTasksIfReady()
  }
  private func finishConnectivityTasksIfReady() {
    guard WCSession.default.activationState == .activated, !WCSession.default.hasContentPending
    else { return }
    for id in Array(connectivityTasks.keys) { complete(id) }
  }
  private func complete(_ id: ObjectIdentifier) {
    guard let task = connectivityTasks.removeValue(forKey: id) else { return }
    task.expirationHandler = nil
    task.setTaskCompletedWithSnapshot(false)
    logger.info("Watch connectivity background task completed")
  }
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
            #if !APPLE_MUSIC
            Button {
              link.send(.radio)
            } label: {
              Label("Radio del brano", systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(!link.reachable || link.pending)
            #endif
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
      .onAppear {
        Logger(subsystem: "com.stivy.simpmusic.prototype.watchapp", category: "Lifecycle").info(
          "Watch player appeared")
      }
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

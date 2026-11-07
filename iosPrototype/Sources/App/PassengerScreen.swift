import SwiftUI

#if os(iOS)
  import VisionKit

  struct PassengerScreen: View {
    @ObservedObject private var bridge = AppleAppSession.shared.passengers!
    @ObservedObject private var link = AppleAppSession.shared.passengers.link
    private var name: String { bridge.passengerName }
    @State private var code = ""
    @State private var scanning = false
    @State private var ending = false
    var body: some View {
      Form {
        Section {
          Label(
            link.status, systemImage: link.mode == .hosting ? "car.fill" : "person.2.fill"
          )
          .accessibilityIdentifier("passenger-status")
          Text(
            "Il telefono principale riproduce su CarPlay con il proprio account. I passeggeri inviano solo le selezioni musicali; account e chiavi restano separati."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
        switch link.mode {
        case .idle:
          Section("Telefono collegato a CarPlay") {
            Button("Apri una sessione nell’auto", systemImage: "car.side") { link.startHosting() }
              .accessibilityIdentifier("passenger-host")
          }
          Section("Telefono del passeggero") {
            nameField
            Button("Cerca un’auto vicina", systemImage: "antenna.radiowaves.left.and.right") {
              link.browse(name: name)
            }
            .accessibilityIdentifier("passenger-browse")
            scanButton
            invitationField
          }
        case .hosting:
          Section {
            Button("Ripristina collegamento", systemImage: "arrow.clockwise") {
              link.resumeHosting(force: true)
            }
            Text(
              "Riapre il collegamento Wi-Fi mantenendo lo stesso QR, i passeggeri Bluetooth e la coda musicale."
            ).font(.caption)
          }
          if let invitation = link.invitation {
            Section("Invita un passeggero · " + String(invitation.sessionID.uuidString.prefix(6))) {
              if let image = PassengerQRCode.image(for: invitation).map({ UIImage(cgImage: $0) }) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                  .frame(maxWidth: 240, maxHeight: 240).padding(12).background(.white)
                  .frame(maxWidth: .infinity).accessibilityLabel("QR della sessione Passeggero")
              }
              Text("Sull’altro telefono: NoteNarrate → Sessione in auto → Scansiona QR.")
              Text(
                "Per CarPlay wireless, attiva Bluetooth su entrambi gli iPhone e consenti l’accesso a NoteNarrate. Il QR permette anche il collegamento Bluetooth senza una rete Wi-Fi comune."
              )
              .font(.caption).foregroundStyle(.secondary)
              Text(invitation.displayCode).font(.system(.headline, design: .monospaced))
                .textSelection(.enabled).accessibilityIdentifier("passenger-code")
              Text(
                "In alternativa, scegli l’auto con lo stesso numero e inserisci questo codice. Il codice cambia quando riapri la sessione."
              )
              .font(.caption).foregroundStyle(.secondary)
              ShareLink(item: invitation.text) {
                Label("Condividi invito", systemImage: "square.and.arrow.up")
              }
            }
          }
          Section("Passeggeri") {
            if link.peers.isEmpty {
              Text("In attesa di un passeggero…").foregroundStyle(.secondary)
            }
            ForEach(link.peers) { peer in
              VStack(alignment: .leading, spacing: 10) {
                Label(peer.name, systemImage: "person.crop.circle.badge.checkmark")
                Text("Collegato · può scegliere la musica dell’auto").font(.caption)
                Button("Scollega", role: .destructive) { link.remove(peer.id) }
              }.padding(.vertical, 6)
            }
          }
        case .browsing:
          Section("Collegati all’auto") {
            nameField
            scanButton
            TextField("Codice della sessione", text: $code).verbatimTextInput()
              .accessibilityIdentifier("passenger-code-input")
            Text(
              "Con il QR l’app prova Wi-Fi e Bluetooth. Attiva Bluetooth e consenti il permesso Bluetooth di iOS su entrambi gli iPhone. La ricerca per numero richiede una rete locale raggiungibile; con CarPlay wireless usa Scansiona QR."
            )
            .font(.caption).foregroundStyle(.secondary)
            if code.hasPrefix("notenarrate:") {
              Button("Usa invito") {
                link.join(text: code, name: name)
                code = ""
              }
            }
            if link.hosts.isEmpty { ProgressView("Cerco una sessione NoteNarrate…") }
            ForEach(link.hosts) { host in
              Button(host.label) {
                link.join(host: host, code: code, name: name)
                code = ""
              }
            }
          }
        case .connecting, .joining:
          Section { ProgressView(link.status) }
        case .connected:
          Section("Nell’auto") {
            if !link.playback.title.isEmpty {
              Label(
                link.playback.title, systemImage: link.playback.playing ? "waveform" : "pause.fill")
              Text(link.playback.artist).foregroundStyle(.secondary)
            }
            Text("\(link.playback.queueCount) brani in coda")
          }
          Section("Scegli la musica") {
            Text(
              "Chiudi questo pannello per usare Cerca e Libreria. Play invia la selezione all’auto; i menu «Invia all’auto» permettono di aggiungerla alla coda. Il tuo telefono resta silenzioso."
            )
            Button("Scegli in NoteNarrate") { bridge.showing = false }
              .accessibilityIdentifier("passenger-choose-music")
          }
        }
        if let error = link.error { Section { Text(error).foregroundStyle(.orange) } }
        if let receipt = link.receipt {
          Section {
            Label(
              receipt.message,
              systemImage: receipt.success ? "checkmark.circle" : "exclamationmark.triangle")
          }
        }
        if link.mode != .idle {
          Section {
            Button(
              link.mode == .hosting ? "Chiudi la sessione per tutti" : "Esci dalla sessione",
              role: .destructive
            ) {
              ending = true
            }.accessibilityIdentifier("passenger-end")
          }
        }
        Section {
          DisclosureGroup("Diagnostica connessione in auto") {
            Text(link.diagnosticReport).font(.caption2).textSelection(.enabled)
            ShareLink(item: link.diagnosticReport) {
              Label("Condividi diagnostica", systemImage: "square.and.arrow.up")
            }
            Text("Non include codice QR, chiavi, account o titoli musicali.").font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Section {
          Text(
            "Scansiona il QR da fermo: con un invito valido il collegamento è automatico. Tieni entrambe le app aperte durante l’abbinamento. L’invito QR protegge il collegamento anche via Bluetooth; la musica resta sul principale. Se iOS sospende l’app, riapri NoteNarrate e riconnettiti."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
      }.navigationTitle("Sessione in auto").inlineNavigationTitle()
        .confirmationDialog(
          "Terminare il collegamento?", isPresented: $ending, titleVisibility: .visible
        ) {
          Button("Termina", role: .destructive) {
            link.stop()
            code = ""
          }
        }
        .sheet(isPresented: $scanning) {
          NavigationStack {
            PassengerScanner { text in
              scanning = false
              link.join(text: text, name: name)
            } failed: { message in
              scanning = false
              link.error = message
            }
            .navigationTitle("Scansiona il QR dell’auto").inlineNavigationTitle()
            .toolbar { Button("Chiudi") { scanning = false } }
          }
        }
    }
    private var nameField: some View {
      TextField("Il tuo nome", text: $bridge.passengerName).textContentType(.nickname)
        .onChange(of: name) { _, value in bridge.passengerName = String(value.prefix(40)) }
    }
    private var scanButton: some View {
      Button("Scansiona QR", systemImage: "qrcode.viewfinder") { scanning = true }
        .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
    }
    private var invitationField: some View {
      Group {
        TextField("Incolla invito completo", text: $code).verbatimTextInput()
        Button("Collegati con invito") {
          link.join(text: code, name: name)
          code = ""
        }
        .disabled(code.isEmpty)
      }
    }
  }

  private struct PassengerScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    var failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found: found, failed: failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
      let controller = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .balanced, recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: false,
        isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
      controller.delegate = context.coordinator
      do { try controller.startScanning() } catch {
        Task { @MainActor in
          failed(
            "Fotocamera non disponibile. Consenti l’accesso nelle impostazioni di iOS oppure usa il codice."
          )
        }
      }
      return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(
      _ controller: DataScannerViewController, coordinator: Coordinator
    ) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
      var completed = false
      let found: (String) -> Void
      let failed: (String) -> Void
      init(found: @escaping (String) -> Void, failed: @escaping (String) -> Void) {
        self.found = found
        self.failed = failed
      }
      func dataScanner(
        _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
      ) {
        guard !completed else { return }
        for case .barcode(let barcode) in addedItems {
          guard let text = barcode.payloadStringValue, (try? PassengerInvitation(text: text)) != nil
          else { continue }
          completed = true
          dataScanner.stopScanning()
          found(text)
          return
        }
      }
      func dataScanner(
        _ dataScanner: DataScannerViewController,
        becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
      ) {
        guard !completed else { return }
        completed = true
        failed("Fotocamera non disponibile. Usa il codice della sessione.")
      }
    }
  }

  struct PassengerPresentation: ViewModifier {
    @ObservedObject private var bridge = AppleAppSession.shared.passengers!
    @ObservedObject private var link = AppleAppSession.shared.passengers.link
    func body(content: Content) -> some View {
      content.safeAreaInset(edge: .top, spacing: 0) {
        if link.isPassenger || (link.mode == .idle && link.error != nil) {
          Button {
            bridge.showing = true
          } label: {
            HStack {
              Image(systemName: "car.fill")
              VStack(alignment: .leading, spacing: 3) {
                Text(
                  link.error ?? link.receipt?.message
                    ?? (link.pendingRequest != nil ? "Invio all’auto…" : link.status)
                )
                .font(.caption.bold()).lineLimit(3)
                if !link.playback.title.isEmpty {
                  Text(link.playback.title).font(.caption).lineLimit(1)
                }
              }
              Spacer()
              Image(systemName: "chevron.right")
            }.padding(12).foregroundStyle(link.error != nil ? Color.orange : .primary)
          }.buttonStyle(.plain).background(.regularMaterial).accessibilityIdentifier(
            "passenger-banner")
        }
      }.sheet(isPresented: $bridge.showing) {
        NavigationStack {
          PassengerScreen().toolbar { Button("Chiudi") { bridge.showing = false } }
        }
      }
    }
  }
#endif

/// Extra explicit menu alongside the normal Play/Add actions, useful when browsing as a passenger.
struct PassengerActions: View {
  let songs: [Song]
  #if os(iOS)
    @ObservedObject private var link = AppleAppSession.shared.passengers.link
  #endif
  var body: some View {
    #if os(iOS)
      if link.isPassenger {
        Menu {
          Button("Aggiungi alla coda dell’auto", systemImage: "text.append") {
            AppleAppSession.shared.passengers.send(songs, action: .enqueue)
          }.accessibilityIdentifier("passenger-send-queue")
          Button("Riproduci subito nell’auto", systemImage: "play.fill") {
            AppleAppSession.shared.passengers.send(songs, action: .playNow)
          }.accessibilityIdentifier("passenger-send-now")
        } label: {
          Label("Invia all’auto", systemImage: "car.fill")
        }
        .disabled(!link.canSend || songs.isEmpty).accessibilityIdentifier("passenger-send-menu")
      }
    #endif
  }
}

/// Loads every playlist page on the passenger phone, including private playlists, before sending IDs.
struct PassengerPlaylistActions: View {
  let id: String
  @EnvironmentObject private var library: LibraryModel
  @State private var loading = false
  #if os(iOS)
    @ObservedObject private var link = AppleAppSession.shared.passengers.link
  #endif
  var body: some View {
    #if os(iOS)
      if link.isPassenger {
        Menu {
          Button("Aggiungi playlist alla coda dell’auto") { send(.enqueue) }
          Button("Riproduci playlist nell’auto") { send(.playNow) }
        } label: {
          Label(
            loading ? "Carico la playlist…" : "Invia playlist all’auto", systemImage: "car.fill")
        }.disabled(loading || !link.canSend)
      }
    #endif
  }
  #if os(iOS)
    private func send(_ action: PassengerSelection.Action) {
      loading = true
      let account = library.session
      let sessionID = link.invitation?.sessionID
      Task { @MainActor in
        defer { loading = false }
        do {
          guard let account else { throw LibraryError.malformed }
          let playlist = try await YouTubeBrowse(session: account).playlist(id: id)
          guard library.session == account, link.mode == .connected,
            link.invitation?.sessionID == sessionID
          else { return }
          AppleAppSession.shared.passengers.send(
            playlist.entries.map { Song($0.item) }, action: action)
        } catch {
          link.error =
            "Impossibile recuperare tutta la playlist. Verifica l’account YouTube Music e riprova."
        }
      }
    }
  #endif
}

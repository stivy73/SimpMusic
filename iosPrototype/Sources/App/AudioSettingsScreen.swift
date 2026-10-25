import SwiftUI
import UniformTypeIdentifiers

struct AudioSettingsScreen: View {
  @ObservedObject private var preferences = AudioPreferences.shared
  @State private var importing = false
  @State private var error: String?
  var body: some View {
    Form {
      Section("Qualità AAC") {
        qualityPicker("Streaming Wi-Fi", selection: $preferences.wifiQuality)
        qualityPicker("Streaming rete mobile", selection: $preferences.cellularQuality)
        qualityPicker("Download", selection: $preferences.downloadQuality)
        Text(
          "La preferenza viene applicata al prossimo caricamento. Il formato e il bitrate effettivi dipendono dai flussi disponibili su YouTube Music."
        ).font(.caption)
      }
      Section("Equalizzatore a dieci bande") {
        Toggle("Attiva effetti audio", isOn: $preferences.effects.enabled).accessibilityIdentifier(
          "effects-enabled")
        Menu("Preset: " + preferences.effects.profile) {
          ForEach(AudioEffects.presets, id: \.0) { preset in
            Button(preset.0) {
              preferences.effects.gains = preset.1
              preferences.effects.profile = preset.0
            }
          }
        }
        ForEach(0..<10, id: \.self) { index in
          VStack {
            HStack {
              Text(frequency(AudioEffects.frequencies[index]))
              Spacer()
              Text(String(format: "%+.1f dB", preferences.effects.gains[index]))
            }
            Slider(
              value: Binding(
                get: { preferences.effects.gains[index] },
                set: {
                  preferences.effects.gains[index] = $0
                  preferences.effects.profile = "Personalizzato"
                }), in: -12...12, step: 0.5
            )
            .accessibilityLabel(frequency(AudioEffects.frequencies[index]))
          }
        }
        Text("Preamplificazione: \(preferences.effects.preamp, specifier: "%.1f") dB")
        Slider(value: $preferences.effects.preamp, in: -30...0, step: 0.5)
        Text("La riserva di volume automatica evita la saturazione quando aumenti una banda.").font(
          .caption)
        NavigationLink("Cerca profili cuffie AutoEq") { AutoEqScreen() }
        Button("Importa AutoEq FixedBandEQ.txt") { importing = true }
      }
      Section("Ambiente") {
        Text("Delay: \(Int(preferences.effects.delay * 100)) %")
        Slider(value: $preferences.effects.delay, in: 0...0.6)
        Text("Tempo delay: \(Int(preferences.effects.delaySeconds * 1000)) ms")
        Slider(value: $preferences.effects.delaySeconds, in: 0.05...0.8)
        Text("Riverbero: \(Int(preferences.effects.reverb * 100)) %")
        Slider(value: $preferences.effects.reverb, in: 0...0.6)
      }
      Section("Transizioni") {
        Text(
          preferences.crossfade == 0
            ? "Crossfade disattivato" : "Crossfade: \(Int(preferences.crossfade)) secondi")
        Slider(value: $preferences.crossfade, in: 0...12, step: 1).accessibilityIdentifier(
          "crossfade-seconds")
        Toggle("Modalità DJ", isOn: $preferences.djMode)
        Text(
          "Sovrappone due brani con una curva di volume più marcata al centro e filtri passa-basso / passa-alto. Non esegue beat matching. Se il prossimo flusso non è pronto, passa al brano normalmente."
        ).font(.caption)
      }
      if let error { Text(error).foregroundStyle(.orange) }
      Text(
        "Gli effetti elaborano il PCM del player iOS; non modificano video o voce narrante. Alcuni flussi HLS possono non offrire il processamento audio."
      ).font(.caption)
    }.navigationTitle("Audio")
      .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
        do {
          let url = try result.get()
          let access = url.startAccessingSecurityScopedResource()
          defer { if access { url.stopAccessingSecurityScopedResource() } }
          guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 100000 else {
            throw OfflineError.incomplete
          }
          preferences.effects = try AudioEffects.autoEq(String(contentsOf: url, encoding: .utf8))
          error = nil
        } catch {
          self.error =
            "Profilo non valido: usa il file AutoEq FixedBandEQ con dieci bande e Q 1,41."
        }
      }
  }
  private func qualityPicker(_ title: String, selection: Binding<AudioQuality>) -> some View {
    Picker(title, selection: selection) {
      ForEach(AudioQuality.allCases) { Text($0.rawValue).tag($0) }
    }
  }
  private func frequency(_ hz: Double) -> String {
    hz >= 1000 ? String(format: "%.0f kHz", hz / 1000) : String(format: "%.0f Hz", hz)
  }
}
struct AutoEqScreen: View {
  @ObservedObject private var preferences = AudioPreferences.shared
  @State private var entries =
    LocalFiles.read(
      [AutoEqEntry].self,
      from: LocalFiles.directory("Playback").appendingPathComponent("autoeq.json")) ?? []
  @State private var query = ""
  @State private var busy = false
  @State private var error: String?
  private var results: [AutoEqEntry] {
    query.count < 2
      ? [] : entries.filter { ($0.name + " " + $0.source).localizedCaseInsensitiveContains(query) }
  }
  var body: some View {
    List {
      if busy { ProgressView("Recupero profilo…") }
      if let error { Text(error).foregroundStyle(.orange) }
      if query.count < 2 { Text("Cerca il modello delle cuffie (almeno due caratteri).") }
      ForEach(Array(results.prefix(80))) { entry in
        Button {
          apply(entry)
        } label: {
          VStack(alignment: .leading) {
            Text(entry.name)
            Text(entry.source).font(.caption).foregroundStyle(.secondary)
          }
        }.disabled(busy)
      }
      if results.count > 80 {
        Text("Altri \(results.count - 80) risultati: specifica meglio il modello.")
      }
      if !busy && query.count >= 2 && results.isEmpty { Text("Nessun profilo trovato.") }
      Link("Progetto AutoEq", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
    }.searchable(text: $query).navigationTitle("AutoEq")
      .task { if entries.isEmpty { await load() } }
      .refreshable { await load() }
  }
  private func load() async {
    busy = true
    defer { busy = false }
    do {
      entries = try await AutoEqCatalog().entries()
      try LocalFiles.write(
        entries, to: LocalFiles.directory("Playback").appendingPathComponent("autoeq.json"))
      error = nil
    } catch { self.error = "Catalogo non disponibile. Puoi importare un profilo dal file." }
  }
  private func apply(_ entry: AutoEqEntry) {
    busy = true
    Task {
      defer { busy = false }
      do {
        preferences.effects = try await AutoEqCatalog().profile(entry)
        error = nil
      } catch {
        self.error = "Profilo non disponibile o formato incompatibile. Nessuna modifica applicata."
      }
    }
  }
}

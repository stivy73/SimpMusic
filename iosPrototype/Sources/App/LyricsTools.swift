import SwiftUI

struct LyricsTools: View {
  @EnvironmentObject private var model: MusicModel
  @State private var romanize = false
  @State private var translation: [String] = []
  @State private var selected = Set<Int>()
  @State private var language = "Italiano"
  @State private var busy = false
  @State private var error: String?
  @State private var imageURL: URL?
  @State private var task: Task<Void, Never>?
  private var original: [String] {
    if !model.timeline.lines.isEmpty { return model.timeline.lines.map(\.text) }
    return (model.manualLyrics.isEmpty ? model.lyrics : model.manualLyrics).components(
      separatedBy: .newlines)
  }
  var body: some View {
    Form {
      Section("Fonte del testo") {
        Picker("Provider", selection: $model.lyricsProvider) {
          ForEach(LyricsProviderChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        .onChange(of: model.lyricsProvider) { _, _ in
          model.timeline = LyricsTimeline(lrc: "")
          model.loadLyrics(force: true)
        }
        if model.lyricsProvider == .spotify {
          SecureField("Token web Spotify", text: $model.spotifyLyricsToken).verbatimTextInput()
          SecureField("Client token Spotify", text: $model.spotifyClientToken).verbatimTextInput()
          Text(
            "Facoltativi, salvati nel Portachiavi con Salva impostazioni. Spotify può richiedere una sessione valida; Premium YouTube non la sostituisce."
          ).font(.caption)
          Button("Salva e recupera testo") {
            model.saveSettings()
            model.loadLyrics(force: true)
          }
        }
        if model.manualLyrics.isEmpty, !model.savedManualLyrics.isEmpty {
          Button("Ripristina testo manuale salvato") { model.importLyrics(model.savedManualLyrics) }
        }
        if model.loadingLyrics { ProgressView(model.lyricsProgress) }
        if let error = model.lyricsError { Text(error).foregroundStyle(.orange) }
      }
      Section("Visualizzazione e traduzione") {
        Toggle("Romanizzazione", isOn: $romanize).accessibilityIdentifier("lyrics-romanize")
        Picker("Lingua traduzione", selection: $language) {
          ForEach(["Italiano", "English", "Français", "Deutsch", "Español"], id: \.self) {
            Text($0)
          }
        }
        Button("Traduci con Gemini") { translate() }.disabled(busy || original.joined().isEmpty)
        if busy { ProgressView("Traduco le righe…") }
        Text(
          "La traduzione invia il testo a Gemini con la chiave già configurata. Mantiene ordine e tempi delle righe originali. La romanizzazione avviene sul dispositivo."
        ).font(.caption)
        if let error { Text(error).foregroundStyle(.orange) }
      }
      Section("Versi: seleziona fino a sei righe per l’immagine") {
        ForEach(Array(original.enumerated()), id: \.offset) { index, line in
          if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
              if selected.contains(index) {
                selected.remove(index)
              } else if selected.count < 6 {
                selected.insert(index)
              }
              imageURL = nil
            } label: {
              HStack(alignment: .top) {
                Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                VStack(alignment: .leading, spacing: 6) {
                  Text(line).foregroundStyle(.primary)
                  if romanize, let latin = line.applyingTransform(.toLatin, reverse: false),
                    latin != line
                  {
                    Text(latin).foregroundStyle(.secondary)
                  }
                  if translation.indices.contains(index) {
                    Text(translation[index]).foregroundStyle(.cyan)
                  }
                }
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("verse-\(index)").accessibilityValue(
              selected.contains(index) ? "Selezionato" : "Non selezionato")
          }
        }
      }
    }.navigationTitle("Strumenti testo")
      .safeAreaInset(edge: .bottom) {
        if !selected.isEmpty, let song = model.current {
          VStack(spacing: 12) {
            Text("\(selected.count) versi selezionati").font(.caption)
            Button("Crea immagine dei versi") {
              imageURL = ShareArtwork.render(
                VerseCard(
                  song: song,
                  lines: selected.sorted().compactMap {
                    original.indices.contains($0) ? original[$0] : nil
                  }), name: "NoteNarrate-versi")
            }.accessibilityIdentifier("create-verse-image")
            if let imageURL {
              ShareLink("Condividi immagine", item: imageURL).accessibilityIdentifier(
                "share-verse-image")
            }
          }
        }
      }
      .onChange(of: original) { _, _ in
        task?.cancel()
        translation = []
        selected = []
        imageURL = nil
        busy = false
      }
      .onDisappear { task?.cancel() }
  }
  private func translate() {
    task?.cancel()
    busy = true
    error = nil
    let lines = original
    let id = model.current?.id
    let target = language
    let key = LocalFiles.key(lines.joined(separator: "\n") + target + model.textModel)
    let url = LocalFiles.directory("Translations").appendingPathComponent(key + ".json")
    task = Task {
      defer { if model.current?.id == id { busy = false } }
      do {
        let value: [String]
        if let cached = LocalFiles.read([String].self, from: url), cached.count == lines.count {
          value = cached
        } else {
          value = try await GeminiService().translateLyrics(
            key: model.apiKey, model: model.textModel, lines: lines, language: target)
          try LocalFiles.write(value, to: url)
        }
        guard !Task.isCancelled, model.current?.id == id, original == lines, language == target
        else { return }
        translation = value
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
}
struct VerseCard: View {
  let song: Song
  let lines: [String]
  var body: some View {
    VStack(alignment: .leading, spacing: 32) {
      Text("NoteNarrate").font(.system(size: 28, weight: .bold))
      Text(lines.joined(separator: "\n")).font(.system(size: 36, weight: .semibold)).lineSpacing(12)
      Text(song.title).font(.system(size: 28, weight: .bold))
      Text(song.artist).font(.system(size: 23))
    }.padding(48).frame(width: 640, alignment: .leading).foregroundStyle(.white)
      .background(
        LinearGradient(
          colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
  }
}

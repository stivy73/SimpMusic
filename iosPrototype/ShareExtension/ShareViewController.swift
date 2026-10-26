import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
  private let model = MusicShareComposer()
  override func viewDidLoad() {
    super.viewDidLoad()
    let host = UIHostingController(
      rootView: MusicShareComposerView(model: model) { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
      })
    addChild(host)
    view.addSubview(host.view)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    host.didMove(toParent: self)
    Task { await loadInput() }
  }
  private func loadInput() async {
    var values: [String] = []
    for item in (extensionContext?.inputItems as? [NSExtensionItem] ?? []).prefix(4) {
      if let text = item.attributedContentText?.string { values.append(text) }
      if let text = item.attributedTitle?.string { values.append(text) }
      for provider in (item.attachments ?? []).prefix(4) {
        for type in [UTType.url.identifier, UTType.plainText.identifier]
        where provider.hasItemConformingToTypeIdentifier(type) {
          if let value = await read(provider, type: type) { values.append(value) }
        }
      }
    }
    model.receive(values)
  }
  private func read(_ provider: NSItemProvider, type: String) async -> String? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { value, _ in
        let text: String?
        if let url = value as? URL {
          text = url.absoluteString
        } else if let string = value as? String {
          text = String(string.prefix(4096))
        } else if let data = value as? Data, data.count <= 16384 {
          text = String(data: data, encoding: .utf8)
        } else {
          text = nil
        }
        continuation.resume(returning: text)
      }
    }
  }
}

@MainActor final class MusicShareComposer: ObservableObject {
  @Published var query = ""
  @Published var target: SharedMusicTarget?
  @Published var error: String?
  @Published var loading = true
  @Published var saved = false
  private var receivedQuery = ""
  func receive(_ values: [String]) {
    target = SharedMusicTarget.parse(values)
    if case .search(let text) = target { query = text }
    receivedQuery = query
    loading = false
    if target == nil { error = "Inserisci titolo e artista del brano da cercare." }
  }
  func save() {
    let edited = SharedMusicTarget.queryText(query)
    let value =
      query == receivedQuery && target != nil ? target : edited.map(SharedMusicTarget.search)
    guard let value, value.valid else {
      error = "Inserisci titolo e artista (massimo 300 caratteri)."
      return
    }
    guard let inbox = SharedMusicInbox.shared() else {
      error = "Impossibile ricevere il brano. Apri NoteNarrate e riprova."
      return
    }
    do {
      try inbox.save(SharedMusicRequest(target: value))
      saved = true
      error = nil
    } catch { self.error = "Il brano non è stato salvato. Riprova." }
  }
}
struct MusicShareComposerView: View {
  @ObservedObject var model: MusicShareComposer
  let finish: () -> Void
  var body: some View {
    NavigationStack {
      Form {
        if model.loading {
          ProgressView("Leggo il brano condiviso…")
        } else if model.saved {
          Section {
            Label("Brano ricevuto", systemImage: "checkmark.circle.fill").font(.headline)
            Text(
              "Apri NoteNarrate: il contenuto condiviso è pronto per la ricerca o la riproduzione. Lo trovi anche in Libreria → Ricevuti."
            )
            Button("Fine", action: finish).accessibilityIdentifier("share-done")
          }
        } else {
          Section("Contenuto condiviso") {
            if let target = model.target, case .search = target {
            } else if let target = model.target {
              Text(target.label)
            }
            TextField("Titolo e artista", text: $model.query, axis: .vertical).lineLimit(1...3)
              .accessibilityIdentifier("share-query")
            Text("Puoi cercare un brano, oppure ricevere un link YouTube Music o YouTube.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let error = model.error { Text(error).foregroundStyle(.orange) }
          Button("Aggiungi a NoteNarrate") { model.save() }
            .accessibilityIdentifier("share-save").disabled(model.loading)
        }
      }.navigationTitle("NoteNarrate")
        .toolbar { if !model.saved { Button("Annulla", action: finish) } }
    }.tint(.cyan)
  }
}

import SwiftUI

struct SharedMusicScreen: View {
  let request: SharedMusicRequest
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @State private var song: Song?
  @State private var query = ""
  @State private var error: String?
  @State private var loading = false
  @State private var searching = false
  var body: some View {
    Group {
      if searching {
        MusicSearchScreen(search: model.searchResults)
      } else if case .playlist(let id) = request.target {
        HomeBrowseView(title: "Playlist condivisa", target: BrowseTarget(browseId: "VL" + id))
      } else {
        Form {
          Section("Ricevuto da un’altra app") {
            Text(request.target.label).font(.headline)
            if loading { ProgressView("Recupero titolo e copertina…") }
            if let song {
              LibraryItemLabel(
                title: song.title, subtitle: song.artist, artwork: song.artwork, layout: .list,
                playable: true)
              Button("Riproduci") {
                finish()
                model.play(song, queue: [song])
              }
              .accessibilityIdentifier("shared-play")
              Button("Aggiungi alla coda") {
                model.enqueue(song)
                finish()
              }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            TextField("Titolo e artista", text: $query).accessibilityIdentifier(
              "shared-search-query")
            Button("Cerca su YouTube Music") {
              guard let clean = SharedMusicTarget.queryText(query) else { return }
              model.searchResults.configure(session: library.session)
              model.searchResults.select(.category(.songs))
              model.searchResults.submit(clean)
              try? SharedMusicInbox.shared()?.remove(request.id)
              searching = true
            }.disabled(SharedMusicTarget.queryText(query) == nil)
              .accessibilityIdentifier("shared-search")
            if error != nil { Button("Riprova recupero informazioni") { Task { await prepare() } } }
          }
        }.navigationTitle("Brano condiviso")
      }
    }.task(id: request.id) { await prepare() }
  }
  private func finish() {
    try? SharedMusicInbox.shared()?.remove(request.id)
    model.sharedRequest = nil
  }
  private func prepare() async {
    error = nil
    switch request.target {
    case .search(let text): query = text
    case .playlist: break
    case .video(let id):
      loading = true
      defer { loading = false }
      do {
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--test-shared-music") {
            song = Song(id: id, title: "Heroes", artist: "David Bowie", artwork: nil)
            query = "Heroes David Bowie"
            return
          }
        #endif
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
          URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=" + id),
          URLQueryItem(name: "format", value: "json"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 131072 else {
          throw URLError(.badServerResponse)
        }
        struct Metadata: Decodable {
          let title: String
          let author_name: String
          let thumbnail_url: URL?
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        try Task.checkCancellation()
        song = Song(
          id: id, title: metadata.title, artist: metadata.author_name,
          artwork: metadata.thumbnail_url)
        query = metadata.title + " " + metadata.author_name
      } catch is CancellationError {} catch {
        self.error =
          "Impossibile recuperare il titolo del link. Riprova oppure inserisci titolo e artista per cercarlo."
      }
    }
  }
}

struct SharedMusicInboxScreen: View {
  @EnvironmentObject private var model: MusicModel
  @State private var pending: [SharedMusicRequest] = []
  var body: some View {
    Group {
      if pending.isEmpty {
        ContentUnavailableView(
          "Nessun brano ricevuto", systemImage: "square.and.arrow.down",
          description: Text(
            "Usa Condividi → NoteNarrate da YouTube Music, YouTube o da un’app che condivide titolo e artista."
          ))
      } else {
        List(pending) { request in
          NavigationLink {
            SharedMusicScreen(request: request)
          } label: {
            Label(request.target.label, systemImage: "music.note")
          }.swipeActions {
            Button("Elimina", role: .destructive) {
              try? SharedMusicInbox.shared()?.remove(request.id)
              reload()
            }
          }
        }
      }
    }.navigationTitle("Ricevuti").onAppear { reload() }
  }
  private func reload() { pending = SharedMusicInbox.shared()?.pending() ?? [] }
}

import SwiftUI

struct SharedCatalogScreen: View {
  let request: SharedMusicRequest
  let link: SharedCatalogLink
  @EnvironmentObject private var music: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @StateObject private var importer: SharedCatalogImport
  @State private var task: Task<Void, Never>?
  @State private var selecting: Int?
  @State private var saving = false
  @State private var saveError: String?
  @State private var createdPlaylist: DiscoveryItem?
  @State private var searchText = ""
  @State private var searching = false
  @State private var showLogin = false
  @State private var candidateQuery = ""

  init(request: SharedMusicRequest, link: SharedCatalogLink) {
    self.request = request
    self.link = link
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-shared-catalog") {
        _importer = StateObject(wrappedValue: SharedCatalogImport.fixtures())
        return
      }
    #endif
    _importer = StateObject(wrappedValue: SharedCatalogImport())
  }
  var body: some View {
    Group {
      if searching { MusicSearchScreen(search: music.searchResults) } else { content }
    }
    .navigationTitle(link.kind == .playlist ? "Playlist condivisa" : link.kind.title + " condiviso")
    .task(id: link) { await importer.load(link) }
    .onDisappear { task?.cancel() }
    .onChange(of: library.accountRevision) { _, _ in
      let previous = task
      previous?.cancel()
      task = Task {
        await previous?.value
        importer.clearMatches()
      }
      createdPlaylist = nil
      showLogin = false
    }
    .sheet(isPresented: $showLogin) { YouTubeLoginScreen(library: library) }
    .sheet(isPresented: Binding(get: { selecting != nil }, set: { if !$0 { selecting = nil } })) {
      NavigationStack {
        List {
          if let index = selecting, let collection = importer.collection {
            Section("Versione originale") {
              Text(collection.tracks[index].title).font(.headline)
              Text(collection.tracks[index].artist)
              TextField("Titolo e artista", text: $candidateQuery)
                .accessibilityIdentifier("shared-catalog-candidate-query")
              Button("Cerca versione") {
                task = Task {
                  await importer.searchCandidates(
                    at: index, query: candidateQuery, session: library.session)
                }
              }.disabled(importer.busy || SharedMusicTarget.queryText(candidateQuery) == nil)
              if importer.busy { ProgressView("Ricerca…") }
              if let failure = importer.failures[index] { Text(failure).foregroundStyle(.orange) }
            }
            Section("Scegli su YouTube Music") {
              ForEach(importer.candidates[index] ?? []) { item in
                Button {
                  importer.choose(item, at: index)
                  selecting = nil
                } label: {
                  LibraryItemLabel(
                    title: item.title, subtitle: item.subtitle, artwork: item.artwork, layout: .list
                  )
                }.disabled(importer.busy)
                  .accessibilityIdentifier("shared-catalog-candidate-" + item.mediaId)
              }
            }
          }
        }.navigationTitle("Conferma il brano")
          .toolbar {
            Button("Chiudi") {
              task?.cancel()
              selecting = nil
            }
          }
      }
    }
  }
  private var content: some View {
    List {
      if let collection = importer.collection {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Artwork(url: collection.artwork).frame(width: 156, height: 156)
              .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(collection.title).font(.title2.bold()).accessibilityIdentifier(
              "shared-catalog-title")
            Text(collection.subtitle).foregroundStyle(.secondary)
            Link("Apri su " + collection.link.provider.title, destination: collection.link.url)
            Text(
              (collection.tracks.count == 1
                ? "1 traccia ricevuta" : "\(collection.tracks.count) tracce ricevute")
                + " · "
                + (importer.matches.count == 1 ? "1 trovata" : "\(importer.matches.count) trovate")
                + " su YouTube Music"
            )
            .accessibilityIdentifier("shared-catalog-count")
            if let warning = collection.warning { Text(warning).foregroundStyle(.orange) }
            Text(
              "La riproduzione usa le versioni trovate su YouTube Music. I Mi piace e la raccolta originale non vengono modificati."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          if importer.busy {
            ProgressView("Verifico \(importer.completed) di \(collection.tracks.count)…")
            Button("Interrompi ricerca") { task?.cancel() }
          } else if importer.matches.count == collection.tracks.count {
            Label("Tutti i brani sono stati trovati", systemImage: "checkmark.circle.fill")
              .font(.footnote).foregroundStyle(.secondary)
          } else {
            Button(
              importer.matches.isEmpty
                ? "Trova i brani su YouTube Music" : "Riprova i brani mancanti"
            ) {
              task = Task { await importer.resolve(session: library.session) }
            }.disabled(importer.matches.count == collection.tracks.count || saving)
              .accessibilityIdentifier("shared-catalog-resolve")
          }
          if !importer.orderedMatches.isEmpty {
            Button(
              importer.matches.count == 1
                ? "Riproduci il brano" : "Riproduci \(importer.matches.count) brani trovati",
              systemImage: "play.fill"
            ) {
              let songs = importer.orderedMatches.map(Song.init)
              finish()
              music.play(songs[0], queue: songs)
            }.disabled(saving).accessibilityIdentifier("shared-catalog-play")
            Button(
              importer.matches.count == 1
                ? "Aggiungi il brano alla coda"
                : "Aggiungi \(importer.matches.count) brani alla coda",
              systemImage: "text.line.last.and.arrowtriangle.forward"
            ) {
              music.enqueue(contentsOf: importer.orderedMatches.map(Song.init))
              finish()
            }.disabled(saving).accessibilityIdentifier("shared-catalog-enqueue")
            if let createdPlaylist {
              Label("Playlist creata su YouTube Music", systemImage: "checkmark.circle.fill")
                .accessibilityIdentifier("shared-catalog-saved")
              NavigationLink("Apri la playlist") { RemotePlaylistView(playlist: createdPlaylist) }
            } else {
              Button(
                "Crea playlist privata con \(importer.matches.count) \(importer.matches.count == 1 ? "brano" : "brani")",
                systemImage: "music.note.list"
              ) {
                save(collection)
              }.disabled(importer.busy || saving).accessibilityIdentifier("shared-catalog-save")
            }
          }
          if saving { ProgressView("Salvo la playlist…") }
          if let saveError { Text(saveError).foregroundStyle(.orange) }
        }
        Section("Tracce nell’ordine originale") {
          ForEach(Array(collection.tracks.enumerated()), id: \.offset) { index, track in
            VStack(alignment: .leading, spacing: 6) {
              HStack(alignment: .top) {
                Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                  Text(track.title).font(.headline)
                  Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if importer.matches[index] != nil {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan)
                }
              }
              if let failure = importer.failures[index] {
                Text(failure).font(.caption).foregroundStyle(.orange)
              }
              if let selected = importer.matches[index] {
                Text("YouTube Music: \(selected.title) · \(selected.subtitle)")
                  .font(.caption).foregroundStyle(.secondary)
              }
              if importer.candidates[index] != nil || importer.failures[index] != nil {
                Button("Scegli versione") {
                  candidateQuery = track.query
                  selecting = index
                }
                .disabled(importer.busy || saving).accessibilityIdentifier(
                  "shared-catalog-choose-\(index)")
              }
            }
          }
        }
      } else if importer.busy {
        ProgressView("Recupero copertina e tracce…")
      }
      if let error = importer.error {
        Section {
          Text(error).foregroundStyle(.orange)
          Link("Apri su " + link.provider.title, destination: link.url)
          Button("Riprova") { task = Task { await importer.load(link) } }
          TextField("Titolo e artista", text: $searchText)
          Button("Cerca su YouTube Music") {
            guard let query = SharedMusicTarget.queryText(searchText) else { return }
            music.searchResults.configure(session: library.session)
            music.searchResults.select(.category(.songs))
            music.searchResults.submit(query)
            searching = true
          }.disabled(SharedMusicTarget.queryText(searchText) == nil)
        }
      }
    }.disabled(saving)
  }
  private func finish() {
    task?.cancel()
    try? SharedMusicInbox.shared()?.remove(request.id)
    music.sharedRequest = nil
  }
  private func save(_ collection: SharedCatalogCollection) {
    guard let session = library.session else {
      saveError = "Accedi a YouTube Music per salvare la playlist."
      showLogin = true
      return
    }
    let revision = library.accountRevision
    let ids = importer.orderedMatches.map(\.mediaId)
    guard !ids.isEmpty, !saving, !importer.busy else { return }
    saving = true
    saveError = nil
    task = Task {
      defer { saving = false }
      do {
        #if DEBUG
          let id: String
          if ProcessInfo.processInfo.arguments.contains("--test-shared-catalog") {
            id = "PL-shared-fixture"
          } else {
            id = try await YouTubeBrowse(session: session).createPlaylist(
              title: collection.title, videoIDs: ids)
          }
        #else
          let id = try await YouTubeBrowse(session: session).createPlaylist(
            title: collection.title, videoIDs: ids)
        #endif
        guard revision == library.accountRevision else { return }
        createdPlaylist = DiscoveryItem(
          kind: .playlist, mediaId: id, title: collection.title,
          subtitle: "Importata da " + collection.link.provider.title, artwork: collection.artwork)
        try? SharedMusicInbox.shared()?.remove(request.id)
        await library.load(.playlists, force: true)
      } catch {
        saveError =
          "Salvataggio non confermato. Controlla le playlist su YouTube Music prima di riprovare."
      }
    }
  }
}

#if DEBUG
  extension SharedCatalogImport {
    static func fixtures() -> SharedCatalogImport {
      let resolver = SharedCatalogResolver { url, _ in
        let link: SharedCatalogLink
        if url.host == "itunes.apple.com", url.path == "/lookup" {
          let id = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first {
            $0.name == "id"
          }!.value!
          let track = ProcessInfo.processInfo.arguments.contains("--test-share-kind-track")
          link = SharedCatalogLink(provider: .appleMusic, kind: track ? .track : .album, id: id)
        } else {
          link = SharedCatalogLink.parse(url)!
        }
        if link.provider == .appleMusic {
          let rows: [[String: Any]] =
            link.kind == .track
            ? [
              [
                "kind": "song", "trackId": Int(link.id)!, "trackName": "Heroes",
                "artistName": "David Bowie", "trackTimeMillis": 200000,
              ]
            ]
            : [
              [
                "wrapperType": "collection", "collectionId": Int(link.id) ?? 594_061_854,
                "collectionName": "Album di prova", "artistName": "David Bowie", "trackCount": 3,
              ]
            ]
              + (0..<3).map {
                [
                  "kind": "song", "collectionId": Int(link.id) ?? 594_061_854,
                  "trackId": 100000 + $0, "trackName": "Brano \($0 + 1)",
                  "artistName": "David Bowie", "trackTimeMillis": 200000,
                ]
              }
          if link.kind != .playlist {
            return .init(
              data: try JSONSerialization.data(withJSONObject: ["results": rows]), url: url)
          }
          let header: [String: Any] = [
            "itemKind": "containerDetailHeaderLockup",
            "items": [["title": "Playlist di prova", "subtitleLinks": [["title": "David Bowie"]]]],
          ]
          let tracks: [String: Any] = [
            "itemKind": "trackLockup",
            "containerContentDescriptor": ["identifiers": ["storeAdamID": link.id]],
            "items": (0..<3).map {
              [
                "title": "Brano \($0 + 1)", "artistName": "David Bowie", "duration": 200000,
                "contentDescriptor": [
                  "kind": "song", "identifiers": ["storeAdamID": "\(100000 + $0)"],
                ],
              ]
            },
          ]
          let json = try JSONSerialization.data(withJSONObject: [
            "data": [["data": ["sections": [header, tracks]]]]
          ])
          return .init(
            data: Data(
              ("<script id=serialized-server-data>" + String(decoding: json, as: UTF8.self)
                + "</script>").utf8), url: url)
        }
        var entity: [String: Any] = [
          "id": link.id, "type": link.kind.rawValue,
          "name": link.kind == .track ? "Heroes" : "Raccolta di prova",
          "artists": [["name": "David Bowie"]], "duration": 200000,
        ]
        if link.kind != .track {
          entity["trackList"] = (0..<3).map {
            [
              "uri": "spotify:track:" + String(repeating: "a", count: 21) + "\($0)",
              "entityType": "track", "title": "Brano \($0 + 1)", "subtitle": "David Bowie",
              "duration": 200000,
            ]
          }
        }
        let json = try JSONSerialization.data(withJSONObject: [
          "props": ["pageProps": ["state": ["data": ["entity": entity]]]]
        ])
        return .init(
          data: Data(
            ("<script id=__NEXT_DATA__>" + String(decoding: json, as: UTF8.self) + "</script>").utf8
          ), url: url)
      }
      return SharedCatalogImport(
        resolver: resolver,
        search: { _, query in
          let title = query.replacingOccurrences(of: " David Bowie", with: "")
          let mismatch = ProcessInfo.processInfo.arguments.contains(
            "--test-shared-catalog-mismatch")
          return [
            .init(
              kind: .song, mediaId: "dQw4w9WgXcQ", title: title + (mismatch ? " (Live)" : ""),
              subtitle: "David Bowie",
              artwork: nil, durationSeconds: 200)
          ]
        })
    }
  }
#endif

import SwiftUI

extension MusicModel {
  static func makeArtistReleases() -> ArtistReleases {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-discovery-extras") {
        let directory = LocalFiles.directory("QAArtistReleases")
        try? FileManager.default.removeItem(at: directory)
        actor Catalog {
          var checks = 0
          func releases() -> [DiscoveryItem] {
            checks += 1
            return (checks == 1 ? ["MPREold"] : ["MPREnew", "MPREold"]).map {
              DiscoveryItem(
                kind: .album, mediaId: $0,
                title: $0 == "MPREnew" ? "Nuova uscita di prova" : "Album precedente",
                subtitle: "Artista seguito di prova", artwork: nil)
            }
          }
        }
        let catalog = Catalog()
        return ArtistReleases(directory: directory, fetch: { _, _ in await catalog.releases() })
      }
    #endif
    return ArtistReleases()
  }
}

struct DiscoveryMenu: View {
  var body: some View {
    Menu {
      ForEach(DiscoveryDestination.allCases) { value in
        NavigationLink {
          DiscoveryCatalogScreen(destination: value)
        } label: {
          Label(value.title, systemImage: value.symbol)
        }.accessibilityIdentifier("open-" + value.rawValue)
      }
      NavigationLink {
        MusicSuggestionsScreen()
      } label: {
        Label("Consigli IA", systemImage: "sparkles")
      }
      .accessibilityIdentifier("open-ai-suggestions")
      NavigationLink {
        ArtistReleasesScreen()
      } label: {
        Label("Nuove uscite", systemImage: "bell")
      }
      .accessibilityIdentifier("open-artist-releases")
    } label: {
      Label("Esplora", systemImage: "square.grid.2x2")
    }
    .accessibilityIdentifier("discovery-menu")
  }
}

struct DiscoveryCatalogScreen: View {
  let destination: DiscoveryDestination
  @EnvironmentObject private var library: LibraryModel
  @StateObject private var catalog: DiscoveryCatalogModel
  @State private var country = "IT"
  init(destination: DiscoveryDestination) {
    self.destination = destination
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-discovery-extras") {
        _catalog = StateObject(
          wrappedValue: DiscoveryCatalogModel(
            destination: destination,
            fetch: { _, section, country, token in
              HomePage(shelves: [
                HomeShelf(
                  id: section.id, title: section.title + " " + country,
                  items: [
                    DiscoveryItem(
                      kind: section == .podcasts ? .playlist : .song,
                      mediaId: section == .podcasts ? "MPSPfixture" : "discovery-song",
                      title: section == .podcasts ? "Podcast di prova" : "Brano di classifica",
                      subtitle: "Artista di prova", artwork: nil)
                  ])
              ])
            }))
      } else {
        _catalog = StateObject(wrappedValue: DiscoveryCatalogModel(destination: destination))
      }
    #else
      _catalog = StateObject(wrappedValue: DiscoveryCatalogModel(destination: destination))
    #endif
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        if destination == .charts {
          Picker("Paese della classifica", selection: $country) {
            Text("Italia").tag("IT")
            Text("Mondo").tag("ZZ")
            Text("Stati Uniti").tag("US")
            Text("Regno Unito").tag("GB")
            Text("Francia").tag("FR")
            Text("Germania").tag("DE")
            Text("Spagna").tag("ES")
            Text("Brasile").tag("BR")
            Text("Giappone").tag("JP")
          }.pickerStyle(.menu).padding(.horizontal).accessibilityIdentifier("charts-country")
          Text("Classifiche ufficiali di YouTube Music per il paese selezionato.").font(.caption)
            .foregroundStyle(.secondary).padding(.horizontal)
        }
        if destination == .podcasts {
          NavigationLink {
            PodcastSearchScreen()
          } label: {
            Label("Cerca un podcast", systemImage: "magnifyingglass").frame(
              maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.bordered).padding(.horizontal).accessibilityIdentifier("podcasts-search")
        }
        if destination == .mixes && library.session == nil {
          ContentUnavailableView {
            Label("I tuoi Mix di YouTube Music", systemImage: destination.symbol)
          } description: {
            Text("Accedi per ascoltare i Mix creati per te da YouTube Music.")
          } actions: {
            Button("Accedi a YouTube Music") { library.showLogin = true }
          }
        } else {
          DiscoveryShelves(shelves: catalog.shelves, songsAsList: destination != .mixes)
          if let error = catalog.error {
            Text(error).foregroundStyle(.orange).padding(.horizontal)
            Button("Riprova") { Task { await catalog.reload() } }.padding(.horizontal)
          }
          if catalog.loading { ProgressView("Caricamento…").frame(maxWidth: .infinity) }
          if !catalog.loading && catalog.error == nil && catalog.shelves.isEmpty {
            ContentUnavailableView(
              "Nessun contenuto disponibile", systemImage: destination.symbol,
              description: Text(
                destination == .podcasts
                  ? "Cerca un podcast per nome oppure aggiorna la pagina."
                  : "Aggiorna per riprovare."))
          }
          if catalog.continuation != nil {
            Button("Carica altri") { Task { await catalog.more() } }.disabled(catalog.loading)
              .padding()
          }
        }
      }.padding(.vertical)
    }.navigationTitle(destination.title).inlineNavigationTitle()
      .refreshable { await catalog.reload() }
      .task(id: library.session) {
        await catalog.configure(session: library.session, country: country)
      }
      .task(id: country) {
        await catalog.configure(session: library.session, country: country)
      }
  }
}

struct PodcastSearchScreen: View {
  @StateObject private var search = MusicSearchModel()
  @EnvironmentObject private var library: LibraryModel
  var body: some View {
    MusicSearchScreen(search: search).navigationTitle("Cerca podcast")
      .task(id: library.session) {
        search.configure(session: library.session)
        search.select(.category(.podcasts))
      }
  }
}

struct FollowArtistButton: View {
  let artist: DiscoveryItem
  @EnvironmentObject private var library: LibraryModel
  var body: some View {
    Button {
      Task { await library.toggleFollow(artist) }
    } label: {
      Label(
        library.isFollowed(artist.mediaId) ? "Non seguire più" : "Segui artista",
        systemImage: library.isFollowed(artist.mediaId) ? "person.badge.minus" : "person.badge.plus"
      )
    }.disabled(library.pendingFollows.contains(artist.mediaId))
      .accessibilityIdentifier("follow-artist")
      .task(id: library.session) { await library.load(.artists) }
  }
}

struct ArtistReleasesScreen: View {
  @EnvironmentObject private var music: MusicModel
  @EnvironmentObject private var library: LibraryModel
  var body: some View { ArtistReleasesContent(releases: music.releases) }
}
private struct ArtistReleasesContent: View {
  @ObservedObject var releases: ArtistReleases
  @EnvironmentObject private var music: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @State private var notificationStatus = ""
  var body: some View {
    List {
      if library.session == nil {
        Button("Accedi a YouTube Music") { library.showLogin = true }
        Text("Gli avvisi usano gli artisti seguiti dell’account collegato.")
      } else {
        Section {
          Toggle(
            "Avvisi nuove uscite",
            isOn: Binding(
              get: { releases.state.enabled },
              set: { enabled in
                #if os(iOS)
                  Task {
                    await AppleAppSession.shared.releaseNotifications.enable(enabled)
                    notificationStatus = await AppleAppSession.shared.releaseNotifications
                      .authorizationMessage()
                  }
                #else
                  releases.setEnabled(enabled)
                #endif
              })
          ).accessibilityIdentifier("release-alerts-toggle")
          Text(
            "Il primo controllo registra le uscite già presenti senza notifiche. I controlli successivi segnalano le novità. iOS decide quando eseguire i controlli in background; puoi controllare anche da qui."
          ).font(.caption).foregroundStyle(.secondary)
          if !notificationStatus.isEmpty {
            Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
          }
          if let date = releases.state.lastCheck {
            Text("Ultimo controllo: " + date.formatted(date: .abbreviated, time: .shortened)).font(
              .caption)
          }
          Button("Controlla ora") {
            Task {
              #if os(iOS)
                await AppleAppSession.shared.releaseNotifications.refresh(force: true)
              #else
                await library.load(.artists, force: true)
                if library.state(.artists).error == nil {
                  _ = await releases.check(artists: library.state(.artists).items, force: true)
                }
              #endif
            }
          }.disabled(releases.busy || !releases.state.enabled).accessibilityIdentifier(
            "check-releases")
          if releases.busy { ProgressView("Controllo gli artisti seguiti…") }
          if let error = releases.error ?? library.state(.artists).error {
            Text(error).foregroundStyle(.orange)
          }
        }
        Section("Artisti seguiti") {
          if library.state(.artists).loading { ProgressView() }
          if library.state(.artists).loaded && library.state(.artists).items.isEmpty {
            Text("Segui un artista dalla sua pagina per riceverne le novità.")
          }
          ForEach(library.state(.artists).items) { artist in
            HStack {
              NavigationLink {
                HomeBrowseView(title: artist.title, target: BrowseTarget(browseId: artist.mediaId))
              } label: {
                HStack {
                  Artwork(url: artist.artwork).frame(width: 44, height: 44).clipShape(Circle())
                  Text(artist.title)
                }
              }
              FollowArtistButton(artist: artist).labelStyle(.iconOnly).buttonStyle(.borderless)
            }
          }
        }
        Section("Nuove uscite rilevate") {
          if releases.state.notices.isEmpty {
            Text("Nessuna nuova uscita rilevata dopo il primo controllo.").foregroundStyle(
              .secondary)
          }
          ForEach(releases.state.notices) { notice in
            DiscoveryItemLink(item: notice.release, queue: []) {
              HStack {
                Artwork(url: notice.release.artwork).frame(width: 56, height: 56).clipShape(
                  RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                  Text(notice.release.title)
                  Text(notice.artist.title).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
          if !releases.state.notices.isEmpty {
            Button("Svuota avvisi", role: .destructive) { releases.clearNotices() }
          }
        }
      }
    }.navigationTitle("Nuove uscite").inlineNavigationTitle()
      .task(id: library.session) {
        releases.configure(library.session)
        await library.load(.artists)
      }
  }
}

struct MusicSuggestionsScreen: View {
  @EnvironmentObject private var music: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @StateObject private var suggestions: MusicSuggestionsModel
  @State private var request = ""
  @FocusState private var requestFocused: Bool
  @State private var useCurrent = true
  @State private var playlistTitle = "Consigli NoteNarrate"
  @State private var saving = false
  @State private var saveMessage: String?
  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-discovery-extras") {
        _suggestions = StateObject(
          wrappedValue: MusicSuggestionsModel(
            generate: { _, _, _, _ in
              [
                MusicSuggestion(
                  title: "Brano suggerito", artist: "Artista di prova",
                  reason: "Una proposta per il tuo momento.")
              ]
            },
            search: { _, _ in
              [
                DiscoveryItem(
                  kind: .song, mediaId: "suggested-fixture", title: "Brano suggerito",
                  subtitle: "Artista di prova", artwork: nil)
              ]
            }))
      } else {
        _suggestions = StateObject(wrappedValue: MusicSuggestionsModel())
      }
    #else
      _suggestions = StateObject(wrappedValue: MusicSuggestionsModel())
    #endif
  }
  private var playable: [Song] { suggestions.results.compactMap(\.item).map(Song.init) }
  var body: some View {
    List {
      Section("Cosa vuoi ascoltare?") {
        TextField("Es. rock italiano per un viaggio", text: $request, axis: .vertical).lineLimit(
          2...4
        ).focused($requestFocused).accessibilityIdentifier("ai-music-request")
        if let current = music.current {
          Toggle("Ispirati anche a “\(current.title)”", isOn: $useCurrent)
        }
        Text(
          "A Google vengono inviati la richiesta e, se attivo, titolo e artista del brano corrente. La chiave Gemini è quella delle Impostazioni. Verifico i consigli sul catalogo YouTube Music prima di renderli riproducibili."
        ).font(.caption).foregroundStyle(.secondary)
        Button(suggestions.busy ? "Annulla" : "Trova musica") {
          requestFocused = false
          if suggestions.busy {
            suggestions.cancel()
            return
          }
          let key: String
          #if DEBUG
            key =
              ProcessInfo.processInfo.arguments.contains("--test-discovery-extras")
              ? "fixture" : music.apiKey
          #else
            key = music.apiKey
          #endif
          saveMessage = nil
          Task {
            await suggestions.start(
              key: key, model: music.textModel, request: request,
              seeds: useCurrent ? music.current.map { [$0] } ?? [] : [], session: library.session)
          }
        }.disabled(
          request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.count > 1200
        ).accessibilityIdentifier("generate-ai-music")
        if suggestions.busy { ProgressView(suggestions.status) }
        if let error = suggestions.error { Text(error).foregroundStyle(.orange) }
      }
      if !playable.isEmpty {
        Section {
          Button("Ascolta tutti") {
            if let first = playable.first { music.play(first, queue: playable) }
          }.accessibilityIdentifier("play-ai-suggestions")
          Button("Aggiungi tutti alla coda") { for song in playable { music.enqueue(song) } }
          if library.session != nil {
            TextField("Nome playlist privata", text: $playlistTitle)
            Button("Salva come playlist privata") {
              guard let session = library.session else { return }
              saving = true
              Task {
                do {
                  _ = try await YouTubeBrowse(session: session).createPlaylist(
                    title: playlistTitle, videoIDs: playable.map(\.id))
                  guard library.session == session else {
                    saving = false
                    return
                  }
                  await library.load(.playlists, force: true)
                  saveMessage = "Playlist privata creata."
                } catch { saveMessage = "Creazione non confermata. Riprova." }
                saving = false
              }
            }.disabled(
              saving || playlistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          if let saveMessage { Text(saveMessage).font(.caption) }
        }
      }
      ForEach(suggestions.results) { result in
        Section {
          if let item = result.item {
            DiscoveryItemLink(item: item, queue: suggestions.results.compactMap(\.item)) {
              HStack {
                Artwork(url: item.artwork).frame(width: 52, height: 52).clipShape(
                  RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                  Text(item.title).foregroundStyle(.primary)
                  Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
              }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }
          } else {
            Text(result.suggestion.title + " · " + result.suggestion.artist)
            Label(
              "Nessuna corrispondenza verificata", systemImage: "exclamationmark.magnifyingglass"
            ).font(.caption).foregroundStyle(.secondary)
          }
          Text(result.suggestion.reason).font(.caption).foregroundStyle(.secondary)
        }
      }
    }.navigationTitle("Consigli IA").inlineNavigationTitle()
      .onChange(of: library.session) { _, _ in suggestions.reset() }
      .onDisappear { suggestions.cancel() }
  }
}

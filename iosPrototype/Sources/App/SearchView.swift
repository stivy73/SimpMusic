import SwiftUI

struct MusicSearchScreen: View {
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @ObservedObject var search: MusicSearchModel
  @State private var playlistSong: Song?

  var body: some View {
    VStack(spacing: 0) {
      #if os(macOS)
        HStack {
          TextField("Canzoni, album, artisti, playlist…", text: $search.query)
            .textFieldStyle(.roundedBorder).accessibilityIdentifier("mac-search-field")
            .onSubmit { search.submit() }
          Button("Cerca", systemImage: "magnifyingglass") { search.submit() }
            .accessibilityIdentifier("mac-search-submit")
        }.padding()
      #endif
      HStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(MusicSearchScope.values) { value in
                Button {
                  search.select(value)
                } label: {
                  Text(value.title).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(search.scope == value ? Color.black : Color.primary)
                    .background(
                      search.scope == value ? Color.cyan : Color.gray.opacity(0.2), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("search-filter-" + value.id)
                  .accessibilityAddTraits(search.scope == value ? .isSelected : [])
                  .id(value.id)
              }
            }.padding(.horizontal).padding(.vertical, 10)
          }.accessibilityIdentifier("search-filters")
            .onChange(of: search.scope) { _, value in proxy.scrollTo(value.id, anchor: .center) }
        }
        Menu {
          ForEach(MusicSearchScope.values) { value in
            Button {
              search.select(value)
            } label: {
              Label(
                value.title,
                systemImage: search.scope == value ? "checkmark" : "line.3.horizontal.decrease")
            }.accessibilityIdentifier("search-menu-" + value.id)
          }
        } label: {
          Image(systemName: "line.3.horizontal.decrease.circle").font(.title3).frame(
            width: 44, height: 44)
        }.accessibilityLabel("Categorie di ricerca").accessibilityIdentifier("search-category-menu")
          .padding(.trailing, 8)
      }
      if search.submittedQuery.isEmpty {
        history
      } else {
        List {
          Text("Risultati per “\(search.submittedQuery)”").font(.caption).foregroundStyle(
            .secondary
          )
          .accessibilityIdentifier("search-query")
          ForEach(search.sections) { section in
            Section {
              if section.loading {
                ProgressView("Cerco \(section.filter.rawValue.lowercased())…")
              } else if let error = section.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("Riprova \(section.filter.rawValue)") { search.retry(section.filter) }
                  .accessibilityIdentifier("search-retry-" + section.id)
              } else if section.items.isEmpty {
                Text("Nessun risultato").foregroundStyle(.secondary)
              } else {
                let visible = search.scope == .all ? Array(section.items.prefix(6)) : section.items
                ForEach(visible) { item in
                  result(item, filter: section.filter, queue: section.items)
                }
                if search.scope == .all && (section.items.count > 6 || section.continuation != nil)
                {
                  Button("Mostra tutti: \(section.filter.rawValue)") {
                    search.select(.category(section.filter))
                  }
                  .accessibilityIdentifier("search-all-" + section.id)
                } else if search.scope != .all {
                  if let error = section.moreError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                  }
                  if section.loadingMore {
                    ProgressView("Carico altri risultati…")
                  } else if section.continuation != nil {
                    Button(section.moreError == nil ? "Altri risultati" : "Riprova altri risultati")
                    {
                      search.loadMore(section.filter)
                    }.accessibilityIdentifier("search-more-" + section.id)
                  }
                }
              }
            } header: {
              Label(section.filter.rawValue, systemImage: section.filter.symbol)
            }
          }
        }.listStyle(.plain).accessibilityIdentifier("search-results")
          .scrollDismissesKeyboard(.interactively)
      }
    }.navigationTitle("Cerca")
      #if os(iOS)
        .searchable(
          text: $search.query, placement: .navigationBarDrawer(displayMode: .always),
          prompt: "Canzoni, album, artisti, playlist…"
        )
        .onSubmit(of: .search) { search.submit() }
      #endif
      .onChange(of: search.query) { _, value in
        if value.isEmpty && !search.submittedQuery.isEmpty { search.clear() }
      }
      .task(id: library.session) { search.configure(session: library.session) }
      .sheet(item: $playlistSong) { AddToPlaylistSheet(song: $0) }
  }

  private var history: some View {
    Group {
      if search.history.isEmpty {
        ContentUnavailableView(
          "Cerca su YouTube Music", systemImage: "magnifyingglass",
          description: Text("Canzoni, album, artisti, playlist, video e podcast."))
      } else {
        List {
          Section {
            ForEach(search.history, id: \.self) { query in
              Button {
                search.submit(query)
              } label: {
                Label(query, systemImage: "clock.arrow.circlepath")
              }.accessibilityIdentifier("search-history-" + query)
                .swipeActions {
                  Button("Elimina", role: .destructive) { search.removeHistory(query) }
                }
            }
            Button("Cancella cronologia", role: .destructive) { search.removeHistory() }
              .accessibilityIdentifier("search-clear-history")
          } header: {
            Text("Ricerche recenti · solo su questo dispositivo")
          }
        }.listStyle(.plain)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func result(_ item: DiscoveryItem, filter: MusicSearchFilter, queue: [DiscoveryItem])
    -> some View
  {
    Group {
      if item.kind == .song {
        Button {
          model.play(Song(item), queue: queue.filter { $0.kind == .song }.map(Song.init))
        } label: {
          row(item, filter: filter)
        }.contextMenu {
          QueueActions(song: Song(item))
          YouTubeLikeButton(song: Song(item))
          Button("Aggiungi a playlist") { playlistSong = Song(item) }
        }
      } else if item.kind == .album {
        NavigationLink {
          AlbumView(
            album: LibraryAlbum(
              id: item.mediaId, title: item.title, artist: item.subtitle, artwork: item.artwork),
            identity: library.session?.identity)
        } label: {
          row(item, filter: filter)
        }
      } else if item.kind == .playlist, filter != .podcasts, library.session != nil {
        NavigationLink {
          RemotePlaylistView(playlist: item)
        } label: {
          row(item, filter: filter)
        }
      } else if let target = item.target {
        NavigationLink {
          HomeBrowseView(title: item.title, target: target)
        } label: {
          row(item, filter: filter)
        }
        .contextMenu {
          if item.kind == .artist {
            Button {
              model.startRadio(artistID: item.mediaId, title: item.title)
            } label: {
              Label("Radio dell’artista", systemImage: "dot.radiowaves.left.and.right")
            }
          }
        }
      }
    }.accessibilityIdentifier("search-result-" + filter.identifier + "-" + item.mediaId)
  }
  private func row(_ item: DiscoveryItem, filter: MusicSearchFilter) -> some View {
    HStack(spacing: 14) {
      Artwork(url: item.artwork).frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: item.kind == .artist ? 29 : 10))
      VStack(alignment: .leading, spacing: 5) {
        Text(item.title).fontWeight(.semibold).foregroundStyle(.primary).lineLimit(2)
        Text(filter == .podcasts && item.subtitle == "Playlist" ? "Podcast" : item.subtitle)
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
      }
      Spacer()
      Image(systemName: item.kind == .song ? "play.circle.fill" : filter.symbol)
        .foregroundStyle(.secondary)
    }.padding(.vertical, 4)
  }
}

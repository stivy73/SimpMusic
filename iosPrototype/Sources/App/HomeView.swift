import SwiftUI

/// Uses the same browse endpoints and filter parameters as Android HomeScreen.
struct HomeView: View {
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @StateObject private var home: HomeModel
  let onSearch: () -> Void
  let onSettings: () -> Void

  init(onSearch: @escaping () -> Void, onSettings: @escaping () -> Void, home: HomeModel? = nil) {
    self.onSearch = onSearch
    self.onSettings = onSettings
    _home = StateObject(wrappedValue: home ?? HomeModel())
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        Text(greeting).foregroundStyle(.secondary).padding(.horizontal, 20)
          .accessibilityIdentifier("home-status")
          .accessibilityValue(home.loading ? "loading" : "ready")
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(HomeFilter.values) { filter in
              Button {
                Task { await home.select(filter) }
              } label: {
                Text(filter.title).font(.subheadline.weight(.semibold))
                  .padding(.horizontal, 18).padding(.vertical, 10)
                  .foregroundStyle(home.selectedFilter == filter ? Color.black : Color.primary)
                  .background(
                    home.selectedFilter == filter ? Color.cyan : Color.clear, in: Capsule()
                  )
                  .overlay(
                    Capsule().stroke(home.selectedFilter == filter ? .clear : .gray.opacity(0.55)))
              }.buttonStyle(.plain).accessibilityIdentifier("home-filter-\(filter.id)")
                .accessibilityAddTraits(home.selectedFilter == filter ? .isSelected : [])
                .accessibilityValue(
                  home.selectedFilter == filter ? "Selezionato" : "Non selezionato")
            }
          }.padding(.horizontal, 20)
        }
        if library.session == nil {
          Button {
            library.showLogin = true
          } label: {
            Label(
              "Accedi per Ascolta di nuovo e consigli personali", systemImage: "person.crop.circle"
            )
            .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.bordered).padding(.horizontal, 20)
        }
        if home.loading {
          ProgressView("Carico la Home di YouTube Music…").frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if let error = home.error {
          HomeErrorView(message: error) { Task { await home.refresh() } }
        } else if home.shelves.isEmpty && home.categories.isEmpty {
          ContentUnavailableView(
            "Nessun consiglio disponibile", systemImage: "music.note",
            description: Text("Aggiorna la pagina per recuperare nuove proposte."))
        }
        DiscoveryShelves(shelves: home.shelves)
        DiscoveryContinuation(home: home)
        DiscoveryCategories(sections: home.categories)
        if let error = home.categoryError {
          HomeErrorView(message: error) { Task { await home.refresh() } }
        }
      }.padding(.vertical, 12)
    }
    .accessibilityIdentifier("home-scroll")
    .navigationTitle("NoteNarrate")
    .toolbar {
      if library.session != nil {
        ToolbarItem(placement: .platformTrailing) {
          NavigationLink {
            HomeBrowseView(title: "Cronologia", target: BrowseTarget(browseId: "FEmusic_history"))
          } label: {
            Label("Cronologia di YouTube Music", systemImage: "clock.arrow.circlepath")
          }
          .accessibilityLabel("Cronologia di YouTube Music")
        }
      }
      ToolbarItem(placement: .platformTrailing) {
        Button(action: onSearch) { Label("Cerca musica", systemImage: "magnifyingglass") }
          .accessibilityLabel("Cerca musica")
      }
      ToolbarItem(placement: .platformTrailing) {
        Button(action: onSettings) { Label("Impostazioni", systemImage: "gearshape.fill") }
          .accessibilityLabel("Impostazioni")
      }
    }
    .refreshable { await home.refresh() }
    .task(id: library.session) { await home.configure(session: library.session) }
  }

  private var greeting: String {
    switch Calendar.current.component(.hour, from: Date()) {
    case 5..<12: "Buondì"
    case 12..<18: "Buon pomeriggio"
    default: "Buonasera"
    }
  }
}

struct HomeBrowseView: View {
  let title: String
  let target: BrowseTarget
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @Environment(\.dismiss) private var dismiss
  @StateObject private var home: HomeModel
  @State private var identity: String?

  init(title: String, target: BrowseTarget) {
    self.title = title
    self.target = target
    _home = StateObject(wrappedValue: HomeModel(target: target))
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 26) {
        if home.loading {
          ProgressView("Carico \(title)…").frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let error = home.error {
          HomeErrorView(message: error) { Task { await home.refresh() } }
        } else if home.shelves.isEmpty && home.categories.isEmpty {
          ContentUnavailableView("Nessun contenuto disponibile", systemImage: "music.note")
        }
        DiscoveryShelves(shelves: home.shelves, songsAsList: true)
        DiscoveryCategories(sections: home.categories)
        DiscoveryContinuation(home: home)
      }.padding(.vertical, 16)
    }.navigationTitle(title).inlineNavigationTitle()
      .toolbar {
        if target.browseId.hasPrefix("UC") {
          Button {
            model.startRadio(artistID: target.browseId, title: title)
          } label: {
            Label("Radio dell’artista", systemImage: "dot.radiowaves.left.and.right")
          }
        }
      }
      .refreshable { await home.refresh() }
      .task {
        identity = library.session?.identity
        await home.configure(session: library.session)
      }
      .onChange(of: library.session?.identity) { _, value in if value != identity { dismiss() } }
  }
}

private struct DiscoveryShelves: View {
  let shelves: [HomeShelf]
  var songsAsList = false
  var body: some View {
    ForEach(shelves) { shelf in
      VStack(alignment: .leading, spacing: 14) {
        if !shelf.title.isEmpty {
          HStack(spacing: 12) {
            if let avatar = shelf.avatar {
              Artwork(url: avatar).frame(width: 46, height: 46).clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
              if !shelf.subtitle.isEmpty {
                Text(shelf.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              Text(shelf.title).font(.title2.bold()).accessibilityIdentifier("home-shelf-title")
            }
            Spacer(minLength: 8)
            if let target = shelf.more {
              NavigationLink("Altro") { HomeBrowseView(title: shelf.title, target: target) }
                .font(.subheadline).accessibilityLabel("Altro: \(shelf.title)")
            } else {
              NavigationLink("Altro") { DiscoveryGridView(title: shelf.title, items: shelf.items) }
                .font(.subheadline).accessibilityLabel("Altro: \(shelf.title)")
            }
          }.padding(.horizontal, 20)
        }
        if songsAsList && shelf.items.allSatisfy({ $0.kind == .song }) {
          ForEach(shelf.items) { item in
            DiscoveryItemLink(item: item, queue: shelf.items) {
              HStack(spacing: 14) {
                Artwork(url: item.artwork).frame(width: 58, height: 58)
                  .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                  Text(item.title).foregroundStyle(.primary).fontWeight(.semibold).lineLimit(2)
                  Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.circle.fill").font(.title2)
              }.padding(.horizontal, 20).padding(.vertical, 5).contentShape(Rectangle())
            }
          }
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 16) {
              ForEach(shelf.items) { item in
                DiscoveryItemLink(item: item, queue: shelf.items.filter { $0.kind == .song }) {
                  DiscoveryCard(item: item)
                }
              }
            }.padding(.horizontal, 20)
          }
        }
      }
    }
  }
}

private struct DiscoveryCard: View {
  let item: DiscoveryItem
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Artwork(url: item.artwork).frame(width: 164, height: 164)
        .clipShape(RoundedRectangle(cornerRadius: item.kind == .artist ? 82 : 14))
      Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
      Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
    }.frame(width: 164, alignment: .leading).foregroundStyle(.primary)
      .accessibilityElement(children: .combine)
  }
}

private struct DiscoveryItemLink<Content: View>: View {
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  let item: DiscoveryItem
  let queue: [DiscoveryItem]
  @ViewBuilder var content: () -> Content
  var body: some View {
    Group {
      if item.kind == .song {
        Button {
          model.play(Song(item), queue: queue.map(Song.init))
        } label: {
          content()
        }.buttonStyle(.plain).contextMenu { QueueActions(song: Song(item)) }
      } else if item.kind == .album {
        NavigationLink {
          AlbumView(
            album: LibraryAlbum(
              id: item.mediaId, title: item.title,
              artist: item.subtitle, artwork: item.artwork), identity: library.session?.identity)
        } label: {
          content()
        }.buttonStyle(.plain)
      } else if let target = item.target {
        NavigationLink {
          HomeBrowseView(title: item.title, target: target)
        } label: {
          content()
        }.buttonStyle(.plain).contextMenu {
          if item.kind == .artist {
            Button {
              model.startRadio(artistID: item.mediaId, title: item.title)
            } label: {
              Label("Radio dell’artista", systemImage: "dot.radiowaves.left.and.right")
            }
          }
        }
      }
    }.accessibilityIdentifier("home-item-\(item.id)")
  }
}

private struct DiscoveryGridView: View {
  let title: String
  let items: [DiscoveryItem]
  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 20)], spacing: 24) {
        ForEach(items) { item in
          DiscoveryItemLink(item: item, queue: items.filter { $0.kind == .song }) {
            DiscoveryCard(item: item)
          }
        }
      }.padding(20)
    }.navigationTitle(title)
  }
}

private struct DiscoveryCategories: View {
  let sections: [HomeCategorySection]
  var body: some View {
    ForEach(sections) { section in
      VStack(alignment: .leading, spacing: 14) {
        Text(section.title).font(.title2.bold()).accessibilityIdentifier("home-category-title")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
          ForEach(section.items) { item in
            NavigationLink {
              HomeBrowseView(title: item.title, target: item.target)
            } label: {
              HStack(spacing: 12) {
                Rectangle().fill(color(item.stripeColor)).frame(width: 7)
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                  .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
              }.frame(minHeight: 60).padding(.trailing, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("home-category-\(item.title)")
          }
        }
      }.padding(.horizontal, 20)
    }
  }
  private func color(_ argb: UInt32) -> Color {
    Color(
      red: Double((argb >> 16) & 255) / 255,
      green: Double((argb >> 8) & 255) / 255, blue: Double(argb & 255) / 255)
  }
}

private struct DiscoveryContinuation: View {
  @ObservedObject var home: HomeModel
  var body: some View {
    if let error = home.continuationError {
      HomeErrorView(message: error) {
        Task { if home.continuation == nil { await home.refresh() } else { await home.loadMore() } }
      }
    } else if home.continuation != nil {
      ProgressView("Carico altre sezioni…").frame(maxWidth: .infinity).padding()
        .task(id: home.continuation) { await home.loadMore() }
    }
  }
}

private struct HomeErrorView: View {
  let message: String
  let retry: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(message, systemImage: "wifi.exclamationmark").font(.subheadline)
      Button("Riprova", action: retry).buttonStyle(.bordered)
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
  }
}

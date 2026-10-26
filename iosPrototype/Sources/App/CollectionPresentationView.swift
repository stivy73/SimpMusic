import SwiftUI

/// Presentation changes only the visible order; the catalogue and remote playlist are never mutated.
struct LibraryCollection<Item: Identifiable, Cell: View>: View where Item.ID: Hashable {
  let items: [Item]
  let key: String
  let title: (Item) -> String
  let artist: (Item) -> String
  let cell: (Item, CollectionLayout, [Item]) -> Cell
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var presentation: CollectionPresentation
  init(
    items: [Item], key: String, defaultLayout: CollectionLayout = .grid,
    title: @escaping (Item) -> String, artist: @escaping (Item) -> String,
    @ViewBuilder cell: @escaping (Item, CollectionLayout, [Item]) -> Cell
  ) {
    self.items = items
    self.key = key
    self.title = title
    self.artist = artist
    self.cell = cell
    _presentation = State(initialValue: CollectionPreferences().load(key, layout: defaultLayout))
  }
  private var ordered: [Item] { presentation.sorted(items, title: title, artist: artist) }
  private var index: [(String, Item.ID)] {
    var seen = Set<String>()
    return ordered.compactMap { item in
      let letter = presentation.indexKey(title: title(item), artist: artist(item))
      return seen.insert(letter).inserted ? (letter, item.id) : nil
    }
  }
  var body: some View {
    ScrollViewReader { proxy in
      VStack(spacing: 0) {
        if presentation.alphabeticalIndex && presentation.order != .original && !items.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
              ForEach(index, id: \.0) { letter, id in
                Button(letter) {
                  withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                }.font(.subheadline.bold()).frame(minWidth: 44, minHeight: 44)
                  .accessibilityLabel("Vai a " + letter).accessibilityIdentifier(
                    "collection-index-" + letter)
              }
            }.padding(.horizontal)
          }.background(.thinMaterial).accessibilityIdentifier("collection-alphabet")
        }
        ScrollView {
          if presentation.layout == .grid {
            LazyVGrid(
              columns: [
                GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 145), spacing: 16)
              ], spacing: 22
            ) {
              ForEach(ordered) { item in cell(item, .grid, ordered).id(item.id) }
            }.padding()
          } else {
            LazyVStack(spacing: 0) {
              ForEach(ordered) { item in
                cell(item, .list, ordered).padding(.vertical, 7).id(item.id)
                Divider()
              }
            }.padding(.horizontal)
          }
        }.accessibilityIdentifier("collection-" + presentation.layout.rawValue)
      }
      .toolbar {
        Menu {
          Section("Visualizzazione") {
            ForEach(CollectionLayout.allCases, id: \.self) { layout in
              Button {
                presentation.layout = layout
              } label: {
                Label(
                  layout.title,
                  systemImage: presentation.layout == layout ? "checkmark" : layout.symbol)
              }.accessibilityIdentifier("collection-layout-" + layout.rawValue)
            }
          }
          Section("Ordina per") {
            ForEach(CollectionOrder.allCases, id: \.self) { order in
              Button {
                presentation.order = order
                if order == .original { presentation.alphabeticalIndex = false }
              } label: {
                Label(
                  order.title,
                  systemImage: presentation.order == order ? "checkmark" : "arrow.up.arrow.down")
              }.accessibilityIdentifier("collection-order-" + order.rawValue)
            }
            Button {
              presentation.descending.toggle()
            } label: {
              Label(
                "Ordine inverso", systemImage: presentation.descending ? "checkmark" : "arrow.down")
            }.accessibilityIdentifier("collection-descending")
          }
          Button {
            presentation.alphabeticalIndex.toggle()
            if presentation.alphabeticalIndex && presentation.order == .original {
              presentation.order = .title
            }
          } label: {
            Label(
              "Indice alfabetico",
              systemImage: presentation.alphabeticalIndex ? "checkmark" : "textformat.abc")
          }.accessibilityIdentifier("collection-toggle-index")
        } label: {
          Label("Visualizzazione e ordine", systemImage: "slider.horizontal.3")
        }.accessibilityIdentifier("collection-options")
      }
      .onChange(of: presentation) { _, value in CollectionPreferences().save(value, collection: key)
      }
    }
  }
}

struct LibraryItemLabel: View {
  let title: String
  let subtitle: String
  let artwork: URL?
  let layout: CollectionLayout
  var circular = false
  var playable = false
  var body: some View {
    Group {
      if layout == .grid {
        VStack(alignment: .leading, spacing: 8) {
          Artwork(url: artwork).aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: circular ? 120 : 14))
          Text(title).fontWeight(.semibold).lineLimit(2)
          Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
      } else {
        HStack(spacing: 14) {
          Artwork(url: artwork).frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: circular ? 29 : 12))
          VStack(alignment: .leading, spacing: 5) {
            Text(title).fontWeight(.semibold).lineLimit(2)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
          Spacer()
          Image(systemName: playable ? "play.circle.fill" : "chevron.right").font(.title3)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.foregroundStyle(.primary).contentShape(Rectangle())
  }
}

struct LibrarySongCollection: View {
  let songs: [Song]
  let key: String
  @EnvironmentObject private var model: MusicModel
  @State private var playlistSong: Song?
  var body: some View {
    LibraryCollection(
      items: songs, key: key, defaultLayout: .list, title: \.title, artist: \.artist
    ) { song, layout, ordered in
      Button {
        model.play(song, queue: ordered)
      } label: {
        LibraryItemLabel(
          title: song.title, subtitle: song.artist, artwork: song.artwork, layout: layout,
          playable: true)
      }.buttonStyle(.plain).accessibilityIdentifier("song-" + song.id)
        .contextMenu {
          QueueActions(song: song)
          YouTubeLikeButton(song: song)
          Button("Aggiungi a playlist") { playlistSong = song }
          Button(
            model.favorites.contains(where: { $0.id == song.id })
              ? "Rimuovi dai preferiti locali" : "Salva nei preferiti locali"
          ) { model.toggleFavorite(song) }
        }
    }.sheet(item: $playlistSong) { AddToPlaylistSheet(song: $0) }
  }
}

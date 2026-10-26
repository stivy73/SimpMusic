import Combine
import SwiftUI

enum PlayerOption { case lyrics, video }

/// The same visible actions are used in the player and on every album track.
struct SongOptionsSheet: View {
  let song: Song
  var playerOption: ((PlayerOption) -> Void)? = nil
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @Environment(\.dismiss) private var dismiss
  @State private var playlist = false
  private var liked: Bool { model.favorites.contains { $0.id == song.id } }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 18) {
            Artwork(url: song.artwork).frame(width: 72, height: 72)
              .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
              Text(song.title).font(.title2.bold())
              Text(song.artist).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 16)
          Divider().padding(.bottom, 10)
          Button {
            model.toggleFavorite(song)
          } label: {
            option(liked ? "Piaciuti" : "Mi piace", icon: liked ? "heart.fill" : "heart")
              .foregroundStyle(liked ? .red : .primary)
          }.accessibilityIdentifier("song-option-like")
            .accessibilityValue(liked ? "Attivo" : "Non attivo")
          Button {
            playlist = true
          } label: {
            option("Aggiungi alla playlist", icon: "text.badge.plus")
          }.accessibilityIdentifier("song-option-playlist")
          Button {
            model.enqueue(song, playNext: true)
            dismiss()
          } label: {
            option("Riproduci successivo", icon: "play.circle")
          }.accessibilityIdentifier("song-option-next")
          Button {
            model.enqueue(song)
            dismiss()
          } label: {
            option("Aggiungi alla coda", icon: "text.append")
          }.accessibilityIdentifier("song-option-queue")
          NavigationLink {
            SongContextView(song: song, filter: .artists)
          } label: {
            option("Artisti", icon: "person.2.fill")
          }.accessibilityIdentifier("song-option-artists")
          NavigationLink {
            SongContextView(song: song, filter: .albums)
          } label: {
            option(
              song.albumTitle.map { "Vai all’album · " + $0 } ?? "Vai all’album",
              icon: "opticaldisc")
          }.accessibilityIdentifier("song-option-album")
          Button {
            model.startRadio(song: song)
            dismiss()
          } label: {
            option("Avvia la radio", icon: "dot.radiowaves.left.and.right")
          }.accessibilityIdentifier("song-option-radio")
          ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(song.id)")!) {
            option("Condividi", icon: "square.and.arrow.up")
          }.accessibilityIdentifier("song-option-share")
          Divider().padding(.vertical, 10)
          DownloadAction(song: song).padding(.vertical, 14)
          YouTubeLikeButton(song: song).padding(.vertical, 14)
          if let playerOption {
            Button {
              playerOption(.lyrics)
              dismiss()
            } label: {
              option("Aggiungi o modifica il testo", icon: "square.and.pencil")
            }
            Button {
              playerOption(.video)
              dismiss()
            } label: {
              option("Mostra video", icon: "play.rectangle")
            }
          }
        }.padding(.horizontal, 24).padding(.bottom, 20)
      }.buttonStyle(.plain).tint(.primary)
        .navigationTitle("Opzioni brano").inlineNavigationTitle()
        .toolbar { Button("Chiudi") { dismiss() }.accessibilityIdentifier("song-options-close") }
        .sheet(isPresented: $playlist) { AddToPlaylistSheet(song: song) }
        .onReceive(model.$showPlayer.dropFirst()) { showing in
          if showing { dismiss() }
        }
    }
    #if os(iOS)
      .presentationDetents([.large]).presentationDragIndicator(.visible)
    #endif
  }

  private func option(_ title: String, icon: String) -> some View {
    Label {
      Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
    } icon: {
      Image(systemName: icon).font(.title2).frame(width: 36)
    }.padding(.vertical, 16).contentShape(Rectangle())
  }
}

/// Prefer catalog identifiers. Without one, show actual filtered results for the user to choose.
struct SongContextView: View {
  let song: Song
  let filter: MusicSearchFilter
  @EnvironmentObject private var library: LibraryModel
  @State private var items: [DiscoveryItem] = []
  @State private var loading = true
  @State private var error: String?
  @State private var revision = 0
  var body: some View {
    Group {
      if filter == .albums, let id = song.albumBrowseID {
        AlbumView(
          album: LibraryAlbum(
            id: id, title: song.albumTitle ?? "Album", artist: song.artist, artwork: song.artwork),
          identity: library.session?.identity)
      } else if filter == .artists, let artists = song.artistReferences, artists.count > 1 {
        List(artists, id: \.id) { artist in
          NavigationLink {
            HomeBrowseView(title: artist.name, target: BrowseTarget(browseId: artist.id))
          } label: {
            Label(artist.name, systemImage: "person.fill").padding(.vertical, 12)
          }.accessibilityIdentifier("context-artist-" + artist.id)
        }.listStyle(.plain).navigationTitle("Artisti")
      } else if filter == .artists, let id = song.artistBrowseID {
        HomeBrowseView(title: song.artist, target: BrowseTarget(browseId: id))
      } else {
        Group {
          if loading {
            ProgressView("Cerco nel catalogo…")
          } else if let error {
            ContentUnavailableView {
              Label("Contenuto non disponibile", systemImage: "wifi.exclamationmark")
            } description: {
              Text(error)
            } actions: {
              Button("Riprova") { revision += 1 }
            }
          } else if items.isEmpty {
            ContentUnavailableView("Nessun risultato", systemImage: "magnifyingglass")
          } else {
            List(items) { item in
              DiscoveryItemLink(item: item, queue: []) {
                HStack(spacing: 14) {
                  Artwork(url: item.artwork).frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item.subtitle).foregroundStyle(.secondary)
                  }
                }.padding(.vertical, 4)
              }
            }.listStyle(.plain)
          }
        }.navigationTitle(filter == .albums ? "Album" : "Artisti")
          .task(id: "\(library.session?.identity ?? ""):\(revision)") { await search() }
      }
    }
  }
  private func search() async {
    loading = true
    error = nil
    let account = library.session
    do {
      let query =
        filter == .artists ? song.artist : "\(song.albumTitle ?? song.title) \(song.artist)"
      let result = try await HomeDiscovery(session: account).search(query: query, filter: filter)
      try Task.checkCancellation()
      guard library.session == account else { return }
      items = result
      loading = false
    } catch is CancellationError {} catch {
      self.error = "Non riesco a recuperare i risultati. Controlla la connessione e riprova."
      loading = false
    }
  }
}

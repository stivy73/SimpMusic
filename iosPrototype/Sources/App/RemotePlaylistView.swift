import SwiftUI

struct RemotePlaylistView: View {
  let playlist: DiscoveryItem
  @EnvironmentObject private var library: LibraryModel
  @EnvironmentObject private var music: MusicModel
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: RemotePlaylistModel
  @State private var title: String
  @State private var rename = false
  @State private var renameTitle = ""
  @State private var deleting = false
  @State private var deleteBusy = false
  @State private var account: YouTubeSession?

  init(playlist: DiscoveryItem) {
    self.playlist = playlist
    _title = State(initialValue: playlist.title)
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-remote-library") {
        let fixture = EditablePlaylistFixture()
        _model = StateObject(
          wrappedValue: RemotePlaylistModel(
            id: playlist.mediaId,
            fetch: { _, _ in await fixture.value() },
            edit: { _, _, action in await fixture.edit(action) }))
      } else {
        _model = StateObject(wrappedValue: RemotePlaylistModel(id: playlist.mediaId))
      }
    #else
      _model = StateObject(wrappedValue: RemotePlaylistModel(id: playlist.mediaId))
    #endif
  }

  var body: some View {
    List {
      if model.loading || model.saving || deleteBusy { ProgressView("Sincronizzazione…") }
      if let error = model.error {
        Text(error).foregroundStyle(.orange)
        Button("Riprova") { Task { await model.reload() } }
      }
      if let detail = model.detail {
        Text(
          "\(detail.entries.count) brani · \(detail.editable ? "La tua playlist" : "Sola lettura")"
        )
        .font(.caption).foregroundStyle(.secondary)
        ForEach(detail.entries) { entry in
          Button {
            music.play(
              Song(entry.item), queue: detail.entries.map { Song($0.item) },
              selectedIndex: detail.entries.firstIndex { $0.id == entry.id })
          } label: {
            HStack {
              Artwork(url: entry.item.artwork).frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
              VStack(alignment: .leading) {
                Text(entry.item.title).foregroundStyle(.primary)
                Text(entry.item.subtitle).font(.caption).foregroundStyle(.secondary)
              }
            }
          }.accessibilityIdentifier("playlist-track-" + entry.id).contextMenu {
            QueueActions(song: Song(entry.item))
            YouTubeLikeButton(song: Song(entry.item))
            if detail.editable, let setID = entry.setVideoID {
              Button("Rimuovi dalla playlist", role: .destructive) {
                Task { await model.apply(.remove(videoID: entry.item.mediaId, setID: setID)) }
              }
            }
          }
        }
        .onMove { offsets, destination in
          guard offsets.count == 1, let source = offsets.first,
            let action = try? RemotePlaylist.moveAction(
              entries: detail.entries, from: source, to: destination)
          else { return }
          Task { await model.apply(action) }
        }
        .moveDisabled(
          !detail.editable || detail.entries.contains { $0.setVideoID == nil } || model.saving)
      }
    }.disabled(deleteBusy).navigationTitle(title).inlineNavigationTitle()
      .refreshable { await model.reload() }
      .toolbar {
        if model.detail?.editable == true {
          #if os(iOS)
            EditButton().disabled(model.loading || model.saving)
          #endif
          Menu {
            Button("Rinomina") {
              renameTitle = title
              rename = true
            }
            Button("Elimina playlist", role: .destructive) { deleting = true }
          } label: {
            Label("Opzioni playlist", systemImage: "ellipsis")
          }
          .disabled(model.loading || model.saving || deleteBusy)
        }
      }
      .alert("Rinomina playlist", isPresented: $rename) {
        TextField("Nome", text: $renameTitle)
        Button("Annulla", role: .cancel) {}
        Button("Salva") {
          Task {
            if await model.apply(.rename(renameTitle)) {
              title = renameTitle
              await library.load(.playlists, force: true)
            }
          }
        }
      }
      .confirmationDialog(
        "Eliminare definitivamente questa playlist da YouTube Music?", isPresented: $deleting,
        titleVisibility: .visible
      ) {
        Button("Elimina playlist", role: .destructive) {
          guard let session = library.session else { return }
          deleteBusy = true
          Task {
            do {
              try await YouTubeBrowse(session: session).deletePlaylist(id: playlist.mediaId)
              guard library.session == session else { return }
              await library.load(.playlists, force: true)
              dismiss()
            } catch { model.error = "Eliminazione non confermata. Riprova." }
            deleteBusy = false
          }
        }
      }
      .task(id: library.session) {
        account = library.session
        await model.configure(session: library.session)
      }
      .onChange(of: library.session) { _, value in if value != account { dismiss() } }
  }
}

struct CreatePlaylistSheet: View {
  var song: Song? = nil
  @EnvironmentObject private var library: LibraryModel
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        TextField("Nome playlist", text: $title)
        Text("La playlist viene creata come privata su YouTube Music.").font(.caption)
        if let song { Text("Primo brano: \(song.title)") }
        if let error { Text(error).foregroundStyle(.orange) }
        if busy { ProgressView("Creazione…") }
        Button("Crea playlist") {
          guard let session = library.session else {
            library.showLogin = true
            return
          }
          busy = true
          Task {
            do {
              _ = try await YouTubeBrowse(session: session).createPlaylist(
                title: title, videoIDs: song.map { [$0.id] } ?? [])
              guard library.session == session else {
                dismiss()
                return
              }
              await library.load(.playlists, force: true)
              dismiss()
            } catch { self.error = "Creazione non confermata. Controlla il nome e riprova." }
            busy = false
          }
        }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.navigationTitle("Nuova playlist")
        .toolbar { Button("Chiudi") { dismiss() }.disabled(busy) }
        .interactiveDismissDisabled(busy)
    }
  }
}

struct AddToPlaylistSheet: View {
  let song: Song
  @EnvironmentObject private var library: LibraryModel
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var create = false
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      List {
        Button("Crea una nuova playlist") { create = true }
        if busy || library.state(.playlists).loading { ProgressView("Sincronizzazione…") }
        if let message = error ?? library.state(.playlists).error {
          Text(message).foregroundStyle(.orange)
        }
        ForEach(
          library.state(.playlists).items.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
          }
        ) { item in
          Button(item.title) {
            guard let session = library.session else {
              library.showLogin = true
              return
            }
            busy = true
            error = nil
            Task {
              do {
                let browse = YouTubeBrowse(session: session)
                guard try await browse.canEditPlaylist(id: item.mediaId) else {
                  error = "Questa playlist è in sola lettura. Scegli una tua playlist."
                  busy = false
                  return
                }
                try await browse.editPlaylist(id: item.mediaId, action: .add(song.id))
                guard library.session == session else {
                  dismiss()
                  return
                }
                dismiss()
              } catch { self.error = "Brano non aggiunto. Riprova." }
              busy = false
            }
          }
        }
      }.disabled(busy).navigationTitle("Aggiungi a playlist")
        .searchable(text: $query, prompt: "Cerca playlist")
        .toolbar { Button("Chiudi") { dismiss() }.disabled(busy) }
        .task(id: library.session) { await library.load(.playlists) }
        .sheet(isPresented: $create) { CreatePlaylistSheet(song: song) }
        .interactiveDismissDisabled(busy)
    }
  }
}

#if DEBUG
  private actor EditablePlaylistFixture {
    private var entries: [RemotePlaylistEntry] = ["a", "b", "c"].map { id in
      RemotePlaylistEntry(
        id: id,
        item: DiscoveryItem(
          kind: .song, mediaId: "fixture-" + id,
          title: "Brano " + id, subtitle: "Prova playlist", artwork: nil), setVideoID: id)
    }
    func value() -> RemotePlaylist { RemotePlaylist(editable: true, entries: entries) }
    func edit(_ action: PlaylistAction) {
      if case .remove(_, let set) = action { entries.removeAll { $0.setVideoID == set } }
      if case .move(let set, let before) = action,
        let source = entries.firstIndex(where: { $0.setVideoID == set })
      {
        let entry = entries.remove(at: source)
        let destination = entries.firstIndex { $0.setVideoID == before } ?? entries.count
        entries.insert(entry, at: destination)
      }
    }
  }
#endif

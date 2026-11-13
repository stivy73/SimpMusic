// Adapted from iosPrototype/Sources/App/RemotePlaylistView.swift at 5a277798.
// Retains create/add sheets, occurrence rows, onMove, rename and error/retry flows.
import SwiftUI
@preconcurrency import MusicKit

struct CollectionFavoriteButton:View {
  @EnvironmentObject var music:MusicLibraryModel
  let collection:AppleCollection
  private var resource:(String,String) {switch collection {case .album(let v):("albums",v.id.rawValue);case .playlist(let v):("playlists",v.id.rawValue)}}
  private var confirmed:Bool {music.favoriteStates[resource.0+":"+resource.1]==true}
  var body:some View {
    Button {Task{await music.requestFavorite(type:resource.0,id:resource.1)}} label:{
      Image(systemName:confirmed ? "star.fill":"star").foregroundStyle(confirmed ? .yellow:.primary)
    }.disabled(confirmed || music.sendingFavorite).accessibilityIdentifier("album-favorite")
      .accessibilityLabel(confirmed ? "Preferito in Apple Music":"Aggiungi ai Preferiti Apple Music")
      .task(id:collection.id){if !music.isPlayerFixture {_ = await music.favoriteStatus(type:resource.0,id:resource.1)}}
  }
}
struct AppleCollectionTrackOptions:View {
  @Environment(\.dismiss) private var dismiss
  let row:AppleCollectionRow
  var body:some View {
    NavigationStack {
      List {
        Text(row.title).font(.headline);Text(row.artist).foregroundStyle(.secondary)
        if let song=row.song {SongNavigationActions(song:song)}
        else {Text("Le azioni del brano non sono disponibili per questo elemento.").foregroundStyle(.secondary)}
      }.navigationTitle("Opzioni brano").toolbar{Button("Chiudi"){dismiss()}}
    }
  }
}
struct AppleCreatePlaylistSheet:View {
  var songs:[Song]=[]
  var onCreated:((Playlist)->Void)?=nil
  @EnvironmentObject var music:MusicLibraryModel
  @EnvironmentObject var service:ApplePlaylistService
  @Environment(\.dismiss) private var dismiss
  @State private var title=""
  @State private var error:String?
  var body:some View {
    NavigationStack {
      Form {
        TextField("Nome playlist",text:$title).accessibilityIdentifier("playlist-name")
        Text("La playlist viene creata nella tua libreria Apple Music.").font(.caption)
        if !songs.isEmpty {Text("\(songs.count) brani da aggiungere")}
        if let error {Text(error).foregroundStyle(.orange)}
        if service.busy {ProgressView("Creazione…")}
        Button("Crea playlist") {
          error=nil
          Task {
            do {let result=try await service.create(name:title,songs:songs)
              music.playlists=BrowseHistory.merging([result],music.playlists);onCreated?(result);dismiss()
            } catch {self.error=error.localizedDescription}
          }
        }.disabled(service.busy || (try? PlaylistPolicy.name(title))==nil).accessibilityIdentifier("playlist-create")
      }.navigationTitle("Nuova playlist").toolbar{Button("Chiudi"){dismiss()}.disabled(service.busy)}
        .interactiveDismissDisabled(service.busy)
    }
  }
}
struct AppleAddToPlaylistSheet:View {
  let songs:[Song]
  @EnvironmentObject var music:MusicLibraryModel
  @EnvironmentObject var service:ApplePlaylistService
  @Environment(\.dismiss) private var dismiss
  @State private var query=""
  @State private var create=false
  @State private var created:Playlist?
  @State private var error:String?
  var body:some View {
    NavigationStack {
      List {
        if let created {Label("Playlist “\(created.name)” creata con i brani selezionati.",systemImage:"checkmark.circle.fill");Button("Fine"){dismiss()}}
        Button("Crea una nuova playlist"){create=true}.accessibilityIdentifier("playlist-new-from-song")
        if service.busy || music.loading {ProgressView("Sincronizzazione…")}
        if let error {Text(error).foregroundStyle(.orange)}
        ForEach(music.playlists.filter{query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)}) {playlist in
          Button(playlist.name) {
            error=nil
            Task {do {try await service.add(songs,to:playlist);dismiss()} catch {self.error=error.localizedDescription}}
          }.accessibilityIdentifier("playlist-add-"+playlist.id.rawValue)
        }
      }.disabled(service.busy).navigationTitle("Aggiungi a playlist")
        .searchable(text:$query,prompt:"Cerca playlist")
        .toolbar{Button("Chiudi"){dismiss()}.disabled(service.busy)}
        .task{if !music.isPlayerFixture {await music.refresh()}}
        .sheet(isPresented:$create){AppleCreatePlaylistSheet(songs:songs,onCreated:{created=$0})}
        .interactiveDismissDisabled(service.busy)
    }
  }
}
struct ApplePlaylistEditor:View {
  @EnvironmentObject private var music:MusicLibraryModel
  @EnvironmentObject private var service:ApplePlaylistService
  @Environment(\.dismiss) private var dismiss
  @State private var playlist:Playlist
  @State private var entries:[Playlist.Entry]=[]
  @State private var loading=true
  @State private var failure:String?
  @State private var rename=false
  @State private var renameTitle=""
  init(playlist:Playlist) {_playlist=State(initialValue:playlist)}
  private var editable:Bool {service.createdHere(playlist) && !loading && failure==nil && entries.allSatisfy{$0.playParameters != nil}}
  var body:some View {
    NavigationStack {
      List {
        if loading || service.busy {ProgressView("Sincronizzazione…")}
        if let failure {Text(failure).foregroundStyle(.orange);Button("Riprova"){Task{await reload()}}}
        Text("\(entries.count) brani · \(editable ? "Playlist creata con NoteNarrate Music":"Gestione in Musica")").font(.caption).foregroundStyle(.secondary)
        if !editable && !loading {Text("Per le modifiche non disponibili qui, apri la playlist in Musica.").font(.caption)}
        if let url=playlist.url {Link("Apri playlist in Musica",destination:url)}
        ForEach(Array(entries.enumerated()),id:\.offset) {index,entry in
          HStack {
            CoverRow(artwork:entry.artwork,title:entry.title,subtitle:entry.artistName)
            if editable {Button(role:.destructive){remove(at:index)} label:{Image(systemName:"minus.circle")}.accessibilityLabel("Rimuovi \(entry.title) dalla playlist")}
          }.contextMenu {if case .song(let song)=entry.item {SongNavigationActions(song:song)}}
        }.onMove {offsets,destination in
          guard offsets.count==1,let from=offsets.first,let values=try? PlaylistPolicy.moved(entries,from:from,to:destination) else{return}
          apply(values)
        }.moveDisabled(!editable || service.busy)
      }.disabled(service.busy).navigationTitle(playlist.name).navigationBarTitleDisplayMode(.inline)
        .refreshable{await reload()}
        .toolbar {
          ToolbarItem(placement:.topBarLeading){Button("Chiudi"){dismiss()}.disabled(service.busy)}
          ToolbarItem(placement:.topBarTrailing){if editable {EditButton()}}
          ToolbarItem(placement:.topBarTrailing){Menu {
            if service.createdHere(playlist) {Button("Rinomina"){renameTitle=playlist.name;rename=true}.disabled(loading || failure != nil)}
            if let url=playlist.url {Link("Altre modifiche ed eliminazione in Musica",destination:url)}
          } label:{Label("Opzioni playlist",systemImage:"ellipsis")}.disabled(service.busy)}
        }
        .alert("Rinomina playlist",isPresented:$rename) {
          TextField("Nome",text:$renameTitle);Button("Annulla",role:.cancel){}
          Button("Salva"){Task {do {playlist=try await service.edit(playlist,name:renameTitle,expected:entries);updateList()} catch {failure=error.localizedDescription}}}
        }
        .task{await reload()}.interactiveDismissDisabled(service.busy)
    }
  }
  private func reload() async {
    loading=true;failure=nil;defer{loading=false}
    do {entries=try await music.playlistEntries(playlist)} catch {if !Task.isCancelled {failure=error.localizedDescription}}
  }
  private func remove(at index:Int) {guard entries.indices.contains(index) else{return};var values=entries;values.remove(at:index);apply(values)}
  private func apply(_ values:[Playlist.Entry]) {
    guard editable else{return}
    Task {do {playlist=try await service.edit(playlist,entries:values,expected:entries);updateList();await reload()} catch {failure=error.localizedDescription}}
  }
  private func updateList() {if let index=music.playlists.firstIndex(where:{$0.id==playlist.id}) {music.playlists[index]=playlist}}
}

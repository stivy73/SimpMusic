import SwiftUI
@preconcurrency import MusicKit

struct PlaylistRows: View {
  let playlists:[Playlist]
  var body:some View {
    ForEach(playlists) { playlist in NavigationLink { CollectionScreen(playlist:playlist) } label: { CoverRow(artwork:playlist.artwork,title:playlist.name,subtitle:playlist.curatorName ?? "Playlist") } }
  }
}
struct ArtistRows: View {
  let artists:[Artist]
  var body:some View {
    ForEach(artists) { artist in NavigationLink { ArtistScreen(artist:artist) } label: { CoverRow(artwork:artist.artwork,title:artist.name,subtitle:"Artista") } }
  }
}
struct CollectionScreen: View {
  @EnvironmentObject var music:MusicLibraryModel
  let album:Album?
  let playlist:Playlist?
  @State private var tracks:[Track]=[]
  @State private var entries:[Playlist.Entry]=[]
  @State private var busy=true
  @State private var failure:String?
  init(album:Album) { self.album=album;playlist=nil }
  init(playlist:Playlist) { self.playlist=playlist;album=nil }
  private var title:String { album?.title ?? playlist?.name ?? "Raccolta" }
  var body:some View {
    List {
      Section {
        CoverRow(artwork:album?.artwork ?? playlist?.artwork,title:title,subtitle:album?.artistName ?? playlist?.curatorName ?? "Playlist")
        Button("Riproduci tutto",systemImage:"play.fill") { Task { if let album {await music.play(album:album)} else if let playlist {await music.play(playlist:playlist)} } }
        if let album { Button("Salva album nella libreria",systemImage:"plus") { Task { await music.saveAlbum(album) } } }
        if let id=album?.id ?? playlist?.id {FavoriteControl(type:album == nil ? "playlists":"albums",id:id.rawValue)}
        if let url=album?.url ?? playlist?.url { ShareLink(item:url);Link("Apri in Musica",destination:url) }
      }
      Section("Tracce · \(playlist == nil ? tracks.count:entries.count)") {
        if busy { ProgressView("Caricamento tracce…") }
        if let failure { Text(failure).foregroundStyle(.orange);Button("Riprova") { Task {await load()} } }
        if let playlist {
          ForEach(Array(entries.enumerated()),id:\.offset) { index,entry in
            Button {Task{await music.playPlaylistEntry(playlist,entry:entry)}} label:{
              HStack {Text("\(index+1)").monospacedDigit().foregroundStyle(.secondary);CoverRow(artwork:entry.artwork,title:entry.title,subtitle:entry.playParameters == nil ? "Non disponibile · " + entry.artistName:entry.artistName)}
            }.disabled(entry.playParameters == nil)
              .contextMenu {if case .song(let song)=entry.item {SongNavigationActions(song:song)}}
          }
        } else {
          ForEach(Array(tracks.enumerated()),id:\.offset) { index,track in
            Button {Task{await music.playCollectionTrack(album:album,track:track)}} label:{
              HStack {Text("\(index+1)").monospacedDigit().foregroundStyle(.secondary);CoverRow(artwork:track.artwork,title:track.title,subtitle:track.artistName)}
            }.disabled(track.playParameters == nil)
              .contextMenu {if case .song(let song)=track {SongNavigationActions(song:song)}}
          }
        }
        if !busy && failure == nil && tracks.isEmpty && entries.isEmpty { Text("Nessuna traccia disponibile per questa raccolta.") }
      }
    }.navigationTitle(title).task {await load()}.refreshable {await load()}
  }
  private func load() async {
    busy=true;failure=nil;defer {busy=false}
    do {
      if let playlist {
        entries=try await music.playlistEntries(playlist)
      } else { tracks=try await music.collectionTracks(album:album,playlist:nil) }
    }
    catch {if !Task.isCancelled {failure=error.localizedDescription} }
  }
}
struct ArtistScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  let artist:Artist
  @State private var albums:[Album]=[]
  @State private var songs:[Song]=[]
  @State private var busy=true
  @State private var failure:String?
  var body:some View {
    List {
      Section {CoverRow(artwork:artist.artwork,title:artist.name,subtitle:"Artista");FavoriteControl(type:"artists",id:artist.id.rawValue);if let url=artist.url {Link("Apri in Musica",destination:url)}}
      if busy {ProgressView("Caricamento artista…")}
      if let failure {Text(failure).foregroundStyle(.orange)}
      Section("Brani") {SongRows(songs:songs)}
      Section("Album") {AlbumRows(albums:albums)}
    }.navigationTitle(artist.name).task {
      defer {busy=false}
      do { let detail=try await music.artistDetails(artist);albums=detail.albums;songs=detail.songs }
      catch {if !Task.isCancelled {failure=error.localizedDescription} }
    }
  }
}

struct FavoriteControl:View {
  @EnvironmentObject var music:MusicLibraryModel
  let type:String
  let id:String
  private var confirmed:Bool {music.favoriteStates[type+":"+id] == true}
  var body:some View {
    Button(confirmed ? "Preferito in Apple Music":"Aggiungi ai Preferiti Apple Music",systemImage:confirmed ? "star.fill":"star") {
      Task {await music.requestFavorite(type:type,id:id)}
    }.disabled(confirmed || music.sendingFavorite)
      .task(id:type+":"+id) {_ = await music.favoriteStatus(type:type,id:id)}
  }
}

struct FavoriteLibraryScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  var body:some View {
    List {
      Text("Preferiti restituiti dalla libreria Apple Music. Per rimuoverli usa Musica.").font(.caption)
      if music.loadingFavorites {ProgressView("Verifica Preferiti…")}
      if let failure=music.favoritesFailure {Text(failure).foregroundStyle(.orange);Button("Riprova"){Task{await music.refreshFavorites()}}}
      Section("Brani · \(music.favoriteSongs.count)"){SongRows(songs:music.favoriteSongs)}
      Section("Album · \(music.favoriteAlbums.count)"){AlbumRows(albums:music.favoriteAlbums)}
      Section("Playlist · \(music.favoritePlaylists.count)"){PlaylistRows(playlists:music.favoritePlaylists)}
    }.navigationTitle("Preferiti Apple Music").task{await music.refreshFavorites()}.refreshable{await music.refreshFavorites()}
  }
}

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
struct CollectionScreen:View {
  let collection:AppleCollection
  init(album:Album){collection = .album(album)}
  init(playlist:Playlist){collection = .playlist(playlist)}
  var body:some View {AppleCollectionScreen(collection:collection)}
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

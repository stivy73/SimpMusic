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
  @StateObject private var profile=ArtistProfileStore()
  private var shown:Artist {profile.artist ?? artist}
  var body:some View {
    ScrollView {
      LazyVStack(alignment:.leading,spacing:28) {
        VStack(alignment:.leading,spacing:16) {
          Cover(artwork:shown.artwork).aspectRatio(1,contentMode:.fit).frame(maxWidth:340).clipShape(RoundedRectangle(cornerRadius:24))
          Text(shown.name).font(.largeTitle.bold())
          if let genres=shown.genreNames,!genres.isEmpty {Text(genres.joined(separator:" · ")).foregroundStyle(.secondary)}
          FavoriteControl(type:"artists",id:shown.id.rawValue)
          if let station=shown.station {Button("Radio dell’artista",systemImage:"dot.radiowaves.left.and.right"){Task{
            guard !music.preparingPlayback else{return}
            music.activeCollectionID=nil;music.activeCollectionRowID=nil;music.activeCollectionQueueEntryID=nil
            await music.startPlayback(queue:.init(for:[station]),origin:"Radio artista")
          }}}
          if let notes=shown.editorialNotes?.standard ?? shown.editorialNotes?.short {Text(notes).textSelection(.enabled)}
          if let url=shown.url {ShareLink(item:url){Label("Condividi artista",systemImage:"square.and.arrow.up")};Link("Apri in Musica",destination:url)}
        }.padding(.horizontal,20)
        if profile.busy {ProgressView("Caricamento artista…").frame(maxWidth:.infinity)}
        if let error=profile.error {Text(error).foregroundStyle(.orange);Button("Riprova"){Task{await load()}}}
        AppleDiscoveryShelves(shelves:profile.shelves)
      }.padding(.vertical,16)
    }.navigationTitle(shown.name).navigationBarTitleDisplayMode(.inline).task{await load()}.refreshable{await load()}
  }
  private func load() async {
    #if DEBUG && BROWSE_LAYOUT_FIXTURE
    if music.isPlayerFixture {profile.artist=artist;profile.shelves=[.init(id:"fixture-top",title:"Brani più ascoltati",items:music.songs.map(MusicBrowseItem.song)),.init(id:"fixture-albums",title:"Album",items:music.albums.map(MusicBrowseItem.album))];return}
    #endif
    await profile.load(artist)
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
      .task(id:type+":"+id) {if !music.isPlayerFixture {_ = await music.favoriteStatus(type:type,id:id)}}
  }
}

struct FavoriteLibraryScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  @AppStorage("favorites.selectedCategory") private var category=BrowseKind.songs
  private var items:[MusicBrowseItem] {switch category {
    case .songs:music.favoriteSongs.map(MusicBrowseItem.song)
    case .albums:music.favoriteAlbums.map(MusicBrowseItem.album)
    case .playlists:music.favoritePlaylists.map(MusicBrowseItem.playlist)
    case .artists:music.favoriteArtists.map(MusicBrowseItem.artist)
  }}
  var body:some View {
    VStack {
      ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(BrowseKind.allCases){kind in Button(kind.title){category=kind}.buttonStyle(.bordered).tint(category==kind ? .cyan:.gray)}}.padding(.horizontal)}
      if music.loadingFavorites {ProgressView("Verifica Preferiti…")}
      if let failure=music.favoritesFailure {Text(failure).foregroundStyle(.orange);Button("Riprova"){Task{await music.refreshFavorites()}}}
      MusicCollectionBrowser(items:items,key:"favorites."+category.rawValue).id(category)
      if items.isEmpty && !music.loadingFavorites && music.favoritesFailure==nil {Text("Nessun preferito restituito da Apple Music per questa categoria.").foregroundStyle(.secondary).padding()}
    }.navigationTitle("Preferiti Apple Music").task{await music.refreshFavorites()}
      .refreshable{await music.refreshFavorites()}
      .toolbar {
        Menu {Picker("Categoria",selection:$category){ForEach(BrowseKind.allCases){Text($0.title).tag($0)}}} label:{Label("Categorie",systemImage:"line.3.horizontal.decrease")}
        Button("Aggiorna",systemImage:"arrow.clockwise"){Task{await music.refreshFavorites()}}.disabled(music.loadingFavorites)
      }
  }
}

import SwiftUI
@preconcurrency import MusicKit

struct AppleDiscoveryItemLink<Content:View>:View {
  @EnvironmentObject private var music:MusicLibraryModel
  let item:MusicBrowseItem
  let queue:[MusicBrowseItem]
  @ViewBuilder var content:()->Content
  var body:some View {
    Group {
      switch item {
      case .song(let song):Button {Task{await music.play(song,in:queue.compactMap{if case .song(let v)=$0{return v};return nil})}} label:{content()}.contextMenu{SongNavigationActions(song:song)}
      case .album(let v):NavigationLink{CollectionScreen(album:v)} label:{content()}
      case .playlist(let v):NavigationLink{CollectionScreen(playlist:v)} label:{content()}
      case .artist(let v):NavigationLink{ArtistScreen(artist:v)} label:{content()}
      }
    }.buttonStyle(.plain).accessibilityIdentifier("home-item-"+item.id)
  }
}

struct AppleShelfScreen:View {
  let shelf:AppleShelf
  @EnvironmentObject private var music:MusicLibraryModel
  @StateObject private var page=BrowsePage<MusicBrowseItem>()
  var body:some View {
    VStack {
      if page.busy {ProgressView("Caricamento…")}
      if let error=page.error {Text(error).foregroundStyle(.orange);Button("Riprova"){Task{await load()}}}
      MusicCollectionBrowser(items:page.items,key:"shelf."+shelf.id)
      if page.moreBusy {ProgressView("Altri elementi…")}
      if let error=page.moreError {Text(error).foregroundStyle(.orange)}
      if page.hasMore {Button(page.moreError==nil ? "Altri elementi":"Riprova altri elementi"){Task{await page.more()}}.disabled(page.moreBusy)}
      if page.items.isEmpty && !page.busy && page.error==nil {ContentUnavailableView("Nessun elemento disponibile",systemImage:"music.note")}
    }.navigationTitle(shelf.title).navigationBarTitleDisplayMode(.inline)
      .task{await load()}.toolbar{Button("Aggiorna",systemImage:"arrow.clockwise"){Task{await load()}}.disabled(page.busy || page.moreBusy)}
  }
  private func load() async {
    await page.load {
      if !music.isPlayerFixture,let fetch=shelf.load {return try await fetch()}
      return .init(items:shelf.items)
    }
  }
}

struct MusicHomeScreen:View {
  @EnvironmentObject private var music:MusicLibraryModel
  private var shelves:[AppleShelf] {
    var values:[AppleShelf]=[]
    if !music.recentSongs.isEmpty {values.append(.init(id:"recent",title:"Ascolta di nuovo",items:music.recentSongs.map(MusicBrowseItem.song),load:AppleDiscoveryService.recentPage))}
    values+=music.recommendations.map(AppleDiscoveryService.recommendation).filter{!$0.items.isEmpty}
    if !music.albums.isEmpty {values.append(.init(id:"library-albums",title:"Album della libreria",items:music.albums.map(MusicBrowseItem.album)))}
    if !music.songs.isEmpty {values.append(.init(id:"library-songs",title:"Brani della libreria",items:music.songs.map(MusicBrowseItem.song)))}
    return values
  }
  var body:some View {
    ScrollView {
      LazyVStack(alignment:.leading,spacing:28) {
        if music.subscriptionVerified && !music.canPlayCatalog {Text("Per ascoltare il catalogo, attiva un abbonamento nell’app Musica.").foregroundStyle(.secondary).padding(.horizontal,20)}
        if music.loadingDiscovery || music.loading {ProgressView("Aggiornamento libreria e consigli…").frame(maxWidth:.infinity)}
        if let error=music.discoveryError {Text(error).foregroundStyle(.orange).padding(.horizontal,20);Button("Riprova"){Task{await music.refreshDiscovery()}}.padding(.horizontal,20)}
        AppleDiscoveryShelves(shelves:shelves)
        if shelves.isEmpty && !music.loading && !music.loadingDiscovery {ContentUnavailableView("Nessun contenuto disponibile",systemImage:"music.note",description:Text("Aggiorna la Home o aggiungi musica alla libreria Apple Music."))}
        AppleDiscoveryCategories(sections:AppleCategorySection.explore)
      }.padding(.vertical,12)
    }.accessibilityIdentifier("home-scroll").refreshable{await music.refreshHome()}
      .toolbar {
        NavigationLink{MusicListeningHistoryScreen()} label:{Label("Cronologia di ascolto",systemImage:"clock.arrow.circlepath")}.accessibilityIdentifier("open-listening-history")
        NavigationLink{AppleExploreScreen()} label:{Label("Esplora",systemImage:"square.grid.2x2")}.accessibilityIdentifier("open-explore")
      }
  }
}

struct MusicListeningHistoryScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  var body:some View {
    VStack {
      Text("Ascolti recenti restituiti da Apple Music, dal più recente. Apple può limitare il periodo disponibile.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
      AppleShelfScreen(shelf:.init(id:"history",title:"Cronologia di ascolto",items:music.recentSongs.map(MusicBrowseItem.song),load:AppleDiscoveryService.recentPage))
    }.navigationTitle("Cronologia di ascolto")
  }
}

enum AppleExploreRoute:Hashable {case genres,moods,charts,releases,genre(Genre),mood(MusicMood)}
struct AppleCategoryItem:Identifiable {
  let id:String,title:String,target:AppleExploreRoute
  var stripeColor:UInt32=0xFF28C4DF
}
struct AppleCategorySection:Identifiable {
  let id:String,title:String,items:[AppleCategoryItem]
  static let explore:[Self]=[.init(id:"explore",title:"Esplora",items:[
    .init(id:"genres",title:"Generi musicali",target:.genres),.init(id:"moods",title:"Stati d’animo",target:.moods,stripeColor:0xFFB784EF),
    .init(id:"charts",title:"Classifiche",target:.charts,stripeColor:0xFFFFAB56),.init(id:"releases",title:"Nuove uscite degli artisti",target:.releases,stripeColor:0xFF53C88F)
  ])]
}
struct AppleExploreScreen:View {
  var body:some View {ScrollView{AppleDiscoveryCategories(sections:AppleCategorySection.explore).padding(.vertical,20)}.navigationTitle("Esplora")}
}
struct AppleExploreDestinationScreen:View {
  let destination:AppleExploreRoute
  var body:some View {
    switch destination {
    case .genres:AppleGenresScreen()
    case .moods:ScrollView{AppleDiscoveryCategories(sections:[.init(id:"moods",title:"Stati d’animo",items:MusicMood.allCases.map{.init(id:$0.id,title:$0.title,target:.mood($0))})]).padding(.vertical,20)}.navigationTitle("Stati d’animo")
    case .charts:AppleChartsScreen(genre:nil)
    case .releases:ArtistReleasesScreen()
    case .genre(let value):AppleChartsScreen(genre:value)
    case .mood(let value):AppleMoodScreen(mood:value)
    }
  }
}
struct AppleGenresScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  @State private var genres:[Genre]=[]
  @State private var busy=false
  @State private var error:String?
  var body:some View {
    ScrollView {
      if busy {ProgressView("Caricamento generi…")}
      if let error {Text(error).foregroundStyle(.orange);Button("Riprova"){Task{await load()}}}
      AppleDiscoveryCategories(sections:[.init(id:"genres",title:"Generi musicali",items:genres.map{.init(id:$0.id.rawValue,title:$0.name,target:.genre($0))})])
      if genres.isEmpty && !busy && error==nil {ContentUnavailableView("Nessun genere restituito da Apple Music",systemImage:"music.note.list")}
    }.navigationTitle("Generi").task{await load()}.refreshable{await load()}
  }
  private func load() async {
    busy=true;error=nil;defer{busy=false}
    do {
      #if DEBUG && BROWSE_LAYOUT_FIXTURE
      if music.isPlayerFixture {genres=try JSONDecoder().decode([Genre].self,from:Data(#"[{"id":"14","type":"genres","attributes":{"name":"Pop"}},{"id":"21","type":"genres","attributes":{"name":"Rock"}}]"#.utf8));return}
      #endif
      let values=try await AppleDiscoveryService.genres();try Task.checkCancellation();genres=values
    } catch {if !Task.isCancelled {self.error=error.localizedDescription}}
  }
}
struct AppleChartsScreen:View {
  let genre:Genre?
  @EnvironmentObject var music:MusicLibraryModel
  @State private var shelves:[AppleShelf]=[]
  @State private var busy=false
  @State private var error:String?
  var body:some View {
    ScrollView {
      LazyVStack(alignment:.leading,spacing:28) {
        Text("Classifiche Apple Music del paese del tuo account.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,20)
        if let genre {NavigationLink("Playlist: "+genre.name){CatalogSearchScreen(initialQuery:genre.name,initialCategory:.playlists)}.padding(.horizontal,20)}
        if busy {ProgressView("Caricamento classifiche…").frame(maxWidth:.infinity)}
        if let error {Text(error).foregroundStyle(.orange);Button("Riprova"){Task{await load()}}}
        AppleDiscoveryShelves(shelves:shelves)
        if shelves.isEmpty && !busy && error==nil {ContentUnavailableView("Nessuna classifica disponibile",systemImage:"chart.bar")}
      }.padding(.vertical,16)
    }.navigationTitle(genre?.name ?? "Classifiche").task(id:genre?.id){await load()}.refreshable{await load()}
  }
  private func load() async {
    busy=true;error=nil;defer{busy=false}
    do {
      #if DEBUG && BROWSE_LAYOUT_FIXTURE
      if music.isPlayerFixture {shelves=[.init(id:"fixture-chart",title:"Brani più ascoltati",items:music.songs.map(MusicBrowseItem.song)),.init(id:"fixture-albums",title:"Album più ascoltati",items:music.albums.map(MusicBrowseItem.album))];return}
      #endif
      let values=try await AppleDiscoveryService.charts(genre);try Task.checkCancellation();shelves=values
    } catch {if !Task.isCancelled {self.error=error.localizedDescription}}
  }
}
struct AppleMoodScreen:View {
  let mood:MusicMood
  @EnvironmentObject var music:MusicLibraryModel
  var body:some View {VStack {
    Text("Playlist trovate nel catalogo Apple Music per questo stato d’animo.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
    AppleShelfScreen(shelf:.init(id:"mood:"+mood.id,title:mood.title,items:music.isPlayerFixture ? music.playlists.map(MusicBrowseItem.playlist):[],load:{try await AppleDiscoveryService.mood(mood)}))
  }.navigationTitle(mood.title)}
}
struct ArtistReleasesScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  @StateObject private var releases=ArtistReleaseStore()
  private var artists:[Artist] {BrowseHistory.merging(music.favoriteArtists,music.artists)}
  var body:some View {
    VStack {
      Text("Ultimo album o singolo dei tuoi artisti in libreria e preferiti, pubblicato negli ultimi 90 giorni.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
      Text("\(releases.checked) di \(releases.total) artisti verificati").font(.caption)
      if releases.busy || music.loadingFavorites {ProgressView("Verifica nuove uscite…")}
      if let failure=music.favoritesFailure {Text(failure).foregroundStyle(.orange).font(.caption).padding(.horizontal)}
      if !releases.failures.isEmpty {Text("\(releases.failures.count) artisti non verificati.").foregroundStyle(.orange);Button("Riprova artisti non verificati"){Task{await releases.retry()}}.disabled(releases.busy)}
      MusicCollectionBrowser(items:releases.albums.map(MusicBrowseItem.album),key:"artist-releases")
      if releases.hasMore {Button("Verifica altri artisti"){Task{await releases.more()}}.disabled(releases.busy || music.isPlayerFixture)}
      if releases.albums.isEmpty && !releases.busy && !music.loadingFavorites && (artists.isEmpty || releases.checked>0) {Text(artists.isEmpty ? "Aggiungi artisti o musica alla tua libreria Apple Music.":"Nessuna nuova uscita trovata fra gli artisti verificati.").foregroundStyle(.secondary).padding()}
    }.navigationTitle("Nuove uscite").task{await refresh()}
      .toolbar{Button("Aggiorna",systemImage:"arrow.clockwise"){Task{await refresh()}}.disabled(releases.busy)}
  }
  private func refresh() async {
    if !music.isPlayerFixture {await music.refreshFavorites()}
    releases.reset(artists)
    #if DEBUG && BROWSE_LAYOUT_FIXTURE
    if music.isPlayerFixture {return}
    #endif
    await releases.more()
  }
}

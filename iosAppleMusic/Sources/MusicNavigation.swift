import SwiftUI
@preconcurrency import MusicKit

enum MusicBrowseItem:Identifiable {
  case song(Song),album(Album),playlist(Playlist),artist(Artist)
  var id:String {switch self {case .song(let v):"s:"+v.id.rawValue;case .album(let v):"a:"+v.id.rawValue;case .playlist(let v):"p:"+v.id.rawValue;case .artist(let v):"r:"+v.id.rawValue}}
  var title:String {switch self {case .song(let v):v.title;case .album(let v):v.title;case .playlist(let v):v.name;case .artist(let v):v.name}}
  var subtitle:String {switch self {case .song(let v):v.artistName;case .album(let v):v.artistName;case .playlist(let v):v.curatorName ?? "Playlist";case .artist:"Artista"}}
  var artwork:Artwork? {switch self {case .song(let v):v.artwork;case .album(let v):v.artwork;case .playlist(let v):v.artwork;case .artist(let v):v.artwork}}
}
struct MusicCollectionBrowser:View {
  let items:[MusicBrowseItem]
  let preferenceKey:String
  @State private var preferences:BrowsePreferences
  @Environment(\.dynamicTypeSize) private var typeSize
  init(items:[MusicBrowseItem],key:String) {self.items=items;preferenceKey=key;_preferences=State(initialValue:BrowsePreferences.load(key))}
  private var ordered:[MusicBrowseItem] {preferences.sorted(items,title:{$0.title},artist:{$0.subtitle})}
  private var letters:[(String,String)] {
    var seen=Set<String>();return ordered.compactMap {item in
      let letter=preferences.letter(title:item.title,artist:item.subtitle)
      return seen.insert(letter).inserted ? (letter,item.id):nil
    }
  }
  var body:some View {
    ScrollViewReader {proxy in
      VStack(spacing:8) {
        HStack {
          Text(items.count == 1 ? "1 elemento":"\(items.count) elementi").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Menu {
            Picker("Visualizzazione",selection:$preferences.layout) {ForEach(BrowseLayout.allCases,id:\.self){Text($0.title).tag($0)}}
            Picker("Ordina per",selection:$preferences.order) {ForEach(BrowseOrder.allCases,id:\.self){Text($0.title).tag($0)}}
            if preferences.order != .original {Toggle("Ordine inverso",isOn:$preferences.descending);Toggle("Indice alfabetico",isOn:$preferences.alphabet)}
          } label:{Label("Visualizzazione e ordine",systemImage:"slider.horizontal.3")}
        }.padding(.horizontal)
        if preferences.alphabet && preferences.order != .original {
          ScrollView(.horizontal,showsIndicators:false) {HStack {ForEach(letters,id:\.0){value in
            Button(value.0){withAnimation{proxy.scrollTo(value.1,anchor:.top)}}.frame(minWidth:44,minHeight:44)
          }}.padding(.horizontal)}
        }
        ScrollView {
          if preferences.layout == .grid {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:typeSize.isAccessibilitySize ? 260:150),spacing:16)],spacing:24) {
              cells(grid:true)
            }.padding()
          } else {LazyVStack(spacing:12){cells(grid:false)}.padding()}
        }
      }
    }.onChange(of:preferences){_,value in value.save(preferenceKey)}
  }
  @ViewBuilder private func cells(grid:Bool)->some View {
    ForEach(ordered){item in MusicBrowseCell(item:item,queue:ordered.compactMap{if case .song(let song)=$0{return song};return nil},grid:grid).id(item.id)}
  }
}
struct MusicBrowseCell:View {
  @EnvironmentObject var music:MusicLibraryModel
  let item:MusicBrowseItem
  let queue:[Song]
  let grid:Bool
  var body:some View {
    Group {
      switch item {
      case .song(let song):
        Button {Task{await music.play(song,in:queue)}} label:{tile}
          .contextMenu {SongNavigationActions(song:song)}
      case .album(let album):NavigationLink{CollectionScreen(album:album)} label:{tile}
      case .playlist(let playlist):NavigationLink{CollectionScreen(playlist:playlist)} label:{tile}
      case .artist(let artist):NavigationLink{ArtistScreen(artist:artist)} label:{tile}
      }
    }.buttonStyle(.plain)
  }
  private var tile:some View {
    Group {
      if grid {
        VStack(alignment:.leading,spacing:6) {
          Cover(artwork:item.artwork).aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:14))
          Text(item.title).font(.headline).lineLimit(2)
          Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
      } else {HStack {CoverRow(artwork:item.artwork,title:item.title,subtitle:item.subtitle);Spacer();Image(systemName:"chevron.right").foregroundStyle(.secondary)}.contentShape(Rectangle())}
    }.foregroundStyle(.primary)
  }
}
struct SongNavigationActions:View {
  @EnvironmentObject var music:MusicLibraryModel
  let song:Song
  @State private var addPlaylist=false
  var body:some View {
    Button("Aggiungi a playlist",systemImage:"text.badge.plus"){addPlaylist=true}
      .sheet(isPresented:$addPlaylist){AppleAddToPlaylistSheet(songs:[song])}
    NavigationLink {SongRelationshipsScreen(song:song,kind:.albums)} label:{Label("Vai all’album",systemImage:"square.stack")}
    NavigationLink {SongRelationshipsScreen(song:song,kind:.artists)} label:{Label("Vai all’artista",systemImage:"person")}
    Button("Riproduci dopo",systemImage:"text.line.first.and.arrowtriangle.forward"){Task{await music.enqueue(song,next:true)}}
    Button("Aggiungi alla coda",systemImage:"text.append"){Task{await music.enqueue(song,next:false)}}
    Button("Aggiungi alla libreria",systemImage:"plus"){Task{await music.add(song)}}
    Button("Aggiungi ai Preferiti Apple Music",systemImage:"star"){Task{await music.requestFavorite(type:"songs",id:song.id.rawValue)}}.disabled(music.sendingFavorite)
    if let url=song.url {ShareLink(item:url)}
  }
}
struct SongRelationshipsScreen:View {
  let song:Song
  let kind:BrowseKind
  @State private var albums:[Album]=[]
  @State private var artists:[Artist]=[]
  @State private var busy=true
  @State private var failure:String?
  var body:some View {
    List {
      if busy {ProgressView("Caricamento…")}
      if let failure {Text(failure).foregroundStyle(.orange);Button("Riprova"){Task{await load()}}}
      AlbumRows(albums:albums);ArtistRows(artists:artists)
      if !busy && failure == nil && albums.isEmpty && artists.isEmpty {
        Text("Apple Music non restituisce questo collegamento per il brano.").foregroundStyle(.secondary)
        if let url=song.url {Link("Apri in Musica",destination:url)}
      }
    }.navigationTitle(kind == .albums ? "Album":"Artisti").task{await load()}
  }
  private func load() async {
    busy=true;failure=nil;defer{busy=false}
    do {
      if kind == .albums {let value=try await song.with([.albums]);albums=try await all(value.albums ?? [])}
      else {let value=try await song.with([.artists]);artists=try await all(value.artists ?? [])}
    } catch {if !Task.isCancelled {failure=error.localizedDescription}}
  }
  private func all<T:MusicItem & Decodable>(_ initial:MusicItemCollection<T>) async throws -> [T] {
    var values=Array(initial),page=initial
    while page.hasNextBatch {try Task.checkCancellation();guard let next=try await page.nextBatch(limit:100) else{break};values.append(contentsOf:next);page=next}
    return values
  }
}
struct LibraryBrowserScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  @StateObject private var search=MusicSearchStore(personal:true)
  @AppStorage("library.selectedCategory") private var category=BrowseKind.albums
  @State private var searchAll=true
  @State private var createPlaylist=false
  var body:some View {
    VStack(spacing:12) {
      ScrollView(.horizontal,showsIndicators:false) {HStack {
        if !search.query.isEmpty {Button("Tutti"){searchAll=true}.buttonStyle(.bordered).tint(searchAll ? .cyan:.gray)}
        ForEach(BrowseKind.allCases){kind in Button(kind.title){category=kind;searchAll=false}.buttonStyle(.bordered).tint(category==kind && (search.query.isEmpty || !searchAll) ? .cyan:.gray)}
        NavigationLink {FavoriteLibraryScreen()} label:{Label("Preferiti",systemImage:"star")}.buttonStyle(.bordered)
      }.padding(.horizontal)}
      if search.query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
        if music.loading {ProgressView("Aggiornamento libreria…")}
        if music.remainingAlbumLookups>0 {Text("Altri \(music.remainingAlbumLookups) album da verificare. Aggiorna per continuare.").font(.caption)}
        MusicCollectionBrowser(items:items,key:"library."+category.rawValue).id(category)
        if items.isEmpty && !music.loading {Text("Nessun elemento restituito nella categoria \(category.title.lowercased()).").foregroundStyle(.secondary).padding()}
      } else {
        if searchAll {
          ScrollView {VStack(alignment:.leading,spacing:24) {
            ForEach(BrowseKind.allCases){kind in
              Text(kind.title).font(.title2.bold()).padding(.horizontal)
              PersonalResults(search:search,kind:kind,preview:true)
              Button("Mostra tutti: "+kind.title){category=kind;searchAll=false}.padding(.horizontal)
            }
          }.padding(.vertical)}
        } else {PersonalResults(search:search,kind:category)}
      }
    }.navigationTitle("Libreria")
      .sheet(isPresented:$createPlaylist){AppleCreatePlaylistSheet()}
      .toolbar {if category == .playlists {Button("Nuova playlist",systemImage:"plus"){createPlaylist=true}};NavigationLink {ReceivedMusicScreen()} label:{Label("Ricevuti",systemImage:"tray.and.arrow.down")};Button {Task{await music.refresh()}} label:{Label("Aggiorna libreria",systemImage:"arrow.clockwise")}.disabled(music.loading)}
      .searchable(text:$search.query,prompt:"Cerca nella tua libreria")
      .onChange(of:search.query){old,value in if old.isEmpty && !value.isEmpty {searchAll=true};if value.trimmingCharacters(in:.whitespacesAndNewlines) != search.submitted {search.invalidate()}}
      .task(id:search.query) {
        let term=search.query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !term.isEmpty,term != search.submitted else{return}
        do {try await Task.sleep(for:.milliseconds(400));try Task.checkCancellation();search.submit()} catch {}
      }
      .onReceive(search.albums.$items){values in if !search.submitted.isEmpty {music.rememberLibraryAlbums(values)}}
  }
  private var items:[MusicBrowseItem] {
    switch category {case .songs:music.songs.map(MusicBrowseItem.song);case .albums:music.albums.map(MusicBrowseItem.album);case .artists:music.artists.map(MusicBrowseItem.artist);case .playlists:music.playlists.map(MusicBrowseItem.playlist)}
  }
}
struct PersonalResults:View {
  @EnvironmentObject var music:MusicLibraryModel
  @ObservedObject var search:MusicSearchStore
  let kind:BrowseKind
  var preview=false
  var body:some View {
    Group {
      switch kind {
      case .songs:SearchResultGroup(page:search.songs,kind:kind,all:preview,key:"personal",local:music.songs.filter{BrowseHistory.matches(search.query,title:$0.title,artist:$0.artistName)},convert:MusicBrowseItem.song,retry:{search.retry(kind)})
      case .albums:SearchResultGroup(page:search.albums,kind:kind,all:preview,key:"personal",local:music.albums.filter{BrowseHistory.matches(search.query,title:$0.title,artist:$0.artistName)},convert:MusicBrowseItem.album,retry:{search.retry(kind)})
      case .playlists:SearchResultGroup(page:search.playlists,kind:kind,all:preview,key:"personal",local:music.playlists.filter{BrowseHistory.matches(search.query,title:$0.name,artist:$0.curatorName ?? "")},convert:MusicBrowseItem.playlist,retry:{search.retry(kind)})
      case .artists:SearchResultGroup(page:search.artists,kind:kind,all:preview,key:"personal",local:music.artists.filter{BrowseHistory.matches(search.query,title:$0.name,artist:"")},convert:MusicBrowseItem.artist,retry:{search.retry(kind)})
      }
    }
  }
}
struct CatalogSearchScreen:View {
  @StateObject private var search:MusicSearchStore
  private let initialQuery:String
  init(initialQuery:String="") {self.initialQuery=initialQuery;_search=StateObject(wrappedValue:MusicSearchStore(personal:false))}
  var body:some View {
    VStack {
      ScrollView(.horizontal,showsIndicators:false){HStack {
        Button("Tutti"){search.category=nil}.buttonStyle(.bordered).tint(search.category == nil ? .cyan:.gray)
        ForEach(BrowseKind.allCases){kind in Button(kind.title){search.category=kind}.buttonStyle(.bordered).tint(search.category==kind ? .cyan:.gray)}
      }.padding(.horizontal)}
      if search.submitted.isEmpty {
        List {
          if search.history.isEmpty {Text("Cerca brani, album, artisti e playlist nel catalogo Apple Music.").foregroundStyle(.secondary)}
          ForEach(search.history,id:\.self){term in Button(term){search.submit(term)}}
          if !search.history.isEmpty {Button("Cancella cronologia",role:.destructive){search.clearHistory()}}
        }
      } else if let kind=search.category {
        result(kind,all:false)
      } else {
        ScrollView {VStack(alignment:.leading,spacing:24) {
          ForEach(BrowseKind.allCases){kind in
            VStack(alignment:.leading) {
              Text(kind.title).font(.title2.bold()).padding(.horizontal)
              result(kind,all:true).frame(minHeight:140)
              Button("Mostra tutti: "+kind.title){search.category=kind}.padding(.horizontal)
            }
          }
        }.padding(.vertical)}
      }
    }.navigationTitle("Cerca")
      .task {if !initialQuery.isEmpty && search.submitted.isEmpty {search.submit(initialQuery)}}
      .searchable(text:$search.query,prompt:"Brani, album, artisti e playlist")
      .onSubmit(of:.search){search.submit()}
      .onChange(of:search.query){_,value in if value.trimmingCharacters(in:.whitespacesAndNewlines) != search.submitted {search.invalidate()}}
  }
  @ViewBuilder private func result(_ kind:BrowseKind,all:Bool)->some View {
    switch kind {
    case .songs:SearchResultGroup(page:search.songs,kind:kind,all:all,key:"catalog",convert:MusicBrowseItem.song,retry:{search.retry(kind)})
    case .albums:SearchResultGroup(page:search.albums,kind:kind,all:all,key:"catalog",convert:MusicBrowseItem.album,retry:{search.retry(kind)})
    case .playlists:SearchResultGroup(page:search.playlists,kind:kind,all:all,key:"catalog",convert:MusicBrowseItem.playlist,retry:{search.retry(kind)})
    case .artists:SearchResultGroup(page:search.artists,kind:kind,all:all,key:"catalog",convert:MusicBrowseItem.artist,retry:{search.retry(kind)})
    }
  }
}
struct SearchResultGroup<Item:Identifiable & Sendable>:View where Item.ID:Hashable {
  @ObservedObject var page:BrowsePage<Item>
  let kind:BrowseKind
  let all:Bool
  let key:String
  var local:[Item]=[]
  let convert:(Item)->MusicBrowseItem
  let retry:()->Void
  private var values:[Item] {BrowseHistory.merging(page.items,local)}
  var body:some View {
    VStack(alignment:.leading,spacing:10) {
      if page.busy {ProgressView("Ricerca \(kind.title.lowercased())…").padding(.horizontal)}
      if let error=page.error {Text(error).foregroundStyle(.orange);Button("Riprova",action:retry)}
      if let warning=page.warning {Text(warning).font(.caption).foregroundStyle(.secondary);Button("Completa ricerca",action:retry)}
      if all {
        VStack {ForEach(Array(values.prefix(6))){item in MusicBrowseCell(item:convert(item),queue:values.compactMap{if case .song(let song)=convert($0){return song};return nil},grid:false)}}.padding(.horizontal)
      } else {
        MusicCollectionBrowser(items:values.map(convert),key:key+"."+kind.rawValue)
        if page.moreBusy {ProgressView("Altri risultati…")}
        if let error=page.moreError {Text(error).foregroundStyle(.orange)}
        if page.hasMore {Button(page.moreError == nil ? "Altri risultati":"Riprova altri risultati"){Task{await page.more()}}.disabled(page.moreBusy)}
      }
      if !page.busy && page.error == nil && values.isEmpty {Text("Nessun risultato in \(kind.title.lowercased()).").foregroundStyle(.secondary).padding(.horizontal)}
    }
  }
}

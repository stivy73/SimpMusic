// Adapted from SharedMusicScreen.swift and SharedCatalogScreen.swift at 5a277798.
// The typed inbox, source-position rows, candidate selection and retry flow are retained.
import SwiftUI
@preconcurrency import MusicKit

enum AppleSharedCatalog {
  static func search(_ query:String) async throws -> [SharedMatchCandidate] {
    var request=MusicCatalogSearchRequest(term:query,types:[Song.self]);request.limit=25
    let search=request
    let result=try await MusicRead.perform{try await search.response()}
    return result.songs.map{.init(mediaId:$0.id.rawValue,title:$0.title,subtitle:$0.artistName,artwork:$0.artwork?.url(width:300,height:300),durationSeconds:$0.duration)}
  }
  static func songs(_ candidates:[SharedMatchCandidate]) async throws -> [Song] {
    let ids=candidates.map{MusicItemID($0.mediaId)};var found:[MusicItemID:Song]=[:]
    for offset in stride(from:0,to:ids.count,by:100) {
      let batch=Array(Set(ids.dropFirst(offset).prefix(100)))
      let request=MusicCatalogResourceRequest<Song>(matching:\.id,memberOf:batch)
      let response=try await MusicRead.perform{try await request.response()}
      for song in response.items {found[song.id]=song}
    }
    return try ids.map{guard let song=found[$0],song.playParameters != nil else{throw SharedCatalogError.unavailable};return song}
  }
  static func expanded(_ input:SharedCatalogLink) async throws -> SharedCatalogLink {
    guard input.valid else{throw SharedCatalogError.malformed}
    if input.kind != .shortLink {return input}
    let response=try await SharedCatalogHTTP.fetch(input.url,provider:input.provider)
    guard let link=SharedCatalogLink.parse(response.url),link.provider==input.provider,link.kind != .shortLink else{throw SharedCatalogError.unavailable}
    return link
  }
}
struct ReceiveMusicShares:ViewModifier {
  @Environment(\.scenePhase) private var phase
  @State private var request:SharedMusicRequest?
  @State private var opened=Set<UUID>()
  func body(content:Content)->some View {
    content.task{check()}.onChange(of:phase){_,value in if value == .active {check()}}
      .onOpenURL{url in
        guard let link=SharedCatalogLink.parse(url),let inbox=SharedMusicInbox.shared() else{return}
        let value=SharedMusicRequest(target:.catalog(link));do{try inbox.save(value);request=value;opened.insert(value.id)}catch{}
      }
      .sheet(item:$request){value in NavigationStack{ReceivedRequestScreen(request:value).toolbar{Button("Chiudi"){request=nil}}}}
  }
  private func check() {
    guard request==nil,let value=SharedMusicInbox.shared()?.pending().first(where:{!opened.contains($0.id)}) else{return}
    opened.insert(value.id);request=value
  }
}
struct ReceivedMusicScreen:View {
  @Environment(\.scenePhase) private var phase
  @State private var pending:[SharedMusicRequest]=[]
  var body:some View {
    Group {
      if pending.isEmpty {
        ContentUnavailableView("Nessun contenuto ricevuto",systemImage:"square.and.arrow.down",description:Text("Usa Condividi → NoteNarrate Music per brani, album e playlist di Apple Music o Spotify."))
      } else {
        List(pending){request in
          NavigationLink{ReceivedRequestScreen(request:request)} label:{Label(request.target.label,systemImage:"music.note")}
            .swipeActions{Button("Elimina",role:.destructive){try? SharedMusicInbox.shared()?.remove(request.id);reload()}}
        }
      }
    }.navigationTitle("Ricevuti").onAppear{reload()}.onChange(of:phase){_,value in if value == .active {reload()}}
  }
  private func reload(){pending=SharedMusicInbox.shared()?.pending() ?? []}
}
struct ReceivedRequestScreen:View {
  let request:SharedMusicRequest
  @State private var query=""
  var body:some View {
    Group {
      if case .catalog(let link)=request.target {
        if link.provider == .appleMusic {NativeSharedMusicScreen(request:request,link:link)}
        else {AppleImportedCatalogScreen(request:request,link:link)}
      } else {
        Form {
          Text("Cerca il contenuto ricevuto nel catalogo Apple Music.")
          TextField("Titolo e artista",text:$query)
          NavigationLink("Cerca su Apple Music"){CatalogSearchScreen(initialQuery:query)}.disabled(SharedMusicTarget.queryText(query)==nil)
        }.navigationTitle("Contenuto condiviso").onAppear{if case .search(let value)=request.target {query=value}}
      }
    }
  }
}
struct NativeSharedMusicScreen:View {
  @EnvironmentObject var music:MusicLibraryModel
  let request:SharedMusicRequest
  let link:SharedCatalogLink
  @State private var collection:AppleCollection?
  @State private var song:Song?
  @State private var busy=true
  @State private var error:String?
  @State private var addPlaylist=false
  @State private var retry=0
  var body:some View {
    Group {
      if let collection {AppleCollectionScreen(collection:collection)}
      else if let song {
        List {
          CoverRow(artwork:song.artwork,title:song.title,subtitle:song.artistName)
          Button("Riproduci",systemImage:"play.fill"){Task{await music.play(song,in:[song]);if music.playing {consume()}}}
          Button("Aggiungi alla coda",systemImage:"text.append"){Task{await music.enqueue(song,next:false)}}
          Button("Aggiungi a playlist",systemImage:"text.badge.plus"){addPlaylist=true}
          NavigationLink("Album e artista"){SongRelationshipsScreen(song:song,kind:.albums)}
          Link("Apri in Musica",destination:song.url ?? link.url)
        }.navigationTitle("Brano condiviso").sheet(isPresented:$addPlaylist){AppleAddToPlaylistSheet(songs:[song])}
      } else {
        Form {
          if busy {ProgressView("Recupero il contenuto Apple Music…")}
          if let error {Text(error).foregroundStyle(.orange);Button("Riprova"){retry+=1};Link("Apri in Musica",destination:link.url)}
        }.navigationTitle("Apple Music")
      }
    }.task(id:retry){await load()}
  }
  private func consume(){try? SharedMusicInbox.shared()?.remove(request.id)}
  private func load() async {
    busy=true;error=nil;defer{busy=false}
    do {
      let canonical=try await AppleSharedCatalog.expanded(link)
      switch canonical.kind {
      case .track:
        let value=MusicCatalogResourceRequest<Song>(matching:\.id,equalTo:MusicItemID(canonical.id))
        song=try await MusicRead.perform{try await value.response()}.items.first
        guard song != nil else{throw SharedCatalogError.unavailable}
      case .album:
        let value=MusicCatalogResourceRequest<Album>(matching:\.id,equalTo:MusicItemID(canonical.id))
        guard let album=try await MusicRead.perform({try await value.response()}).items.first else{throw SharedCatalogError.unavailable}
        collection = .album(album)
      case .playlist:
        // First resolve a private playlist already owned by this account by its exact share ID.
        if let own=music.playlists.first(where:{$0.url.flatMap(SharedCatalogLink.parse)?.id==canonical.id}) {collection = .playlist(own);return}
        var library=MusicLibraryRequest<Playlist>();library.limit=100
        let personalRequest=library
        if let first=try? await MusicRead.perform({try await personalRequest.response()}) {
          let personal=try await MusicRead.all(first.items)
          if let own=personal.first(where:{$0.url.flatMap(SharedCatalogLink.parse)?.id==canonical.id}) {collection = .playlist(own);return}
        }
        let value=MusicCatalogResourceRequest<Playlist>(matching:\.id,equalTo:MusicItemID(canonical.id))
        guard let playlist=try await MusicRead.perform({try await value.response()}).items.first else{throw SharedCatalogError.unavailable}
        collection = .playlist(playlist)
      case .shortLink:throw SharedCatalogError.unavailable
      }
      try Task.checkCancellation()
    } catch {if !Task.isCancelled {self.error=error.localizedDescription}}
  }
}
struct AppleImportedCatalogScreen:View {
  let request:SharedMusicRequest
  let link:SharedCatalogLink
  @EnvironmentObject private var music:MusicLibraryModel
  @EnvironmentObject private var playlists:ApplePlaylistService
  @StateObject private var importer=SharedCatalogImport(search:AppleSharedCatalog.search)
  @State private var task:Task<Void,Never>?
  @State private var selecting:Int?
  @State private var candidateQuery=""
  @State private var saving=false
  @State private var saveError:String?
  @State private var createdPlaylist:Playlist?
  var body:some View {
    List {
      if let collection=importer.collection {
        Section {
          YTPlayerArtwork(url:collection.artwork).frame(width:156,height:156).clipShape(RoundedRectangle(cornerRadius:16))
          Text(collection.title).font(.title2.bold());Text(collection.subtitle).foregroundStyle(.secondary)
          Link("Apri su "+collection.link.provider.title,destination:collection.link.url)
          Text("\(collection.tracks.count) tracce ricevute · \(importer.matches.count) trovate su Apple Music")
          if let warning=collection.warning {Text(warning).foregroundStyle(.orange)}
          if importer.busy {ProgressView("Verifico \(importer.completed) di \(collection.tracks.count)…");Button("Interrompi ricerca"){task?.cancel()}}
          else {Button(importer.matches.isEmpty ? "Trova i brani su Apple Music":"Riprova i brani mancanti"){task=Task{await importer.resolve()}}.disabled(importer.matches.count==collection.tracks.count)}
          if !importer.orderedMatches.isEmpty {
            Button("Riproduci \(importer.matches.count) brani trovati",systemImage:"play.fill"){perform(.play)}
            Button("Aggiungi \(importer.matches.count) brani alla coda",systemImage:"text.append"){perform(.enqueue)}
            if let createdPlaylist {Label("Playlist creata in Apple Music",systemImage:"checkmark.circle.fill");NavigationLink("Apri la playlist"){CollectionScreen(playlist:createdPlaylist)}}
            else {Button("Crea playlist con \(importer.matches.count) brani trovati",systemImage:"music.note.list"){perform(.save)}}
          }
          if saving {ProgressView("Preparazione…")}
          if let saveError {Text(saveError).foregroundStyle(.orange)}
        }
        Section("Tracce nell’ordine originale") {
          ForEach(Array(collection.tracks.enumerated()),id:\.offset){index,track in
            VStack(alignment:.leading,spacing:6) {
              HStack(alignment:.top){Text("\(index+1)").monospacedDigit().foregroundStyle(.secondary);VStack(alignment:.leading){Text(track.title).font(.headline);Text(track.artist).font(.subheadline).foregroundStyle(.secondary)};Spacer();if importer.matches[index] != nil {Image(systemName:"checkmark.circle.fill").foregroundStyle(.cyan)}}
              if let failure=importer.failures[index] {Text(failure).font(.caption).foregroundStyle(.orange)}
              if let selected=importer.matches[index] {Text("Apple Music: \(selected.title) · \(selected.subtitle)").font(.caption).foregroundStyle(.secondary)}
              if importer.candidates[index] != nil || importer.failures[index] != nil {Button("Scegli versione"){candidateQuery=track.query;selecting=index}.disabled(importer.busy || saving)}
            }
          }
        }
      } else if importer.busy {ProgressView("Recupero copertina e tracce…")}
      if let error=importer.error {Text(error).foregroundStyle(.orange);Link("Apri su "+link.provider.title,destination:link.url);Button("Riprova"){task=Task{await importer.load(link)}}}
    }.disabled(saving).navigationTitle(link.kind == .playlist ? "Playlist condivisa":link.kind.title+" condiviso")
      .task(id:link){await importer.load(link)}.onDisappear{task?.cancel()}
      .sheet(isPresented:Binding(get:{selecting != nil},set:{if !$0 {selecting=nil}})) {
        NavigationStack {
          List {
            TextField("Titolo e artista",text:$candidateQuery)
            Button("Cerca versione"){if let index=selecting {task=Task{await importer.searchCandidates(at:index,query:candidateQuery)}}}.disabled(importer.busy)
            if importer.busy {ProgressView("Ricerca…")}
            if let index=selecting {ForEach(importer.candidates[index] ?? []){item in
              Button{importer.choose(item,at:index);selecting=nil} label:{VStack(alignment:.leading){Text(item.title);Text(item.subtitle).font(.caption).foregroundStyle(.secondary)}}.disabled(importer.busy)
            }}
          }.navigationTitle("Conferma il brano").toolbar{Button("Chiudi"){task?.cancel();selecting=nil}}
        }
      }
  }
  private enum Action {case play,enqueue,save}
  private func perform(_ action:Action) {
    guard !saving,!importer.busy,let collection=importer.collection else{return}
    let chosen=importer.orderedMatches;saving=true;saveError=nil
    task=Task {
      defer{saving=false}
      do {
        let songs=try await AppleSharedCatalog.songs(chosen);try Task.checkCancellation()
        switch action {
        case .play:if let first=songs.first {await music.play(first,in:songs)}
        case .enqueue:try await music.player.queue.insert(songs,position:.tail)
        case .save:
          let value=try await playlists.create(name:collection.title,songs:songs);createdPlaylist=value
          music.playlists=BrowseHistory.merging([value],music.playlists)
        }
        if action != .play || music.playing {try? SharedMusicInbox.shared()?.remove(request.id)}
      } catch {saveError=error.localizedDescription}
    }
  }
}

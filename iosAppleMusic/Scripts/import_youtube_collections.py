"""Reproducible service adaptations of the original collection/share code."""
from pathlib import Path
import subprocess, hashlib, sys
root=Path(__file__).resolve().parents[2]
revision='5a277798'
outputs={}
def source(path):
    value=subprocess.check_output(['git','show',f'{revision}:{path}'],cwd=root).decode()
    return value, f'// Adapted from {path} at {revision}. SHA256 {hashlib.sha256(value.encode()).hexdigest()}\n// Reproduce with Scripts/import_youtube_collections.py.\n'

s,h=source('iosPrototype/Sources/Core/SharedMusic.swift')
outputs['Sources/SharedMusic.swift']=h+s.replace('group.com.stivy.simpmusic.prototype','group.com.stivy.notenarrate.applemusic')
s,h=source('iosPrototype/Sources/Core/SharedCatalog.swift')
s=s.replace('DiscoveryItem','SharedMatchCandidate').replace('MusicSuggestion.normalize','SharedMatchKey.normalize')
s=s.replace('(YouTubeSession?, String)', '(String)')
s=s.replace('search: @escaping Search = {\n      try await HomeDiscovery(session: $0).search(query: $1, filter: .songs)\n    }','search: @escaping Search')
s=s.replace('resolve(session: YouTubeSession?)','resolve()').replace('search(session, track.query)','search(track.query)')
s=s.replace('query: String, session: YouTubeSession?','query: String').replace('search(session, query)','search(query)')
s=s.replace('su YouTube Music','su Apple Music')
outputs['Sources/SharedCatalog.swift']=h+s
s,h=source('iosPrototype/ShareExtension/ShareViewController.swift')
s=s.replace('Ricevi brani, album e playlist da Apple Music, Spotify e YouTube Music. Le tracce verranno cercate su YouTube Music nell’app.','Ricevi brani, album e playlist da Apple Music e Spotify. La riproduzione avviene con Apple Music nell’app.')
s=s.replace('NoteNarrate','NoteNarrate Music')
outputs['ShareExtension/ShareViewController.swift']=h+s
s,h=source('iosPrototype/Tests/SharedCatalogTests.swift')
s=s.replace('@testable import PrototypeCore','@testable import LyricsContract').replace('DiscoveryItem','SharedMatchCandidate')
s=s.replace('search: { _, query in','search: { query in').replace('search: { _, _ in','search: { _ in')
s=s.replace('.resolve(session: nil)','.resolve()').replace(', session: nil)',')')
outputs['Tests/SharedCatalogTests.swift']=h+s

s,h=source('iosPrototype/Sources/App/AlbumScreen.swift')
s=s[:s.index('\nprivate struct AlbumDownloadControl:')]
start=s.index('struct AlbumView: View {');body=s.index('  var body: some View {')
s=s[:start]+'''struct AppleCollectionScreen: View {
  let collection:AppleCollection
  @EnvironmentObject private var music:MusicLibraryModel
  @Environment(\\.dynamicTypeSize) private var typeSize
  @State private var detail:AppleCollectionDetail?
  @State private var loading=true
  @State private var error:String?
  @State private var retry=0
  @State private var optionsSong:AppleCollectionRow?
  @State private var addToPlaylist=false
  @State private var showEditor=false
  private var shown:CollectionIdentity {detail?.identity ?? collection.identity}
  private var songs:[AppleCollectionRow] {detail?.songs ?? []}
  private var currentCollection:Bool {
    music.activeCollectionID==collection.id && (music.activeCollectionRowID != nil || songs.contains{$0.mediaID==music.nowPlaying?.id.rawValue})
  }
  private var playingAlbum:Bool {currentCollection && music.playing}
  var body: some View {
'''+s[body+len('  var body: some View {\n'):]
s=s.replace('Artwork(url:','YTPlayerArtwork(url:')
s=s.replace('model.play(song, queue: songs, selectedIndex: index)','Task {await music.playCollection(collection,row:song,shuffle:false)}')
s=s.replace('model.current?.id == song.id','isCurrent(song)')
s=s.replace('}.buttonStyle(.plain).accessibilityIdentifier("album-track-\\(index)")','}.buttonStyle(.plain).disabled(!song.playable).accessibilityIdentifier("album-track-\\(index)")')
a=s.index('    }.navigationTitle(shown.title)');b=s.index('\n  private var identityHeader:',a)
s=s[:a]+'''    }.navigationTitle(shown.title).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement:.topBarTrailing) {CollectionFavoriteButton(collection:collection)}
        ToolbarItem(placement:.topBarTrailing) {
          Menu {
            Button("Riproduci dopo",systemImage:"text.line.first.and.arrowtriangle.forward"){Task{await music.enqueueCollection(collection,next:true)}}.disabled(songs.isEmpty)
            Button("Aggiungi alla coda",systemImage:"text.append"){Task{await music.enqueueCollection(collection)}}.disabled(songs.isEmpty)
            Button("Aggiungi a playlist",systemImage:"text.badge.plus"){addToPlaylist=true}.disabled(songs.isEmpty || songs.contains{$0.song==nil})
            if case .album(let album)=collection {Button("Salva album nella libreria",systemImage:"plus"){Task{await music.saveAlbum(album)}}}
            if case .playlist=collection {Button("Gestisci playlist",systemImage:"pencil"){showEditor=true}}
            if let url=shown.url {ShareLink(item:url){Label("Condividi",systemImage:"square.and.arrow.up")};Link("Apri in Musica",destination:url)}
            Button("Aggiorna",systemImage:"arrow.clockwise"){retry+=1}
          } label:{Label("Opzioni raccolta",systemImage:"ellipsis")}.accessibilityIdentifier("album-options")
        }
      }
      .task(id:"\\(collection.id):\\(retry)"){await load()}
      .sheet(item:$optionsSong){row in AppleCollectionTrackOptions(row:row)}
      .sheet(isPresented:$addToPlaylist){AppleAddToPlaylistSheet(songs:songs.compactMap(\\.song))}
      .sheet(isPresented:$showEditor,onDismiss:{retry+=1}){if case .playlist(let playlist)=collection {ApplePlaylistEditor(playlist:playlist)}}
  }
'''+s[b:]
s=s.replace('[detail?.year, "Album"]','[detail?.year, shown.kind]')
a=s.index('  private var albumControls:');b=s.index('  private var summary:',a)
s=s[:a]+'''  private var albumControls: some View {
    HStack(spacing:18) {
      Button {
        Task{await music.playCollection(collection,row:songs.filter(\\.playable).randomElement(),shuffle:true)}
      } label:{Image(systemName:"shuffle").font(.title2).frame(width:58,height:58)}
        .buttonStyle(.plain).background(.white.opacity(0.12),in:Circle())
        .accessibilityLabel("Riproduzione casuale della raccolta").accessibilityIdentifier("album-shuffle")
        .disabled(!songs.contains(where:\\.playable) || music.preparingPlayback)
      Button {
        if playingAlbum {music.pause()}
        else if currentCollection {Task{await music.resume()};music.showPlayer=true}
        else {Task{await music.playCollection(collection,row:songs.first(where:\\.playable),shuffle:false)}}
      } label:{Label(playingAlbum ? "Pausa":"Play",systemImage:playingAlbum ? "pause.fill":"play.fill")
          .font(.title3.bold()).frame(maxWidth:.infinity).frame(height:60)}
        .buttonStyle(.plain).foregroundStyle(.black).background(.white,in:Capsule())
        .accessibilityIdentifier("album-play").disabled(!songs.contains(where:\\.playable) || music.preparingPlayback)
    }.tint(.white)
  }
'''+s[b:]
a=s.index('  private func load() async {')
s=s[:a]+'''  private func isCurrent(_ row:AppleCollectionRow)->Bool {
    guard music.activeCollectionID==collection.id else{return false}
    if let selected=music.activeCollectionRowID {return selected==row.id}
    return music.nowPlaying?.id.rawValue==row.mediaID && songs.filter{$0.mediaID==row.mediaID}.count==1
  }
  private func load() async {
    loading=true;error=nil
    do {let result=try await music.collectionDetail(collection);try Task.checkCancellation();detail=result}
    catch {if !Task.isCancelled {self.error=error.localizedDescription}}
    loading=false
  }
}
'''
s=s.replace('import SwiftUI','import SwiftUI\n@preconcurrency import MusicKit')
s=s.replace('Carico l’album…','Carico la raccolta…').replace('Album non disponibile','Raccolta non disponibile')
s=s.replace('var text = \"\\(songs.count) tracce\"','var text = songs.count == 1 ? \"1 traccia\":\"\\(songs.count) tracce\"')
outputs['Sources/YouTubeCollectionPresentation.swift']=h+s

for path,value in outputs.items():
    destination=root/'iosAppleMusic'/path
    if '--check' in sys.argv:
        assert destination.read_text()==value, f'Pinned port differs: {path}'
    else:
        destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(value)
print('Pinned collection/share imports: verified' if '--check' in sys.argv else 'Imported collection/share sources')

// Adapted from iosPrototype/Sources/App/AlbumScreen.swift at 5a277798. SHA256 193445397c08276ee0163d4d607a5256569a230f12de6528d313e45beadca728
// Reproduce with Scripts/import_youtube_collections.py.
import SwiftUI
@preconcurrency import MusicKit

struct AppleCollectionScreen: View {
  let collection:AppleCollection
  @EnvironmentObject private var music:MusicLibraryModel
  @Environment(\.dynamicTypeSize) private var typeSize
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
    GeometryReader { geometry in
      let wide = geometry.size.width >= 700 && !typeSize.isAccessibilitySize
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if wide {
            HStack(alignment: .center, spacing: 28) {
              YTPlayerArtwork(url: shown.artwork, fit: true)
                .frame(
                  width: min(geometry.size.width * 0.4, 380),
                  height: min(geometry.size.width * 0.4, 380)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
              VStack(alignment: .leading, spacing: 24) {
                identityHeader
                albumControls
              }
            }.padding(.horizontal, 24).padding(.top, 12)
          } else {
            ZStack(alignment: .bottom) {
              YTPlayerArtwork(url: shown.artwork).frame(height: min(geometry.size.width * 1.08, 520))
              LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black], startPoint: .top, endPoint: .bottom)
              identityHeader.padding(24)
            }
            albumControls.padding(.horizontal, 24)
          }
          if loading {
            ProgressView("Carico la raccolta…").frame(maxWidth: .infinity).padding()
          } else if let error {
            ContentUnavailableView {
              Label("Raccolta non disponibile", systemImage: "exclamationmark.triangle")
            } description: {
              Text(error)
            } actions: {
              Button("Riprova") { retry += 1 }
            }
          } else {
            Text(detail?.description.isEmpty == false ? detail!.description : "Nessuna descrizione")
              .foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 24)
              .accessibilityIdentifier("album-description")
            Text(summary).font(.subheadline).padding(.horizontal, 24)
              .accessibilityIdentifier("album-track-summary")
            LazyVStack(spacing: 0) {
              ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                HStack(spacing: 12) {
                  Button {
                    Task {await music.playCollection(collection,row:song,shuffle:false)}
                  } label: {
                    HStack(spacing: 18) {
                      Group {
                        if isCurrent(song) {
                          Image(systemName: "waveform").foregroundStyle(.cyan)
                        } else {
                          Text("\(index + 1)").foregroundStyle(.secondary)
                        }
                      }.font(.headline).frame(width: 30)
                      VStack(alignment: .leading, spacing: 5) {
                        Text(song.title).font(.headline).foregroundStyle(.primary)
                        Text(song.artist).font(.subheadline).foregroundStyle(.secondary)
                      }.frame(maxWidth: .infinity, alignment: .leading)
                      if let duration = song.durationSeconds {
                        Text(Self.time(duration)).font(.caption).monospacedDigit().foregroundStyle(
                          .secondary)
                      }
                    }.padding(.vertical, 18).contentShape(Rectangle())
                  }.buttonStyle(.plain).disabled(!song.playable).accessibilityIdentifier("album-track-\(index)")
                  Button {
                    optionsSong = song
                  } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(
                      width: 44, height: 48)
                  }.buttonStyle(.plain).accessibilityLabel("Opzioni di \(song.title)")
                    .accessibilityIdentifier("album-track-options-\(index)")
                }.padding(.horizontal, 20)
                Divider().padding(.leading, 68)
              }
            }
          }
        }.padding(.bottom, 32).frame(maxWidth: 1100).frame(maxWidth: .infinity)
      }.background(.black).accessibilityIdentifier("album-scroll")
    }.navigationTitle(shown.title).navigationBarTitleDisplayMode(.inline)
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
      .task(id:"\(collection.id):\(retry)"){await load()}
      .sheet(item:$optionsSong){row in AppleCollectionTrackOptions(row:row)}
      .sheet(isPresented:$addToPlaylist){AppleAddToPlaylistSheet(songs:songs.compactMap(\.song))}
      .sheet(isPresented:$showEditor,onDismiss:{retry+=1}){if case .playlist(let playlist)=collection {ApplePlaylistEditor(playlist:playlist)}}
  }

  private var identityHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(shown.title).font(.largeTitle.bold()).accessibilityIdentifier("album-title")
      Text(shown.artist).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
      Text([detail?.year, shown.kind].compactMap { $0 }.joined(separator: " · "))
        .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("album-year")
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var albumControls: some View {
    HStack(spacing:18) {
      Button {
        Task{await music.playCollection(collection,row:songs.filter(\.playable).randomElement(),shuffle:true)}
      } label:{Image(systemName:"shuffle").font(.title2).frame(width:58,height:58)}
        .buttonStyle(.plain).background(.white.opacity(0.12),in:Circle())
        .accessibilityLabel("Riproduzione casuale della raccolta").accessibilityIdentifier("album-shuffle")
        .disabled(!songs.contains(where:\.playable) || music.preparingPlayback)
      Button {
        if playingAlbum {music.pause()}
        else if currentCollection {Task{await music.resume()};music.showPlayer=true}
        else {Task{await music.playCollection(collection,row:songs.first(where:\.playable),shuffle:false)}}
      } label:{Label(playingAlbum ? "Pausa":"Play",systemImage:playingAlbum ? "pause.fill":"play.fill")
          .font(.title3.bold()).frame(maxWidth:.infinity).frame(height:60)}
        .buttonStyle(.plain).foregroundStyle(.black).background(.white,in:Capsule())
        .accessibilityIdentifier("album-play").disabled(!songs.contains(where:\.playable) || music.preparingPlayback)
    }.tint(.white)
  }
  private var summary: String {
    var text = songs.count == 1 ? "1 traccia":"\(songs.count) tracce"
    if let seconds = detail?.durationSeconds { text += ", \(Int((seconds / 60).rounded())) minuti" }
    return text
  }
  private static func time(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    return "\(total / 60):" + String(format: "%02d", total % 60)
  }
  private func isCurrent(_ row:AppleCollectionRow)->Bool {
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

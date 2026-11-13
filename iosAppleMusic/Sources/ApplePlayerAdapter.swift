import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
@preconcurrency import MusicKit

struct PlayerSong:Identifiable {
  let id:String
  let title:String
  let artist:String
  let artwork:URL?
}
enum PlayerRepeatMode {
  case off,all,one
  var next:Self {switch self {case .off:.all;case .all:.one;case .one:.off}}
  var title:String {switch self {case .off:"Disattivata";case .all:"Tutti";case .one:"Uno"}}
}
@MainActor final class ApplePlayerAdapter:ObservableObject {
  let music:MusicLibraryModel
  let narration:NarrationModel
  @Published var showMeaning=false
  private var subscriptions=Set<AnyCancellable>()
  init(music:MusicLibraryModel,narration:NarrationModel) {
    self.music=music;self.narration=narration
    music.objectWillChange.sink {[weak self] _ in self?.objectWillChange.send()}.store(in:&subscriptions)
    narration.objectWillChange.sink {[weak self] _ in self?.objectWillChange.send()}.store(in:&subscriptions)
  }
  var current:PlayerSong? {music.nowPlaying.map{.init(id:$0.id.rawValue,title:$0.title,artist:$0.artistName,artwork:music.artworkURL($0))}}
  func loadCurrentArtwork() async {
    guard let song=music.nowPlaying else{return}
    music.rememberArtwork([song]);await music.artwork.load(id:song.id.rawValue)
  }
  var showPlayer:Bool {get{music.showPlayer} set{music.showPlayer=newValue}}
  var player:ApplePlayerAdapter {self}
  var isPassenger:Bool {false}
  var playing:Bool {music.playing}
  var elapsed:Double {music.position}
  var durationSeconds:Double {music.duration}
  var isLoading:Bool {music.preparingPlayback}
  var playbackError:String? {music.playbackFailure}
  var videoId:String {current?.id ?? ""}
  var reading:Bool {narration.isReading}
  var busyMeaning:Bool {narration.busy && !narration.isReading}
  var meaningPresentationOnPhone:Bool {true}
  var hasPrevious:Bool {music.player.queue.entries.first?.id != music.player.queue.currentEntry?.id}
  var hasNext:Bool {music.player.queue.entries.last?.id != music.player.queue.currentEntry?.id}
  var shuffleEnabled:Bool {music.player.state.shuffleMode == .songs}
  func setShuffle(_ value:Bool) {music.player.state.shuffleMode=value ? .songs:.off;objectWillChange.send()}
  var repeatMode:PlayerRepeatMode {
    get {switch music.player.state.repeatMode {case .one:.one;case .all:.all;default:.off}}
    set {switch newValue {case .off:music.player.state.repeatMode = MusicPlayer.RepeatMode.none;case .all:music.player.state.repeatMode = .all;case .one:music.player.state.repeatMode = .one};objectWillChange.send()}
  }
  func play() {Task{await music.resume()}}
  func pause() {music.pause()}
  func load(videoId:String) {Task{await music.resume()}}
  func seek(to time:CMTime) {if music.isPlayerFixture {music.position=max(0,min(durationSeconds,time.seconds));return};music.player.playbackTime=max(0,min(durationSeconds,time.seconds))}
  func previousSong() {if elapsed>3 {seek(to:.zero)} else {Task{await music.previous()}}}
  func nextSong() {Task{await music.next()}}
  func minimizePlayer() {showPlayer=false}
  func explain() {showMeaning=true}
  func stopMeaning() {narration.stop()}
  func loadLyrics() {} // The licensed text service is not enabled; the pane shows sources.
}
struct NativeMusicVolume:UIViewRepresentable {
  func makeUIView(context:Context)->MPVolumeView {let view=MPVolumeView();view.tintColor = .white;view.showsRouteButton=false;return view}
  func updateUIView(_ view:MPVolumeView,context:Context) {}
}
struct AppleAudioOutputButtons:View {
  var body:some View {RoutePicker().frame(width:44,height:44).accessibilityLabel("AirPlay")}
}
struct PlayerInfoContent:View {
  @EnvironmentObject var model:ApplePlayerAdapter
  var body:some View {
    ScrollView {
      VStack(alignment:.leading,spacing:22) {
        if model.narration.text.isEmpty {
          Text("Significato").font(.title2.bold())
          Text("Cerca il significato per ascoltare l’interpretazione.").foregroundStyle(.secondary)
          Button("Cerca significato",systemImage:"lightbulb") {model.explain()}
        } else {
          Text(model.narration.text).font(.title3).lineSpacing(6).textSelection(.enabled)
        }
      }.padding(24)
    }
  }
}
struct ApplePlayerOptions:View {
  @EnvironmentObject var model:ApplePlayerAdapter
  let song:PlayerSong
  let onClose:()->Void
  @State private var addPlaylist=false
  var body:some View {
    NavigationStack {
      List {
        Text(song.title).font(.headline)
        FavoriteControl(type:"songs",id:song.id)
        if let native=model.music.nowPlaying {
          Button("Aggiungi a playlist",systemImage:"text.badge.plus"){addPlaylist=true}
            .sheet(isPresented:$addPlaylist){AppleAddToPlaylistSheet(songs:[native])}
          NavigationLink {SongRelationshipsScreen(song:native,kind:.albums)} label:{Label("Vai all’album",systemImage:"square.stack")}
          NavigationLink {SongRelationshipsScreen(song:native,kind:.artists)} label:{Label("Vai all’artista",systemImage:"person")}

          Button("Riproduci dopo",systemImage:"text.line.first.and.arrowtriangle.forward") {Task{await model.music.enqueue(native,next:true)}}
          Button("Aggiungi alla coda",systemImage:"text.append") {Task{await model.music.enqueue(native,next:false)}}
          Button("Aggiungi alla libreria",systemImage:"plus") {Task{await model.music.add(native)}}
          if let url=native.url {ShareLink(item:url);Link("Apri in Musica",destination:url)}
        }
      }.navigationTitle("Opzioni brano").toolbar {Button("Chiudi"){onClose()}}
    }
  }
}
struct ApplePlayerQueueScreen:View {
  @EnvironmentObject var model:ApplePlayerAdapter
  @Environment(\.dismiss) private var dismiss
  var body:some View {
    NavigationStack {
      List {
        Text("\(model.music.playbackQueueEntries.count) elementi").font(.caption).foregroundStyle(.secondary)
        ForEach(model.music.playbackQueueEntries,id:\.id) {entry in
          Button {
            if model.music.isPlayerFixture {dismiss();return}
            model.music.player.queue.currentEntry=entry
            Task{await model.music.resume()};dismiss()
          } label:{
            HStack {
              YTPlayerArtwork(url:model.music.artworkURL(entry)).frame(width:44,height:44).clipShape(RoundedRectangle(cornerRadius:6))
                .accessibilityIdentifier("queue-artwork-"+entry.id)
              VStack(alignment:.leading) {Text(entry.title);Text(entry.subtitle ?? "").font(.caption).foregroundStyle(.secondary)}
              Spacer();if entry.id==model.music.player.queue.currentEntry?.id {Image(systemName:"waveform")}
            }
          }.accessibilityValue(entry.id==model.music.player.queue.currentEntry?.id ? "Brano corrente":"In coda")
            .task(id:model.music.artworkID(entry)){await model.music.loadArtwork(entry)}
        }
      }.navigationTitle("Coda").accessibilityIdentifier("playback-queue").toolbar {Button("Chiudi"){dismiss()}}
    }
  }
}
extension ToolbarItemPlacement {static var platformTrailing:Self {.topBarTrailing}}
extension View {
  func platformSheetSize()->some View {self}
  func inlineNavigationTitle()->some View {navigationBarTitleDisplayMode(.inline)}
  func playerToolbarBackground()->some View {toolbarBackground(.hidden,for:.navigationBar)}
}

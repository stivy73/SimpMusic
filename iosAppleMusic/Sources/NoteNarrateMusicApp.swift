import SwiftUI
@preconcurrency import MusicKit
import AVKit

@main
struct NoteNarrateMusicApp: App {
  @UIApplicationDelegateAdaptor(MusicAppDelegate.self) private var delegate
  @StateObject private var music = MusicAppState.shared.music
  @StateObject private var narration = MusicAppState.shared.narration
  var body: some Scene {
    WindowGroup { MusicRoot().environmentObject(music).environmentObject(narration).tint(.cyan).preferredColorScheme(.dark) }
  }
}
struct MusicRoot: View {
  @EnvironmentObject var music: MusicLibraryModel
  @State private var player = false
  @State private var selectedTab = 0
  @EnvironmentObject var narration: NarrationModel
  var body: some View {
    TabView(selection:$selectedTab) {
      NavigationStack {
        Group {
          if music.authorization != .authorized {
            ContentUnavailableView {
              Label("NoteNarrate", systemImage: "music.note")
            } description: {
              Text("Collega Apple Music per ascoltare la tua musica e scoprirne il significato. L'accesso al catalogo richiede un abbonamento Apple Music.")
            } actions: { Button("Collega Apple Music") { Task { await music.connect() } }.buttonStyle(.borderedProminent) }
          } else {
            List {
              if !music.canPlayCatalog { Text("Per ascoltare il catalogo, attiva un abbonamento nell'app Musica.").foregroundStyle(.secondary) }
              Section("Brani della libreria") { SongRows(songs: music.songs) }
            }.overlay { if music.loading { ProgressView() } }
              .refreshable { await music.refresh() }
          }
        }.navigationTitle("NoteNarrate")
      }.tag(0).tabItem { Label("Home",systemImage:"house") }
      NavigationStack {
        List { SongRows(songs: music.results) }.navigationTitle("Cerca")
          .searchable(text:$music.query,prompt:"Brano o artista su Apple Music")
          .onSubmit(of:.search) { Task { await music.search() } }
      }.tag(1).tabItem { Label("Cerca",systemImage:"magnifyingglass") }
      NavigationStack {
        List {
          Section("Album") {
            ForEach(music.albums) { album in
              Button { Task { await music.play(album:album) } } label: { CoverRow(artwork:album.artwork,title:album.title,subtitle:album.artistName) }
            }
          }
          Section("Playlist") {
            ForEach(music.playlists) { playlist in
              Button { Task { await music.play(playlist:playlist) } } label: { CoverRow(artwork:playlist.artwork,title:playlist.name,subtitle:playlist.curatorName ?? "Playlist") }
            }
          }
        }.navigationTitle("Libreria").refreshable { await music.refresh() }
      }.tag(2).tabItem { Label("Libreria",systemImage:"square.stack") }
      NavigationStack { MusicSettings(onSaved:{selectedTab=0}) }.tag(3).tabItem { Label("Impostazioni",systemImage:"gearshape") }
    }
    .safeAreaInset(edge:.bottom) {
      if let song = music.nowPlaying {
        HStack {
          Button { player=true } label: { CoverRow(artwork:song.artwork,title:song.title,subtitle:song.artistName) }.buttonStyle(.plain)
          Spacer()
          Button { Task { await music.toggle() } } label: { Image(systemName: music.playing ? "pause.fill":"play.fill").padding() }
            .accessibilityLabel(music.playing ? "Pausa":"Riproduci")
        }.padding(.horizontal).padding(.vertical,8).background(.regularMaterial)
      }
    }
    .sheet(isPresented:$player) { MusicPlayerScreen() }
    .task { await music.refresh() }
    .onChange(of:music.nowPlaying?.id) { _,_ in narration.stop();narration.text="";narration.attribution=nil }
    .alert("Apple Music",isPresented:Binding(get:{music.error != nil},set:{if !$0 { music.error=nil }})) { Button("OK") { music.error=nil } } message: { Text(music.error ?? "") }
  }
}
struct CoverRow: View {
  let artwork: Artwork?
  let title: String
  let subtitle: String
  var body: some View {
    HStack {
      Cover(artwork:artwork).frame(width:48,height:48).clipShape(RoundedRectangle(cornerRadius:8))
      VStack(alignment:.leading) { Text(title).foregroundStyle(.primary).lineLimit(2);Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
    }
  }
}
struct Cover: View {
  let artwork: Artwork?
  var body: some View {
    if let artwork { ArtworkImage(artwork,width:320).scaledToFit() }
    else { RoundedRectangle(cornerRadius:12).fill(.gray.opacity(0.2)).overlay { Image(systemName:"music.note") } }
  }
}
struct SongRows: View {
  @EnvironmentObject var music: MusicLibraryModel
  let songs: [MusicKit.Song]
  var body: some View {
    ForEach(songs) { song in
      Button { Task { await music.play(song,in:songs) } } label: { CoverRow(artwork:song.artwork,title:song.title,subtitle:song.artistName) }
        .contextMenu {
          Button("Riproduci successivo",systemImage:"text.line.first.and.arrowtriangle.forward") { Task { await music.enqueue(song,next:true) } }
          Button("Aggiungi alla coda",systemImage:"text.append") { Task { await music.enqueue(song,next:false) } }
          Button("Aggiungi alla libreria",systemImage:"plus") { Task { await music.add(song) } }
          if let url=song.url { ShareLink(item:url) }
        }
    }
  }
}
struct MusicPlayerScreen: View {
  @EnvironmentObject var music: MusicLibraryModel
  @EnvironmentObject var narration: NarrationModel
  @Environment(\.dismiss) private var dismiss
  @State private var meaning=false
  var body: some View {
    NavigationStack {
      ScrollView {
        if let song=music.nowPlaying {
          VStack(spacing:24) {
            Cover(artwork:song.artwork).frame(maxWidth:380).clipShape(RoundedRectangle(cornerRadius:20))
            Text(song.title).font(.title.bold());Text(song.artistName).foregroundStyle(.secondary)
            Slider(value:Binding(get:{min(music.duration,max(0,music.position))},set:{music.player.playbackTime=$0}),in:0...max(1,music.duration))
            HStack {
              Text(Duration.seconds(music.position).formatted(.time(pattern:.minuteSecond)))
              Spacer();Text(Duration.seconds(music.duration).formatted(.time(pattern:.minuteSecond)))
            }.font(.caption.monospacedDigit())
            HStack(spacing:48) {
              Button { Task { await music.previous() } } label: { Image(systemName:"backward.end.fill") }
              Button { Task { await music.toggle() } } label: { Image(systemName:music.playing ? "pause.fill":"play.fill").font(.system(size:48)) }
              Button { Task { await music.next() } } label: { Image(systemName:"forward.end.fill") }
            }.font(.title).buttonStyle(.plain)
            HStack {
              Button("Significato",systemImage:"lightbulb") { meaning=true }
              Spacer();RoutePicker().frame(width:44,height:44).accessibilityLabel("AirPlay")
              if let url=song.url { ShareLink(item:url) }
            }
            if !music.queueSongs.isEmpty {
              VStack(alignment:.leading) { Text("Coda").font(.headline);SongRows(songs:music.queueSongs) }
            }
          }.padding(24)
        }
      }.toolbar { ToolbarItem(placement:.topBarLeading) { Button("Chiudi",systemImage:"chevron.down") { dismiss() } } }
        .sheet(isPresented:$meaning) { MeaningScreen() }
    }
  }
}
struct MeaningScreen: View {
  @EnvironmentObject var music: MusicLibraryModel
  @EnvironmentObject var narration: NarrationModel
  @Environment(\.dismiss) private var dismiss
  @State private var consent=false
  var body: some View {
    NavigationStack {
      Form {
        Section("Testi con licenza") {
          Text("L’interpretazione utilizza esclusivamente un testo fornito dal servizio autorizzato. Titolo e artista vengono inviati al servizio testi; il testo e i riferimenti del brano vengono inviati a Google solo dopo la tua conferma.")
          if let attribution=narration.attribution { Text(attribution).font(.caption) }
          if let url=narration.sourceURL { Link("Fonte del testo",destination:url) }
        }
        Button("Prepara interpretazione") { consent=true }.disabled(narration.busy)
        if narration.busy { ProgressView("Preparazione…") }
        if let error=narration.error { Text(error).foregroundStyle(.orange) }
        if !narration.text.isEmpty {
          Section("Interpretazione AI") {
            Text(narration.text).textSelection(.enabled)
            Button("Leggi interpretazione",systemImage:"speaker.wave.2") { music.player.pause();narration.read() }
          }
        }
        Button("Interrompi",role:.destructive) { narration.stop() }
      }.navigationTitle("Significato")
        .toolbar { Button("Chiudi") { narration.stop();dismiss() } }
        .alert("Inviare il testo a Gemini?",isPresented:$consent) {
          Button("Invia e interpreta") {
            guard let song=music.nowPlaying else { return }
            narration.explain(id:song.id.rawValue,title:song.title,artist:song.artistName)
          }
          Button("Annulla",role:.cancel) {}
        } message: { Text("Il servizio testi riceverà il riferimento al brano. Titolo, artista e testo autorizzato saranno inviati a Google per generare l'interpretazione. La risposta AI può contenere errori. La lettura Gemini, se attiva, invia anche l'interpretazione a Google.") }
    }
  }
}
struct MusicSettings: View {
  var onSaved: () -> Void = {}
  @EnvironmentObject var narration: NarrationModel
  @State private var message: String?
  var body: some View {
    Form {
      Section("Gemini") {
        SecureField("Chiave API",text:$narration.key).textInputAutocapitalization(.never).autocorrectionDisabled()
        TextField("Modello",text:$narration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
        Toggle("Usa voce Gemini",isOn:$narration.useGeminiVoice)
        Text("La chiave resta nel Portachiavi del dispositivo. Il testo viene inviato a Google solo dopo la tua conferma. La voce di sistema non richiede l'invio dell'interpretazione a Google.").font(.caption)
        Button("Salva impostazioni") { do { try narration.save();onSaved() } catch {message=error.localizedDescription} }
        if let message { Text(message) }
      }
      Section("Privacy") {
        Text("Apple Music gestisce accesso e riproduzione. Questa app non estrae file audio e non usa cookie YouTube. Le interpretazioni restano nella sessione corrente. Il servizio testi riceve i riferimenti del brano scelto.")
        Button("Cancella testo e interpretazione",role:.destructive) { narration.stop();narration.attribution=nil;narration.text="" }
      }
    }.navigationTitle("Impostazioni")
  }
}
struct RoutePicker: UIViewRepresentable {
  func makeUIView(context:Context)->AVRoutePickerView { let view=AVRoutePickerView();view.tintColor = .cyan;view.prioritizesVideoDevices=false;return view }
  func updateUIView(_ uiView:AVRoutePickerView,context:Context) {}
}

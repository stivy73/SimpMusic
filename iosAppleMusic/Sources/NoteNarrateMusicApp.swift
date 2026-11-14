import SwiftUI
@preconcurrency import MusicKit
import AVKit

@main
struct NoteNarrateMusicApp: App {
  @UIApplicationDelegateAdaptor(MusicAppDelegate.self) private var delegate
  @StateObject private var music = MusicAppState.shared.music
  @StateObject private var narration = MusicAppState.shared.narration
  var body: some Scene {
    WindowGroup { MusicRoot().modifier(ReceiveMusicShares()).environmentObject(music).environmentObject(narration).environmentObject(MusicAppState.shared.playlists).environmentObject(MusicAppState.shared.playerPresentation).tint(.cyan).preferredColorScheme(.dark) }
  }
}
struct MusicRoot: View {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject var music: MusicLibraryModel
  @EnvironmentObject var presentation:ApplePlayerAdapter
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  @GestureState private var playerBackDrag:CGFloat=0
  private var model:ApplePlayerAdapter {presentation}
  #if DEBUG && LIBRARY_SYNC_LAYOUT_FIXTURE
  @State private var selectedTab = 2
  #else
  @State private var selectedTab = 0
  #endif
  @EnvironmentObject var narration: NarrationModel
  private var navigation: some View {
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
            MusicHomeScreen()
          }
        }.navigationTitle("NoteNarrate")
      }.tag(0).tabItem { Label("Home",systemImage:"house") }
      NavigationStack {CatalogSearchScreen()}.tag(1).tabItem{Label("Cerca",systemImage:"magnifyingglass")}
      NavigationStack {LibraryBrowserScreen()}.tag(2).tabItem{Label("Libreria",systemImage:"square.stack")}
      NavigationStack { MusicSettings(onSaved:{selectedTab=0}) }.tag(3).tabItem { Label("Impostazioni",systemImage:"gearshape") }
    }
    .modifier(SystemMiniPlayerAccessory())
    .modifier(LegacyMiniPlayerInset())
    .modifier(DuoNavigationBars())
    .task { await music.refreshHome() }
    .onChange(of:scenePhase) {_,phase in
      if phase == .active {Task{await music.refresh()}}
    }
    .onChange(of:music.nowPlaying?.id) { _,_ in narration.clearInterpretation() }
    .alert("Apple Music",isPresented:Binding(get:{music.notice != nil},set:{if !$0 {music.notice=nil}})) {Button("OK"){music.notice=nil}} message:{Text(music.notice ?? "")}
    .alert("Apple Music",isPresented:Binding(get:{music.error != nil},set:{if !$0 { music.error=nil }})) { Button("OK") { music.error=nil } } message: { Text(music.error ?? "") }
  }
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
        navigation.allowsHitTesting(!model.showPlayer).accessibilityHidden(model.showPlayer)
        if model.current != nil {
          // Retain the original presentation while MusicKit owns the media session.
          AdaptedYTPlayerScreen(player: model.player, onLibrary: { selectedTab = 2 })
            .environmentObject(model).background(.black)
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Native vertical bars draw in the display's safe-area region on Duo.
            // Clipping the navigation container here also clips those controls.
            .scaleEffect(model.showPlayer || reduceMotion ? 1 : 0.94, anchor: .bottom)
            .offset(x: layoutDirection == .rightToLeft ? -playerBackDrag : playerBackDrag)
            .offset(
              y: model.showPlayer || reduceMotion
                ? 0
                : geometry.size.height
            )
            .opacity(model.showPlayer ? 1 : 0)
            .animation(
              reduceMotion
                ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.92),
              value: model.showPlayer
            )
            .animation(
              reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9),
              value: playerBackDrag
            )
            .allowsHitTesting(model.showPlayer).accessibilityHidden(!model.showPlayer)
            .overlay(alignment: .leading) {
              #if os(iOS)
                if model.showPlayer {
                  Color.clear.frame(width: 20).contentShape(Rectangle())
                    .gesture(playerBackSwipe(width: geometry.size.width))
                    .accessibilityHidden(true)
                }
              #endif
            }
            .coordinateSpace(name: "player-back-swipe")
            .accessibilityAction(.escape) { model.minimizePlayer() }
        }
      }
    }
  }
  private func playerBackSwipe(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 14, coordinateSpace: .named("player-back-swipe"))
      .updating($playerBackDrag) { value, drag, transaction in
        guard model.showPlayer, let distance = playerBackDistance(value, width: width) else {
          return
        }
        transaction.animation = nil
        drag = min(distance, width * 0.8)
      }
      .onEnded { value in
        guard model.showPlayer, let distance = playerBackDistance(value, width: width) else {
          return
        }
        let direction: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        let projected = value.predictedEndTranslation.width * direction
        if distance >= min(100, width * 0.25)
          || (distance >= 32 && projected >= width * 0.5)
        {
          model.minimizePlayer()
        }
      }
  }

  private func playerBackDistance(_ value: DragGesture.Value, width: CGFloat) -> CGFloat? {
    let rtl = layoutDirection == .rightToLeft
    let start = rtl ? width - value.startLocation.x : value.startLocation.x
    let distance = value.translation.width * (rtl ? -1 : 1)
    // The content's controls start at least 20 pt in, so their horizontal drags
    // remain independent. Vertical lyric scrolling never triggers a dismissal.
    guard start >= 0, start < 20, distance > 0,
      distance > abs(value.translation.height) * 1.5
    else { return nil }
    return distance
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
    YTPlayerArtwork(url:PlaybackArtworkURL.resolve(artwork?.url(width:600,height:600)))
      .aspectRatio(1,contentMode:.fit).clipped()
  }
}
struct AlbumRows: View {
  @EnvironmentObject var music: MusicLibraryModel
  let albums: [Album]
  var body: some View {
    ForEach(albums) { album in
      NavigationLink { CollectionScreen(album:album) } label: {
        CoverRow(artwork:album.artwork,title:album.title,subtitle:album.artistName)
      }
    }
  }
}
struct SongRows: View {
  @EnvironmentObject var music: MusicLibraryModel
  let songs: [MusicKit.Song]
  var body: some View {
    ForEach(songs) { song in
      Button { Task { await music.play(song,in:songs) } } label: { CoverRow(artwork:song.artwork,title:song.title,subtitle:song.artistName) }
        .contextMenu {SongNavigationActions(song:song)}
    }
  }
}
struct MeaningScreen: View {
  @EnvironmentObject var music: MusicLibraryModel
  @EnvironmentObject var narration: NarrationModel
  @Environment(\.dismiss) private var dismiss
  @State private var consent=false
  @AppStorage("songMeaningGoogleConsent.v1") private var consentAccepted=false
  var body: some View {
    NavigationStack {
      Form {
        Button("Cerca significato") { requestMeaning() }.disabled(narration.busy)
        if narration.busy { ProgressView(narration.isReading ? "Lettura in corso…" : "Preparazione del significato…") }
        if let error=narration.error { Text(error).foregroundStyle(.orange) }
        if !narration.text.isEmpty {
          Section("Interpretazione AI") {
            Text(narration.text).textSelection(.enabled)
            Button("Leggi interpretazione",systemImage:"speaker.wave.2") { music.pause();narration.read() }
          }
        }
        Button("Interrompi",role:.destructive) { narration.stop() }
      }.navigationTitle("Significato")
        .task(id:music.nowPlaying?.id) {
          if narration.text.isEmpty && !narration.busy { requestMeaning() }
        }
        .toolbar { Button("Chiudi") { narration.stop();dismiss() } }
        .alert("Cercare il significato con Google?",isPresented:$consent) {
          Button("Cerca e interpreta") {
            consentAccepted=true
            startMeaning()
          }
          Button("Annulla",role:.cancel) {}
        } message: { Text("Titolo e artista saranno inviati a Gemini e Google Search per cercare fonti sul significato della canzone. Non viene inviato l’audio. La risposta AI può contenere errori. La lettura Gemini, se attiva, invia anche l’interpretazione a Google.") }
    }
  }
  private func requestMeaning() {
    guard music.nowPlaying != nil, !narration.busy else { return }
    if consentAccepted { startMeaning() } else { consent=true }
  }
  private func startMeaning() {
    guard let song=music.nowPlaying, !narration.busy else { return }
    narration.explain(id:song.id.rawValue,title:song.title,artist:song.artistName)
  }
}
struct MusicSettings: View {
  @EnvironmentObject var music: MusicLibraryModel
  var onSaved: () -> Void = {}
  @EnvironmentObject var narration: NarrationModel
  @State private var message: String?
  var body: some View {
    Form {
      Section("Collegamento Apple Music") {
        Button("Ripristina collegamento") { Task { await music.restoreAccess() } }
          .disabled(music.checkingAccess || music.loading)
        if music.checkingAccess { ProgressView("Verifica collegamento…") }
        Text("Rinnova l’accesso tramite MusicKit senza cambiare il tuo account Apple o la libreria.").font(.caption)
        Button("Verifica libreria cloud") { Task { await music.checkCloudLibrary() } }
          .disabled(music.checkingCloudLibrary || music.loading)
        if music.checkingCloudLibrary { ProgressView("Verifica libreria cloud…") }
        DisclosureGroup("Diagnostica Apple Music") {
          Text(music.accessReport+"\n"+music.artworkReport).font(.caption.monospaced()).textSelection(.enabled)
          ShareLink("Condividi diagnostica",item:music.accessReport+"\n"+music.artworkReport)
        }
      }
      Section("Gemini") {
        SecureField("Chiave API",text:$narration.key).textInputAutocapitalization(.never).autocorrectionDisabled()
        TextField("Modello",text:$narration.model).textInputAutocapitalization(.never).autocorrectionDisabled()
        Toggle("Usa voce Gemini",isOn:$narration.useGeminiVoice)
        Text("La chiave resta nel Portachiavi del dispositivo. Titolo e artista vengono inviati a Gemini e Google Search solo dopo la tua conferma. La voce di sistema non richiede l'invio dell'interpretazione a Google.").font(.caption)
        Button("Salva impostazioni") { do { try narration.save();onSaved() } catch {message=error.localizedDescription} }
        if let message { Text(message) }
      }
      Section("Privacy") {
        Text("Apple Music gestisce accesso e riproduzione. Questa app non estrae file audio e non usa cookie YouTube. Le interpretazioni restano nella sessione corrente. La ricerca del significato invia a Google titolo e artista del brano scelto. Le fonti e i risultati non vengono salvati su disco.")
        Button("Cancella testo e interpretazione",role:.destructive) { narration.clearInterpretation() }
      }
    }.navigationTitle("Impostazioni")
  }
}
struct RoutePicker: UIViewRepresentable {
  func makeUIView(context:Context)->AVRoutePickerView { let view=AVRoutePickerView();view.tintColor = .cyan;view.prioritizesVideoDevices=false;return view }
  func updateUIView(_ uiView:AVRoutePickerView,context:Context) {}
}

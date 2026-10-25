import AVKit
import Combine
import SwiftUI
import WebKit
import YouTubeSDK

#if !os(macOS)
  @main
  struct StivyApp: App {
    @UIApplicationDelegateAdaptor(CarPlayAppDelegate.self) private var delegate
    @StateObject private var model = AppleAppSession.shared.music
    @StateObject private var library = AppleAppSession.shared.library
    var body: some Scene {
      WindowGroup {
        RootView().environmentObject(model).environmentObject(library).tint(.cyan)
          .preferredColorScheme(.dark)
      }
    }
  }

#endif

struct Artwork: View {
  let url: URL?
  var fit = false
  var body: some View {
    AsyncImage(url: url) { image in
      image.resizable().aspectRatio(contentMode: fit ? .fit : .fill)
    } placeholder: {
      ZStack {
        LinearGradient(
          colors: [.cyan.opacity(0.5), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white)
      }
    }.clipped()
  }
}

struct RootView: View {
  @EnvironmentObject var model: MusicModel
  @EnvironmentObject var library: LibraryModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var tab = 0
  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
        navigation.allowsHitTesting(!model.showPlayer).accessibilityHidden(model.showPlayer)
        if model.current != nil {
          // Animate the retained player instead of removing its WKWebView and media session.
          PlayerScreen(player: model.player, onLibrary: { tab = 2 })
            .environmentObject(model).background(.black)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: model.showPlayer || reduceMotion ? 0 : 24))
            .scaleEffect(model.showPlayer || reduceMotion ? 1 : 0.94, anchor: .bottom)
            .offset(
              y: model.showPlayer || reduceMotion
                ? 0
                : geometry.size.height
            )
            .opacity(reduceMotion && !model.showPlayer ? 0 : 1)
            .animation(
              reduceMotion
                ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.92),
              value: model.showPlayer
            )
            .allowsHitTesting(model.showPlayer).accessibilityHidden(!model.showPlayer)
        }
      }
    }.clipped()
      .modifier(RadioFeedback())
  }

  private var navigation: some View {
    TabView(selection: $tab) {
      NavigationStack {
        HomeView(onSearch: { tab = 1 }, onSettings: { tab = 3 })
      }.modifier(LegacyMiniPlayerInset()).tabItem {
        Label("Home", systemImage: "house.fill")
      }.tag(0)
      NavigationStack {
        Group {
          if model.searching {
            ProgressView("Ricerca su YouTube Music…").frame(
              maxWidth: .infinity, maxHeight: .infinity)
          } else if let error = model.searchError {
            ContentUnavailableView {
              Label("Ricerca non riuscita", systemImage: "wifi.exclamationmark")
            } description: {
              Text(error)
            } actions: {
              Button("Riprova") { model.search() }
            }
          } else if model.songs.isEmpty {
            ContentUnavailableView.search(text: model.query)
          } else {
            SongList(songs: model.songs)
          }
        }.navigationTitle("Cerca")
          .searchable(text: $model.query, prompt: "Brano o artista")
          .onSubmit(of: .search) { model.search() }
      }.modifier(LegacyMiniPlayerInset()).tabItem {
        Label("Cerca", systemImage: "magnifyingglass")
      }.tag(1)
      NavigationStack {
        LibraryView(library: library)
      }.modifier(LegacyMiniPlayerInset()).tabItem {
        Label("Libreria", systemImage: "square.stack.fill")
      }.tag(2)
      NavigationStack { SettingsView().navigationTitle("Impostazioni") }
        .modifier(LegacyMiniPlayerInset())
        .tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }.tag(3)
    }
    .modifier(SystemMiniPlayerAccessory())
    .sheet(isPresented: $library.showLogin) {
      YouTubeLoginScreen(library: library)
    }
    .task(id: library.session) { await library.load(.likes) }
    .alert(
      "Sincronizzazione YouTube Music",
      isPresented: Binding(
        get: { library.syncError != nil }, set: { if !$0 { library.syncError = nil } })
    ) {
      Button("OK", role: .cancel) { library.syncError = nil }
    } message: {
      Text(library.syncError ?? "")
    }

  }
}

private struct SystemMiniPlayerAccessory: ViewModifier {
  @EnvironmentObject var model: MusicModel
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26.1, *) {
        content.tabViewBottomAccessory(isEnabled: model.current != nil) {
          MiniPlayer(systemAccessory: true)
        }
      } else {
        content
      }
    #else
      content
    #endif
  }
}

private struct LegacyMiniPlayerInset: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26.1, *) {
        content
      } else {
        content.safeAreaInset(edge: .bottom) { MiniPlayer() }
      }
    #else
      content.safeAreaInset(edge: .bottom) { MiniPlayer() }
    #endif
  }
}

struct MiniPlayer: View {
  var systemAccessory = false
  @EnvironmentObject var model: MusicModel
  var body: some View {
    if let song = model.current {
      HStack(spacing: 12) {
        Button {
          model.showPlayer = true
        } label: {
          HStack(spacing: 12) {
            Artwork(url: song.artwork).frame(width: 44, height: 44).clipShape(
              RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading) {
              Text(song.title).font(.subheadline.bold()).lineLimit(1)
              Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.up")
          }.contentShape(Rectangle())
        }.accessibilityIdentifier("open-player")
        MiniPlaybackButton(player: model.player)
          .disabled(model.busyMeaning || model.reading || model.player.isLoading)
      }.buttonStyle(.plain).padding(systemAccessory ? 8 : 12)
        .background(systemAccessory ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, systemAccessory ? 8 : 16).padding(.bottom, systemAccessory ? 0 : 8)
    }
  }
}

private struct MiniPlaybackButton: View {
  @ObservedObject var player: PlaybackPlayer
  var body: some View {
    Button {
      player.playing ? player.pause() : player.play()
    } label: {
      Image(systemName: player.playing ? "pause.fill" : "play.fill")
        .font(.title2).frame(width: 44, height: 44)
    }.accessibilityLabel(player.playing ? "Pausa" : "Riproduci")
      .accessibilityIdentifier("mini-playback-toggle")
      .accessibilityValue(player.playing ? "Riproduzione attiva" : "In pausa")
  }
}

struct SongList: View {
  @EnvironmentObject var model: MusicModel
  @EnvironmentObject var library: LibraryModel
  let songs: [Song]
  @State private var playlistSong: Song?
  var body: some View {
    List(songs) { song in
      Button {
        model.play(song, queue: songs)
      } label: {
        HStack(spacing: 14) {
          Artwork(url: song.artwork).frame(width: 58, height: 58).clipShape(
            RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading, spacing: 5) {
            Text(song.title).foregroundStyle(.primary).fontWeight(.semibold)
            Text(song.artist).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "play.circle.fill").font(.title2)
        }.padding(.vertical, 5)
      }.accessibilityIdentifier("song-\(song.id)")
        .contextMenu {
          QueueActions(song: song)
          YouTubeLikeButton(song: song)
          Button("Aggiungi a playlist") { playlistSong = song }
          Button {
            model.toggleFavorite(song)
          } label: {
            Label(
              model.favorites.contains(where: { $0.id == song.id })
                ? "Rimuovi dai preferiti locali" : "Salva nei preferiti locali",
              systemImage: "heart")
          }
        }
    }.listStyle(.plain)
      .sheet(item: $playlistSong) { song in AddToPlaylistSheet(song: song) }
  }
}

/// Shared by search, library, discovery, playlist tracks and the player's menu.
struct RadioFeedback: ViewModifier {
  @EnvironmentObject var model: MusicModel
  func body(content: Content) -> some View {
    content.alert(
      "Radio YouTube Music",
      isPresented: Binding(
        get: { model.radioActionError != nil }, set: { if !$0 { model.radioActionError = nil } }
      )
    ) {
      Button("OK") { model.radioActionError = nil }
    } message: {
      Text(model.radioActionError ?? "")
    }
  }
}

struct QueueActions: View {
  @EnvironmentObject var model: MusicModel
  let song: Song
  var body: some View {
    Button {
      model.enqueue(song, playNext: true)
    } label: {
      Label("Riproduci dopo", systemImage: "text.line.first.and.arrowtriangle.forward")
    }
    Button {
      model.enqueue(song)
    } label: {
      Label("Aggiungi alla coda", systemImage: "text.append")
    }
    Button {
      model.startRadio(song: song)
    } label: {
      Label("Avvia radio", systemImage: "dot.radiowaves.left.and.right")
    }
    if let artistID = song.artistBrowseID {
      Button {
        model.startRadio(artistID: artistID, title: song.artist)
      } label: {
        Label("Radio dell’artista", systemImage: "person.wave.2")
      }
    }
  }
}

struct QueueScreen: View {
  @EnvironmentObject var model: MusicModel
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          Toggle("Riproduzione automatica", isOn: $model.autoplayEnabled)
            .accessibilityIdentifier("queue-autoplay")
          if let title = model.radioTitle {
            Label(title, systemImage: "dot.radiowaves.left.and.right")
          }
          if model.loadingRadio {
            ProgressView("Preparo la radio…").accessibilityIdentifier("radio-loading")
          }
          if let error = model.radioError {
            Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier(
              "radio-error")
            Button("Riprova suggerimenti") { model.retryRadio() }
          }
          #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-radio") {
              Button("Simula fine brano") { model.player.onEnded?() }
                .accessibilityIdentifier("radio-test-ended")
              Button("Simula pausa") { model.player.pause() }
                .accessibilityIdentifier("radio-test-pause")
            }
          #endif
        } footer: {
          Text(
            "A coda terminata prosegue con i suggerimenti di YouTube Music. La ripetizione ha precedenza."
          )
        }
        Text("\(model.queue.count) brani").font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("queue-count")
        ForEach(model.queueRows) { row in
          Button {
            model.playQueueOccurrence(row.id)
            dismiss()
          } label: {
            HStack {
              Artwork(url: row.song.artwork).frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
              VStack(alignment: .leading) {
                Text(row.song.title)
                Text(row.song.artist).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if model.queueIndex == row.index { Image(systemName: "waveform") }
            }
          }.accessibilityIdentifier("queue-" + row.song.id)
            .accessibilityValue(model.queueIndex == row.index ? "Brano corrente" : "In coda")
            .contextMenu {
              Button("Riproduci dopo") { model.playQueueOccurrenceNext(row.id) }
                .disabled(model.queueIndex == row.index)
              Button("Rimuovi dalla coda", role: .destructive) {
                model.removeQueueOccurrence(row.id)
              }
            }
        }
        .onMove { offsets, destination in model.moveQueuedSongs(from: offsets, to: destination) }
        .onDelete { offsets in model.removeQueuedSongs(at: offsets) }
      }.navigationTitle("Coda").accessibilityIdentifier("playback-queue")
        .toolbar {
          #if os(iOS)
            ToolbarItem(placement: .platformLeading) { EditButton() }
          #endif
          ToolbarItem(placement: .platformTrailing) { Button("Chiudi") { dismiss() } }
        }
    }
  }
}

/// Account likes and local favorites are independent. No optimistic success on network failure.
struct YouTubeLikeButton: View {
  @EnvironmentObject var library: LibraryModel
  let song: Song
  var iconOnly = false
  private var pending: Bool { library.pendingLikes.contains(song.id) }
  private var label: String {
    if library.session == nil { return "Accedi per mettere Mi piace" }
    if !library.state(.likes).loaded { return "Verifica Mi piace su YouTube Music" }
    return library.isLiked(song.id)
      ? "Rimuovi Mi piace da YouTube Music" : "Mi piace su YouTube Music"
  }
  var body: some View {
    Button {
      Task { await library.toggleLike(song.discoveryItem) }
    } label: {
      if pending {
        ProgressView().accessibilityLabel("Sincronizzazione Mi piace")
      } else if iconOnly {
        Image(systemName: library.isLiked(song.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
          .frame(width: 44, height: 44)
      } else {
        Label(label, systemImage: library.isLiked(song.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
      }
    }.disabled(pending || library.state(.likes).loading)
      .accessibilityLabel(label).accessibilityIdentifier("youtube-like-" + song.id)
      .accessibilityValue(
        library.state(.likes).loaded
          ? (library.isLiked(song.id) ? "Attivo" : "Non attivo") : "Da verificare")
  }
}

struct PlayerScreen: View {
  @EnvironmentObject var model: MusicModel
  @Environment(\.dynamicTypeSize) private var typeSize
  @ObservedObject var player: PlaybackPlayer
  let onLibrary: () -> Void
  @State private var showVideo = false
  @State private var showLyrics = false
  @State private var expandedLyrics = false
  @State private var showQueue = false
  @State private var editLyrics = false
  @State private var playlistSong: Song?

  var body: some View {
    NavigationStack {
      Group {
        #if os(iOS)
          GeometryReader { geometry in
            if #available(iOS 27.1, *), geometry.size.width >= 700,
              !typeSize.isAccessibilitySize
            {
              ArrangementView {
                nowPlaying(expanded: true)
              } secondary: {
                LyricsContent().environmentObject(model).padding()
                  .accessibilityIdentifier("expanded-player-lyrics")
              }
              .arrangementViewStyle(.split)
              .task(id: model.current?.id) { model.loadLyrics() }
            } else {
              nowPlaying()
            }
          }
        #else
          nowPlaying()
        #endif
      }
      .playerToolbarBackground()
      .inlineNavigationTitle()
      .toolbar {
        if model.showPlayer {
          ToolbarItem(placement: .platformLeading) {
            Button {
              model.minimizePlayer()
              onLibrary()
            } label: {
              Label("Libreria", systemImage: "square.stack")
            }
            .accessibilityIdentifier("return-to-library")
          }
          ToolbarItem(placement: .platformTrailing) {
            Button {
              model.minimizePlayer()
            } label: {
              Label("Torna alla schermata precedente", systemImage: "chevron.down")
            }.accessibilityIdentifier("close-player")
          }
        }
      }
      .onChange(of: model.current?.id) { _, _ in if showLyrics { model.loadLyrics() } }
      .sheet(
        isPresented: $model.showMeaning,
        onDismiss: {
          if model.meaningPresentationOnPhone { model.stopMeaning() }
        }
      ) {
        MeaningView().environmentObject(model).platformSheetSize()
      }
      .sheet(item: $playlistSong) { song in AddToPlaylistSheet(song: song) }
      .sheet(isPresented: $showQueue) { QueueScreen() }
      .sheet(isPresented: $expandedLyrics) {
        NavigationStack {
          LyricsContent().environmentObject(model).padding().navigationTitle("Testo").toolbar {
            Button("Chiudi") { expandedLyrics = false }
          }
        }
      }
      .sheet(isPresented: $editLyrics) {
        NavigationStack {
          TextEditor(text: $model.manualLyrics)
            .accessibilityLabel("Testo manuale della canzone")
            .accessibilityIdentifier("manual-lyrics-editor")
            .padding()
            .navigationTitle("Testo della canzone")
            .toolbar {
              Button("Fine") {
                editLyrics = false
                showLyrics = true
                showVideo = false
              }
            }
        }
      }
    }
  }
  private func nowPlaying(expanded: Bool = false) -> some View {
    GeometryReader { geometry in
      let wide =
        geometry.size.width >= 680 && geometry.size.height >= 280
        && geometry.size.width > geometry.size.height && !typeSize.isAccessibilitySize
      let width = max(0, min(geometry.size.width, 1100) - 40)
      let column = wide ? (width - 32) / 2 : width
      let layout =
        wide ? AnyLayout(HStackLayout(spacing: 32)) : AnyLayout(VStackLayout(spacing: 18))
      ZStack {
        if let song = model.current {
          Artwork(url: song.artwork)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped().blur(radius: 65).opacity(0.42).ignoresSafeArea()
          LinearGradient(
            colors: [.black.opacity(0.15), .black.opacity(0.85)], startPoint: .top,
            endPoint: .bottom
          ).ignoresSafeArea()
          ScrollView {
            layout {
              ZStack {
                #if os(macOS)
                  // macOS retains the embedded playback session.
                  EmbeddedPlayer(player: player).id(player.loadID)
                    .opacity(showVideo ? 1 : 0).allowsHitTesting(showVideo)
                    .accessibilityHidden(!showVideo)
                #endif
                if !showVideo {
                  if showLyrics && !expanded {
                    LyricsContent().environmentObject(model)
                  } else {
                    Artwork(url: song.artwork, fit: true)
                      .accessibilityElement(children: .ignore)
                      .accessibilityAddTraits(.isImage)
                      .accessibilityLabel("Copertina di \(song.title)")
                      .accessibilityIdentifier("player-artwork")
                  }
                }
              }
              .frame(
                width: column,
                height: wide
                  ? max(120, min(column, geometry.size.height - 90))
                  : min(column, geometry.size.height * 0.45)
              )
              .clipShape(RoundedRectangle(cornerRadius: 20))
              VStack(spacing: 22) {
                songHeading(song, expanded: expanded)
                PlayerControls(player: player, reading: model.reading || model.busyMeaning)
                HStack {
                  playerAction("Testo della canzone", icon: "quote.bubble", selected: showLyrics) {
                    showLyrics.toggle()
                    showVideo = false
                    if showLyrics && !expanded { model.loadLyrics() }
                  }.accessibilityIdentifier("toggle-lyrics")
                  Spacer()
                  playerAction(
                    showVideo ? "Mostra copertina" : "Mostra video",
                    icon: showVideo ? "photo" : "play.rectangle", selected: showVideo
                  ) {
                    openVideo()
                    showLyrics = false
                  }.accessibilityIdentifier("toggle-video")
                  Spacer()
                  playerAction("Coda di riproduzione", icon: "music.note.list", selected: false) {
                    showQueue = true
                  }
                  .accessibilityIdentifier("show-queue")
                }.padding(.horizontal, 22)
                if showLyrics && !expanded {
                  HStack {
                    Button {
                      expandedLyrics = true
                    } label: {
                      Label("Espandi testo", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Spacer()
                    ShareLink(
                      item: model.manualLyrics.isEmpty ? model.lyrics : model.manualLyrics
                    ) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel(
                      "Condividi testo")
                  }.font(.subheadline)
                }
              }.frame(width: column)
            }.padding(20).frame(maxWidth: .infinity)
          }
        }
      }.foregroundStyle(.white).tint(.white)
    }
  }

  private func songHeading(_ song: Song, expanded: Bool) -> some View {
    let identity = HStack(spacing: 12) {

      if showLyrics && !expanded {
        Artwork(url: song.artwork).frame(width: 48, height: 48).clipShape(
          RoundedRectangle(cornerRadius: 8))
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(song.title).font(.title2.bold()).lineLimit(2)
        Text(song.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65))
          .lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
    let actions = HStack(spacing: 12) {
      YouTubeLikeButton(song: song, iconOnly: true)
      Button {
        #if DEBUG
          #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--test-carplay-meaning") {
              CarPlayNarrationRequest.start(model) { completion in
                // Reproduce a vehicle that never delivers the presentation callback.
                if ProcessInfo.processInfo.arguments.contains(
                  "--test-carplay-presentation-failure")
                {
                  completion(false)
                }
              }
            } else {
              model.explain()
            }
          #else
            model.explain()
          #endif
        #else
          model.explain()
        #endif
      } label: {
        Label("Significato della canzone", systemImage: "lightbulb.max.fill")
          .labelStyle(.iconOnly).frame(width: 44, height: 44)
      }
      .accessibilityLabel("Significato della canzone").disabled(player.isLoading)
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-carplay-meaning") {
          Text(
            verbatim:
              "\(model.narrationStarts):\(model.narrationFinishes):\(model.reading):\(model.busyMeaning):\(model.systemArtworkAvailable):\(model.systemNarrationActive):\(model.preparingNarrationInBackground)"
          )
          .font(.system(size: 1)).frame(width: 1, height: 1)
          .accessibilityIdentifier("carplay-diagnostics")
        }
      #endif
      Menu {
        QueueActions(song: song)
        Button("Aggiungi a playlist") { playlistSong = song }
        Button {
          model.toggleFavorite(song)
        } label: {
          Label(
            model.favorites.contains(where: { $0.id == song.id })
              ? "Rimuovi dai preferiti locali" : "Salva nei preferiti locali", systemImage: "heart")
        }
        ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(song.id)")!) {
          Label("Condividi brano", systemImage: "square.and.arrow.up")
        }
        Button {
          editLyrics = true
        } label: {
          Label("Aggiungi o modifica il testo", systemImage: "square.and.pencil")
        }
        Button {
          openVideo()
          showLyrics = false
        } label: {
          Label(
            showVideo ? "Mostra copertina" : "Mostra video",
            systemImage: "play.rectangle")
        }
      } label: {
        Image(systemName: "ellipsis").frame(width: 44, height: 44)
      }.accessibilityLabel("Altre opzioni")
    }.font(.title2).buttonStyle(.plain)
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        identity
        actions
      }
      VStack(alignment: .leading, spacing: 8) {
        identity
        actions
      }
    }
  }

  private func openVideo() {
    #if os(macOS)
      showVideo.toggle()
      showLyrics = false
    #else
      guard let id = model.current?.id,
        var url = URLComponents(string: "https://www.youtube.com/watch")
      else { return }
      url.queryItems = [URLQueryItem(name: "v", value: id)]
      guard let target = url.url else { return }
      model.stopMeaning(resume: false)
      player.pause()
      UIApplication.shared.open(target)
    #endif
  }
  private func playerAction(
    _ label: String, icon: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.title2).frame(width: 52, height: 48)
        .background(selected ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 16))
    }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(selected ? "Attivo" : "")
  }
}

struct LyricsContent: View {
  @EnvironmentObject var model: MusicModel
  private var text: String { model.manualLyrics.isEmpty ? model.lyrics : model.manualLyrics }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if model.loadingLyrics && text.isEmpty { ProgressView(model.lyricsProgress) }
        if !text.isEmpty {
          Text(text).font(.title2.bold()).lineSpacing(12).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("song-lyrics")
          Text("Testo non sincronizzato").font(.caption).foregroundStyle(.secondary)
          if model.manualLyrics.isEmpty, let source = model.lyricsSource {
            if let url = model.lyricsSourceURL {
              Link("Testo: \(source.rawValue)", destination: url).font(.caption)
            } else {
              Text("Testo: \(source.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
          }
          HStack {
            Button {
              PlatformClipboard.copy(text)
            } label: {
              Label("Copia testo", systemImage: "doc.on.doc")
            }
            Spacer()
            ShareLink(item: text) { Label("Condividi testo", systemImage: "square.and.arrow.up") }
          }.labelStyle(.iconOnly)
        } else if let error = model.lyricsError {
          Text(error).foregroundStyle(.secondary)
          Button("Riprova") { model.loadLyrics(force: true) }
        }
      }.padding(18)
    }.task { model.loadLyrics() }
  }
}

struct PlayerControls: View {
  @EnvironmentObject var model: MusicModel
  @ObservedObject var player: PlaybackPlayer
  let reading: Bool
  @State private var scrubTime = 0.0
  @State private var scrubbing = false
  private var elapsed: Double { scrubbing ? scrubTime : player.elapsed }
  private var duration: Double { max(0, player.durationSeconds) }
  private func clock(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = Int(max(0, seconds))
    return value >= 3600
      ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
      : String(format: "%d:%02d", value / 60, value % 60)
  }
  var body: some View {
    VStack(spacing: 20) {
      if player.isLoading { ProgressView("Preparazione audio…") }
      if let error = player.playbackError {
        Text(error).font(.caption).foregroundStyle(.orange).accessibilityIdentifier(
          "playback-error")
        Button("Riprova riproduzione") { player.load(videoId: player.videoId) }
      }
      #if DEBUG && os(iOS)
        if ProcessInfo.processInfo.arguments.contains("--test-native-audio") {
          Text(player.diagnostic).accessibilityIdentifier("native-audio-status")
        }
      #endif
      VStack(spacing: 4) {
        Slider(
          value: Binding(get: { min(elapsed, max(duration, 1)) }, set: { scrubTime = $0 }),
          in: 0...max(duration, 1),
          onEditingChanged: { editing in
            if editing { scrubTime = player.elapsed }
            scrubbing = editing
            if !editing { player.seek(to: CMTime(seconds: scrubTime, preferredTimescale: 600)) }
          }
        ).disabled(reading || player.isLoading || duration == 0).accessibilityLabel(
          "Posizione nel brano"
        ).accessibilityIdentifier("playback-seek")
        HStack {
          Text(clock(elapsed)).accessibilityIdentifier(
            "playback-elapsed"
          ).accessibilityLabel(clock(elapsed)).accessibilityValue(
            String(Int(max(0, elapsed))))
          Spacer()
          Label("YouTube", systemImage: "waveform").font(.caption2).padding(.horizontal, 10)
            .padding(.vertical, 5).background(.white.opacity(0.12), in: Capsule())
          Spacer()
          Text(duration > 0 ? "−" + clock(duration - elapsed) : "—")
        }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
      }
      HStack {
        Button {
          model.setShuffle(!model.shuffleEnabled)
        } label: {
          Image(systemName: "shuffle").foregroundStyle(model.shuffleEnabled ? Color.cyan : .white)
            .frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Riproduzione casuale").accessibilityValue(
          model.shuffleEnabled ? "Attiva" : "Disattivata"
        )
        .accessibilityIdentifier("playback-shuffle")
        Spacer()
        Button {
          model.previousSong()
        } label: {
          Image(systemName: "backward.end.fill").frame(minWidth: 44, minHeight: 64)
        }
        .disabled(!model.hasPrevious && elapsed <= 3).accessibilityLabel("Brano precedente")
        .accessibilityIdentifier("previous-song")
        Spacer()
        Button {
          player.playing ? player.pause() : player.play()
        } label: {
          Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 48))
            .frame(minWidth: 64, minHeight: 72)
        }.accessibilityIdentifier("playback-toggle").accessibilityLabel(
          player.playing ? "Pausa" : "Riproduci"
        ).accessibilityValue(player.playing ? "Riproduzione attiva" : "In pausa")
        Spacer()
        Button {
          model.nextSong()
        } label: {
          Image(systemName: "forward.end.fill").frame(minWidth: 44, minHeight: 64)
        }
        .disabled(!model.hasNext).accessibilityLabel("Brano successivo").accessibilityIdentifier(
          "next-song")
        Spacer()
        Button {
          model.repeatMode = model.repeatMode.next
        } label: {
          Image(systemName: model.repeatMode == .one ? "repeat.1" : "repeat")
            .foregroundStyle(model.repeatMode == .off ? Color.white : .cyan)
            .frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Ripetizione").accessibilityValue(model.repeatMode.title)
          .accessibilityIdentifier("playback-repeat")
      }.font(.title).buttonStyle(.plain).disabled(
        reading || player.isLoading)
      HStack(spacing: 14) {
        Image(systemName: "speaker.fill")
        Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...100)
          .accessibilityLabel("Volume del player")
        Image(systemName: "speaker.wave.3.fill")
      }.font(.caption)
    }
  }
}

struct MeaningView: View {
  @EnvironmentObject var model: MusicModel
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if model.busyMeaning { ProgressView(model.meaningProgress) }
          if let error = model.meaningError {
            Text(error).foregroundStyle(.orange)
            Button("Riprova") { model.explain() }
          }
          if !model.meaning.isEmpty {
            if model.manualLyrics.isEmpty, let source = model.lyricsSource {
              Text("Testo recuperato da \(source.rawValue)").font(.caption).foregroundStyle(
                .secondary)
            }
            Text(model.meaning).accessibilityIdentifier("meaning-text").font(.title3).lineSpacing(6)
              .textSelection(.enabled)
            if !Interpretation.isExpectedLength(model.meaning) {
              Text("Il modello ha superato il limite richiesto; il testo è mantenuto completo.")
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 22) {
              Button {
                PlatformClipboard.copy(model.meaning)
              } label: {
                Label("Copia", systemImage: "doc.on.doc")
              }
              ShareLink(item: model.meaning) {
                Label("Condividi", systemImage: "square.and.arrow.up")
              }
              Button {
                model.reading ? model.stopMeaning() : model.readAgain()
              } label: {
                Image(systemName: model.reading ? "stop.fill" : "play.fill")
              }.disabled(model.busyMeaning).accessibilityLabel(
                model.reading ? "Interrompi lettura" : "Leggi interpretazione")
            }.labelStyle(.iconOnly).font(.title2)
            Button("Rigenera interpretazione", systemImage: "arrow.clockwise") {
              model.explain(force: true)
            }.disabled(model.busyMeaning || model.reading)
          }
        }.padding(24)
      }.navigationTitle("Significato").inlineNavigationTitle()
        .toolbar {
          Button("Chiudi") {
            model.stopMeaning()
            dismiss()
          }.accessibilityIdentifier("close-meaning")
        }
    }.presentationDragIndicator(.visible)
  }
}

struct SettingsView: View {
  @EnvironmentObject var model: MusicModel
  @EnvironmentObject var library: LibraryModel
  var body: some View {
    Form {
      Section("Account YouTube Music") {
        if library.session != nil {
          Label("Account collegato", systemImage: "checkmark.circle")
          Button("Cambia account") { library.showLogin = true }
          Button("Esci", role: .destructive) { library.disconnect() }
        } else {
          Button("Accedi a YouTube Music") { library.showLogin = true }
        }
        if let error = library.error { Text(error).font(.caption).foregroundStyle(.orange) }
      }
      Section("Riproduzione") {
        Toggle("Riproduzione automatica", isOn: $model.autoplayEnabled)
        Text(
          "Terminata la coda, continua con brani suggeriti da YouTube Music. Puoi avviare una radio dal menu di un brano o di un artista."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Interpretazione IA") {
        SecureField("Chiave API Google Gemini", text: $model.apiKey).verbatimTextInput()
          .accessibilityIdentifier("gemini-key")
        Link("Non hai le API?", destination: URL(string: "https://aistudio.google.com/apikey")!)
        TextField("Modello", text: $model.textModel).verbatimTextInput()
        Text(
          "Titolo, artista e testo vengono inviati a Google solo quando richiedi il significato. La chiave è salvata nel Portachiavi."
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section("Lettura") {
        Toggle("Usa Gemini TTS", isOn: $model.useGeminiVoice)
        if model.useGeminiVoice {
          Picker("Stile", selection: $model.style) {
            ForEach(VoiceStyle.allCases) { Text($0.rawValue).tag($0) }
          }
          Picker("Voce", selection: $model.voice) {
            ForEach(["Kore", "Puck", "Charon", "Aoede"], id: \.self) { Text($0).tag($0) }
          }
        } else {
          Text("Voce italiana di sistema, senza una seconda richiesta cloud.").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Section {
        DisclosureGroup("Diagnostica lettura") {
          Text(diagnostics).font(.caption).textSelection(.enabled)
          ShareLink(item: diagnostics) {
            Label("Condividi diagnostica", systemImage: "square.and.arrow.up")
          }
          Text("Solo le ultime fasi audio, senza chiavi API, testo, indirizzi firmati o brani.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Section {
        Button("Salva impostazioni") { model.saveSettings() }
        if let error = model.settingsError { Text(error).foregroundStyle(.orange) }
      }
      Section(
        "NoteNarrate · "
          + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
      ) {
        NavigationLink("Licenze open source") {
          ScrollView {
            Text(thirdPartyNotices).font(.footnote).textSelection(.enabled).padding()
          }.navigationTitle("Licenze")
        }
        Text(
          "Client Apple sperimentale. Ricerca e riproduzione dipendono dalle API interne di YouTube. Raccolte remote e Mi piace sincronizzati con YouTube Music. Su iOS l’audio usa il player nativo anche in background; il video è opzionale. CarPlay richiede l’abilitazione audio da Apple."
        ).font(.caption)
      }
    }
  }
  private var diagnostics: String {
    #if os(iOS)
      "Build: " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        + "\nVoce: " + model.narrationDiagnostic + "\nAccount audio: "
        + model.player.sourceDiagnostic
        + "\nMusica: " + model.player.networkDiagnostic
    #else
      "Voce: " + model.narrationDiagnostic
    #endif
  }
  private var thirdPartyNotices: String {
    guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return "YouTubeSDK — Copyright © 2026 Aarav Gupta — MIT License" }
    return text
  }
}

#if os(macOS)
  struct EmbeddedPlayer: PlatformWebViewRepresentable {
    @ObservedObject var player: PlaybackPlayer
    func makeCoordinator() -> Coordinator { Coordinator(player: player) }
    #if os(macOS)
      func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
      }
      func updateNSView(_ view: WKWebView, context: Context) {}
      static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        dismantleWebView(view, coordinator: coordinator)
      }
    #else
      func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
      }
      func updateUIView(_ view: WKWebView, context: Context) {}
      static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        dismantleWebView(view, coordinator: coordinator)
      }
    #endif
    private func makeWebView(coordinator: Coordinator) -> WKWebView {
      let configuration = WKWebViewConfiguration()
      #if !os(macOS)
        configuration.allowsInlineMediaPlayback = true
      #else
        // Keep the retained music session scheduled while navigating or minimizing the window.
        configuration.preferences.inactiveSchedulingPolicy = .none
      #endif
      configuration.defaultWebpagePreferences.preferredContentMode = .mobile
      configuration.mediaTypesRequiringUserActionForPlayback = []
      configuration.userContentController.add(coordinator, name: "playback")
      let view = WKWebView(frame: .zero, configuration: configuration)
      #if !os(macOS)
        view.isOpaque = false
        view.scrollView.isScrollEnabled = false
      #endif
      player.webView = view
      let encoded = String(data: try! JSONEncoder().encode(player.videoId), encoding: .utf8)!
      let origin =
        "https://" + (Bundle.main.bundleIdentifier ?? "com.stivy.simpmusic.prototype").lowercased()
      let start = Int(player.elapsed)
      let autoplay = player.wantsPlayback ? 1 : 0
      let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#000"><div id="video"></div>
        <script src="https://www.youtube.com/iframe_api"></script><script>
        var player;
        function report(extra) {
          window.webkit.messageHandlers.playback.postMessage(Object.assign({id: \(encoded)}, extra));
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('video', {width:'100%', height:'100%', videoId: \(encoded),
            playerVars: {autoplay:\(autoplay), playsinline:1, controls:1, origin:'\(origin)', start:\(start)},
            events: {
              onReady: function(){report({ready:true});},
              onStateChange: function(event){report({state:event.data});},
              onError: function(event){report({error:event.data});}
            }});
        }
        </script><style>html,body,#video{width:100%;height:100%}</style></body></html>
        """
      view.loadHTMLString(html, baseURL: URL(string: origin))
      return view
    }
    private static func dismantleWebView(_ view: WKWebView, coordinator: Coordinator) {
      coordinator.stopProgressUpdates()
      view.evaluateJavaScript("player.pauseVideo()", completionHandler: nil)
      view.configuration.userContentController.removeScriptMessageHandler(forName: "playback")
      if coordinator.player.webView === view {
        coordinator.player.playing = false
        coordinator.player.webView = nil
      }
    }
    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
      let player: PlaybackPlayer
      private var progressTimer: Timer?
      private var readingProgress = false
      init(player: PlaybackPlayer) { self.player = player }

      func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
      }

      private func startProgressUpdates() {
        stopProgressUpdates()
        // WebKit can throttle page timers when the video is hidden behind artwork.
        // Ask for the actual media time from a native timer; never extrapolate playback.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
          Task { @MainActor [weak self] in self?.readProgress() }
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readProgress()
      }

      private func readProgress() {
        guard !readingProgress, let view = player.webView else { return }
        readingProgress = true
        view.evaluateJavaScript(
          "if (typeof player !== 'undefined' && player.getCurrentTime) { report({elapsed:player.getCurrentTime(),duration:player.getDuration()}); }"
        ) { [weak self] _, _ in self?.readingProgress = false }
      }
      func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
      ) {
        guard message.webView === player.webView, message.frameInfo.isMainFrame,
          let value = message.body as? [String: Any],
          value["id"] as? String == player.videoId
        else { return }
        if value["ready"] as? Bool == true {
          player.isLoading = false
          startProgressUpdates()
          player.setVolume(player.volume)
          if player.wantsPlayback { player.play() } else { player.pause() }
        }
        if let state = value["state"] as? Int {
          let wasPlaying = player.playing
          player.playing = state == 1
          if state == 1 { player.wantsPlayback = true }
          if state == 0 || (state == 2 && wasPlaying) { player.wantsPlayback = false }
          if state == 0 { player.onEnded?() }
        }
        if let elapsed = value["elapsed"] as? Double, elapsed.isFinite, elapsed >= 0 {
          player.elapsed = elapsed
        }
        if let duration = value["duration"] as? Double, duration.isFinite, duration > 0 {
          player.durationSeconds = duration
        }
        if let error = value["error"] as? Int {
          player.isLoading = false
          player.playing = false
          player.playbackError =
            "YouTube non consente la riproduzione incorporata di questo brano (\(error)). Prova un altro risultato."
        }
      }
    }
  }
#endif

// Only platform bridges live here; the player, lyrics and interpretation UI stay shared.
#if os(macOS)
  import AppKit
  typealias PlatformWebViewRepresentable = NSViewRepresentable
#else
  typealias PlatformWebViewRepresentable = UIViewRepresentable
#endif

@MainActor
enum PlatformClipboard {
  static func copy(_ text: String) {
    #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    #else
      UIPasteboard.general.string = text
    #endif
  }
}

extension ToolbarItemPlacement {
  static var platformLeading: Self {
    #if os(macOS)
      .navigation
    #else
      .topBarLeading
    #endif
  }
  static var platformTrailing: Self {
    #if os(macOS)
      .primaryAction
    #else
      .topBarTrailing
    #endif
  }
}

extension View {
  @ViewBuilder
  func platformSheetSize() -> some View {
    #if os(macOS)
      self.frame(minWidth: 620, idealWidth: 680, minHeight: 440, idealHeight: 520)
    #else
      self
    #endif
  }

  @ViewBuilder
  func verbatimTextInput() -> some View {
    #if os(macOS)
      self.autocorrectionDisabled()
    #else
      self.textInputAutocapitalization(.never).autocorrectionDisabled()
    #endif
  }
  @ViewBuilder
  func inlineNavigationTitle() -> some View {
    #if os(macOS)
      self
    #else
      self.navigationBarTitleDisplayMode(.inline)
    #endif
  }
  @ViewBuilder
  func playerToolbarBackground() -> some View {
    #if os(macOS)
      self
    #else
      self.toolbarBackground(.hidden, for: .navigationBar)
    #endif
  }
}

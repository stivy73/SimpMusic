// Player presentation ported from iosPrototype/Sources/App/StivyApp.swift at 5a277798.
// Original SHA256: 23ab00e6eee9a94887e951f85345708d25a7e80413d96519f00cf0701afbedb2
// Reproduce with Scripts/import_youtube_player.py. Service adaptations are explicit there.
import AVKit
import Combine
import SwiftUI

struct YTPlayerArtwork: View {
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

struct DuoNavigationBars: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 27.1, *) {
        content.toolbarVerticalBehavior(.automatic)
          .toolbarVerticalCompressionBehavior(.prefersTabBar)
      } else {
        content
      }
    #else
      content
    #endif
  }
}

struct SystemMiniPlayerAccessory: ViewModifier {
  @EnvironmentObject var model: ApplePlayerAdapter
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26.1, *) {
        content.tabViewBottomAccessory(isEnabled: model.current != nil && !model.isPassenger) {
          AppleMiniPlayer(systemAccessory: true)
        }
      } else {
        content
      }
    #else
      content
    #endif
  }
}

struct LegacyMiniPlayerInset: ViewModifier {
  @ViewBuilder func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26.1, *) {
        content
      } else {
        content.safeAreaInset(edge: .bottom) { AppleMiniPlayer() }
      }
    #else
      content.safeAreaInset(edge: .bottom) { AppleMiniPlayer() }
    #endif
  }
}

struct AppleMiniPlayer: View {
  var systemAccessory = false
  @EnvironmentObject var model: ApplePlayerAdapter
  var body: some View {
    if let song = model.current, !model.isPassenger {
      HStack(spacing: 12) {
        Button {
          model.showPlayer = true
        } label: {
          HStack(spacing: 12) {
            YTPlayerArtwork(url: song.artwork).frame(width: 44, height: 44).clipShape(
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
  @ObservedObject var player: ApplePlayerAdapter
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

struct AdaptedYTPlayerScreen: View {
  @EnvironmentObject var model: ApplePlayerAdapter
  @Environment(\.dynamicTypeSize) private var typeSize
  @ObservedObject var player: ApplePlayerAdapter
  let onLibrary: () -> Void
  @State private var showVideo = false
  @State private var showLyrics = false
  @State private var expandedLyrics = false
  @State private var showQueue = false
  @State private var optionsSong: PlayerSong?

  var body: some View {
    NavigationStack {
      Group {
        #if os(iOS)
          if #available(iOS 27.1, *) {
            PlayerBarLayout { vertical in
              playerContent(verticalBar: vertical)
                .toolbar { duoToolbar(vertical: vertical) }
                .toolbarVerticalBehavior(.automatic)
                .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
            }
          } else {
            playerContent(verticalBar: false).toolbar { navigationToolbar }
          }
        #else
          playerContent(verticalBar: false).toolbar { navigationToolbar }
        #endif
      }
      .onChange(of: model.current?.id) { _, _ in if showLyrics { model.loadLyrics() } }
      .sheet(
        isPresented: $model.showMeaning,
        onDismiss: {
          if model.meaningPresentationOnPhone { model.stopMeaning() }
        }
      ) {
        MeaningScreen().environmentObject(model).platformSheetSize()
      }
      .sheet(item: $optionsSong) { song in
        ApplePlayerOptions(song: song, onClose: { optionsSong = nil })
      }
      .sheet(isPresented: $showQueue) { ApplePlayerQueueScreen() }
      .sheet(isPresented: $expandedLyrics) {
        NavigationStack {
          PlayerInfoContent().environmentObject(model).padding().navigationTitle("Fonti e significato").toolbar {
            Button("Chiudi") { expandedLyrics = false }
          }
        }
      }

    }
  }

  private func playerContent(verticalBar: Bool) -> some View {
    Group {
      #if os(iOS)
        GeometryReader { geometry in
          if #available(iOS 27.1, *), geometry.size.width >= 700,
            !typeSize.isAccessibilitySize
          {
            ArrangementView {
              nowPlaying(expanded: true, verticalBar: verticalBar)
            } secondary: {
              PlayerInfoContent().environmentObject(model).padding()
                .accessibilityIdentifier("expanded-player-lyrics")
            }
            .arrangementViewStyle(.split)
            .task(id: model.current?.id) { model.loadLyrics() }
          } else {
            nowPlaying(verticalBar: verticalBar)
          }
        }
      #else
        nowPlaying()
      #endif
    }.playerToolbarBackground().inlineNavigationTitle()
  }

  private var backButton: some View {
    Button { model.minimizePlayer() } label: {
      Label("Indietro", systemImage: "chevron.backward")
    }.accessibilityLabel("Torna alla schermata precedente")
      .accessibilityIdentifier("close-player")
  }

  private var libraryButton: some View {
    Button {
      model.minimizePlayer()
      onLibrary()
    } label: {
      Label("Libreria", systemImage: "square.stack")
    }.accessibilityIdentifier("return-to-library")
  }

  @ToolbarContentBuilder
  private var navigationToolbar: some ToolbarContent {
    if model.showPlayer {
      ToolbarItem(placement: .cancellationAction) { backButton }
      ToolbarItem(placement: .platformTrailing) { libraryButton }
    }
  }

  #if os(iOS)
    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    private func duoToolbar(vertical: Bool) -> some ToolbarContent {
      if model.showPlayer {
        ToolbarItem(placement: .cancellationAction) { backButton }
          .axisBehavior(.verticalPreferred).visibilityPriority(.high)
        ToolbarItem(placement: .topBarTrailing) { libraryButton }
          .axisBehavior(.verticalPreferred)
        if vertical {
          ToolbarItemGroup(placement: .bottomBar) {
            Button {
              model.loadLyrics()
              expandedLyrics = true
            } label: {
              Label("Fonti e significato", systemImage: "quote.bubble")
            }.accessibilityIdentifier("toggle-lyrics")
            meaningButton
            Button { showQueue = true } label: {
              Label("Coda di riproduzione", systemImage: "music.note.list")
            }.accessibilityIdentifier("show-queue")
          }.axisBehavior(.verticalPreferred).visibilityPriority(.high)
          ToolbarItem(placement: .topBarPinnedTrailing) { optionsButton }
            .axisBehavior(.verticalPreferred).visibilityPriority(.high)
        }
      }
    }
  #endif

  private func toggleLyrics() {
    showLyrics.toggle()
    showVideo = false
    if showLyrics { model.loadLyrics() }
  }

  private func nowPlaying(expanded: Bool = false, verticalBar: Bool = false) -> some View {
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
          YTPlayerArtwork(url: song.artwork)
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
                    PlayerInfoContent().environmentObject(model).accessibilityHidden(expandedLyrics)
                  } else {
                    YTPlayerArtwork(url: song.artwork, fit: true)
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
                songHeading(song, expanded: expanded, verticalBar: verticalBar)
                AdaptedYTPlayerControls(player: player, reading: model.reading || model.busyMeaning)
                if !verticalBar {
                  HStack {
                    playerAction("Fonti e significato", icon: "quote.bubble", selected: showLyrics) {
                      if expanded { expandedLyrics = true } else { toggleLyrics() }
                    }.accessibilityIdentifier("toggle-lyrics")
                    Spacer()
                    #if os(macOS)
                      playerAction(
                        showVideo ? "Mostra copertina" : "Mostra video",
                        icon: showVideo ? "photo" : "play.rectangle", selected: showVideo
                      ) {
                        openVideo()
                        showLyrics = false
                      }.accessibilityIdentifier("toggle-video")
                      Spacer()
                    #endif
                    playerAction("Coda di riproduzione", icon: "music.note.list", selected: false) {
                      showQueue = true
                    }
                    .accessibilityIdentifier("show-queue")
                  }.padding(.horizontal, 22)
                }

              }.frame(width: column)
            }.padding(20).frame(maxWidth: .infinity)
          }
        }
      }.foregroundStyle(.white).tint(.white)
    }
  }

  private func songHeading(_ song: PlayerSong, expanded: Bool, verticalBar: Bool) -> some View {
    let identity = HStack(spacing: 12) {

      if showLyrics && !expanded {
        YTPlayerArtwork(url: song.artwork).frame(width: 48, height: 48).clipShape(
          RoundedRectangle(cornerRadius: 8))
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(song.title).font(.title2.bold()).lineLimit(2)
        Text(song.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65))
          .lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
    let actions = HStack(spacing: 12) {
      meaningButton
      optionsButton
    }.font(.title2).buttonStyle(.plain)
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        identity
        if !verticalBar { actions }
      }
      VStack(alignment: .leading, spacing: 8) {
        identity
        if !verticalBar { actions }
      }
    }
  }

  private var optionsButton: some View {
    Button { optionsSong = model.current } label: {
      Label("Opzioni brano", systemImage: "ellipsis").labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
    }.accessibilityLabel("Opzioni brano").accessibilityIdentifier("player-more-options")
  }

  private var meaningButton: some View {
    Button { model.explain() } label: {
      Label("Significato della canzone", systemImage: "lightbulb.max.fill")
        .labelStyle(.iconOnly).frame(width: 44, height: 44)
    }
      .accessibilityLabel("Significato della canzone").disabled(player.isLoading)
  }

  #if os(macOS)
    private func openVideo() {
      showVideo.toggle()
      showLyrics = false
    }
  #endif
  private func playerAction(
    _ label: String, icon: String, selected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.title2).frame(width: 52, height: 48)
        .background(selected ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 16))
    }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(selected ? "Attivo" : "")
  }
}

#if os(iOS)
  /// Read the edge inside NavigationStack, where the system supplies bar geometry.
  /// Using this environment keeps Split View and the inner portrait display native.
  @available(iOS 27.1, *)
  private struct PlayerBarLayout<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @ViewBuilder let content: (Bool) -> Content
    var body: some View { content(verticalEdge != nil) }
  }
#endif

struct AdaptedYTPlayerControls: View {
  @EnvironmentObject var model: ApplePlayerAdapter
  @ObservedObject var player: ApplePlayerAdapter
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
      VStack(spacing: 4) {
        Slider(
          value: Binding(
            get: { min(elapsed, max(duration, 1)) },
            set: { value in
              scrubTime = value
              // VoiceOver and accessibility adjustments don't start a touch-edit
              // session; apply their requested position immediately as well.
              if !scrubbing {
                player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
              }
            }),
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
          Label("Apple Music", systemImage: "waveform").font(.caption2).padding(.horizontal, 10)
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
        NativeMusicVolume().frame(height: 28).accessibilityLabel("Volume")
        Image(systemName: "speaker.wave.3.fill")
        #if os(iOS)
          AppleAudioOutputButtons()
        #endif
      }.font(.caption)

    }
  }
}

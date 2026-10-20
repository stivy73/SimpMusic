import AppKit
import SwiftUI

enum MacSection: String, CaseIterable, Identifiable {
  case home = "Home"
  case search = "Cerca"
  case library = "Libreria"
  case settings = "Impostazioni"
  var id: String { rawValue }
  var icon: String {
    switch self {
    case .home: "house.fill"
    case .search: "magnifyingglass"
    case .library: "square.stack.fill"
    case .settings: "gearshape.fill"
    }
  }
}

@MainActor
final class MacNavigation: ObservableObject {
  @Published var section: MacSection = .home
}

@main
struct NoteNarrateMacApp: App {
  @StateObject private var model = MusicModel()
  @StateObject private var library = LibraryModel()
  @StateObject private var navigation = MacNavigation()
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    // One music session and one web player, even when Settings is opened separately.
    Window("NoteNarrate", id: "main") {
      MacRootView().environmentObject(model).environmentObject(library)
        .environmentObject(navigation).tint(.cyan).preferredColorScheme(.dark)
        .frame(minWidth: 820, minHeight: 620)
    }.defaultSize(width: 1120, height: 780)
      .commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Riproduzione") {
          Button(model.player.playing ? "Pausa" : "Riproduci") {
            model.player.playing ? model.player.pause() : model.player.play()
          }.keyboardShortcut(.space, modifiers: .command)
            .disabled(
              model.current == nil || model.player.isLoading || model.busyMeaning || model.reading)
          Button("Brano precedente") { model.previousSong() }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(model.current == nil || model.busyMeaning || model.reading)
          Button("Brano successivo") { model.nextSong() }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(!model.hasNext || model.busyMeaning || model.reading)
          Divider()
          Button("Significato della canzone") {
            model.showPlayer = true
            model.explain()
          }.keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(model.current == nil || model.player.isLoading || model.busyMeaning)
          Button("Interrompi lettura") { model.stopMeaning() }
            .disabled(!model.reading && !model.busyMeaning)
        }
        CommandMenu("Navigazione") {
          Button("Mostra finestra") {
            openWindow(id: "main")
            // SwiftUI can activate an existing Window without restoring it from the Dock.
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })
              ?? NSApp.windows.first(where: { $0.title == "NoteNarrate" && !$0.isSheet })
            {
              window.deminiaturize(nil)
              window.makeKeyAndOrderFront(nil)
              NSApp.activate()
            }
          }.keyboardShortcut("0")
          Button("Home") { navigate(.home) }.keyboardShortcut("1")
          Button("Cerca") { navigate(.search) }.keyboardShortcut("2")
          Button("Libreria") { navigate(.library) }.keyboardShortcut("3")
          Button("Player") { model.showPlayer = true }.keyboardShortcut("4")
            .disabled(model.current == nil)
        }
      }
    Settings {
      SettingsView().environmentObject(model).environmentObject(library)
        .frame(width: 560, height: 650).tint(.cyan).preferredColorScheme(.dark)
    }
  }

  private func navigate(_ section: MacSection) {
    model.minimizePlayer()
    navigation.section = section
  }
}

struct MacRootView: View {
  @EnvironmentObject private var model: MusicModel
  @EnvironmentObject private var library: LibraryModel
  @EnvironmentObject private var navigation: MacNavigation
  @StateObject private var home = HomeModel()

  var body: some View {
    NavigationSplitView {
      List(MacSection.allCases, selection: $navigation.section) { section in
        Label(section.rawValue, systemImage: section.icon).tag(section)
          .accessibilityIdentifier("mac-section-\(section.id)")
      }.navigationTitle("NoteNarrate").navigationSplitViewColumnWidth(
        min: 170, ideal: 190, max: 240)
    } detail: {
      ZStack {
        NavigationStack {
          switch navigation.section {
          case .home:
            HomeView(
              onSearch: { navigation.section = .search },
              onSettings: { navigation.section = .settings }, home: home)
          case .search: MacSearchView()
          case .library: LibraryView(library: library).navigationTitle("Libreria")
          case .settings: SettingsView().navigationTitle("Impostazioni")
          }
        }.opacity(model.showPlayer ? 0 : 1)
          .allowsHitTesting(!model.showPlayer).accessibilityHidden(model.showPlayer)
        if model.current != nil {
          PlayerScreen(player: model.player, onLibrary: { navigation.section = .library })
            .opacity(model.showPlayer ? 1 : 0)
            .allowsHitTesting(model.showPlayer).accessibilityHidden(!model.showPlayer)
            .animation(.easeInOut(duration: 0.2), value: model.showPlayer)
        }
      }.safeAreaInset(edge: .bottom, spacing: 0) {
        if !model.showPlayer { MiniPlayer() }
      }
    }
    .onChange(of: navigation.section) { _, _ in model.minimizePlayer() }
    .sheet(isPresented: $library.showLogin) {
      YouTubeLoginScreen(library: library).frame(minWidth: 780, minHeight: 640)
    }
  }

}

struct MacSearchView: View {
  @EnvironmentObject private var model: MusicModel
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        TextField("Brano o artista", text: $model.query).textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("mac-search-field")
          .onSubmit { model.search() }
        Button("Cerca", systemImage: "magnifyingglass") { model.search() }
          .accessibilityIdentifier("mac-search-submit")
      }.padding()
      if model.searching {
        ProgressView("Ricerca su YouTube Music…").frame(maxWidth: .infinity, maxHeight: .infinity)
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
  }
}

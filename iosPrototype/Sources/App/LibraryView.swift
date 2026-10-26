import SwiftUI
import WebKit
import YouTubeSDK

extension LibraryModel {
  convenience init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-reset-collection-preferences") {
        for key in ["albums", "artists", "playlists", "songs", "likes", "local", "offline"] {
          UserDefaults.standard.removeObject(forKey: "collectionPresentation." + key)
        }
      }
      if ProcessInfo.processInfo.arguments.contains("--test-remote-library") {
        self.init(
          session: YouTubeSession(
            cookies: "SAPISID=fixture", identity: "library-test", clientVersion: "test"),
          save: { _ in },
          fetch: { _ in
            if ProcessInfo.processInfo.arguments.contains("--test-collection-presentation") {
              return (0..<26).reversed().map { n in
                LibraryAlbum(
                  id: "MPREcollection-\(n)", title: String(UnicodeScalar(65 + n)!) + " raccolta",
                  artist: "Artista \(25-n)", artwork: nil)
              }
            }
            return [
              LibraryAlbum(
                id: "MPREfixture", title: "Album di prova", artist: "Artista di prova", artwork: nil
              )
            ]
          },
          fetchCollection: { _, kind in
            let id: String
            let title: String
            switch kind {
            case .songs: (id, title) = ("saved-fixture", "Brano salvato di prova")
            case .likes: (id, title) = ("liked-fixture", "Brano piaciuto di prova")
            case .playlists: (id, title) = ("VLfixture", "Playlist di prova")
            case .artists: (id, title) = ("UCfixture", "Artista seguito di prova")
            }
            return [
              DiscoveryItem(
                kind: kind.itemKind, mediaId: id, title: title, subtitle: "Account di prova",
                artwork: nil)
            ]
          },
          rateSong: { _, _, _ in
            if ProcessInfo.processInfo.arguments.contains("--test-like-failure") {
              throw LibraryError.http(403)
            }
          }, followArtist: { _, _, _ in })
        return
      }
    #endif
    let stored = SecureStore.read("youtube-session").data(using: .utf8)
      .flatMap { try? JSONDecoder().decode(YouTubeSession.self, from: $0) }
    self.init(
      session: stored,
      save: { session in
        let value =
          try session.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? ""
        try SecureStore.save(value, as: "youtube-session")
      }, fetch: { session in try await YouTubeLibrary(session: session).albums() })
  }
}

private enum LibrarySection: String, CaseIterable, Identifiable {
  case albums = "Album"
  case songs = "Brani salvati"
  case likes = "Mi piace"
  case playlists = "Playlist"
  case artists = "Artisti seguiti"
  case local = "Preferiti locali"
  case offline = "Download e offline"
  var id: String { rawValue }
  var remote: RemoteLibraryKind? {
    switch self {
    case .songs: .songs
    case .likes: .likes
    case .playlists: .playlists
    case .artists: .artists
    default: nil
    }
  }
}

struct LibraryView: View {
  @EnvironmentObject var model: MusicModel
  @ObservedObject var library: LibraryModel
  @State private var section = LibrarySection.albums
  @State private var createPlaylist = false
  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(LibrarySection.allCases) { value in
            Button {
              section = value
            } label: {
              Text(value.rawValue).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundStyle(section == value ? Color.black : Color.primary)
                .background(section == value ? Color.cyan : Color.gray.opacity(0.2), in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("library-section-" + value.name)
              .accessibilityAddTraits(section == value ? .isSelected : [])
          }
        }.padding()
      }
      if section == .offline {
        OfflineScreen(downloads: model.downloads)
      } else if section == .local {
        if model.favorites.isEmpty {
          ContentUnavailableView("Nessun preferito locale", systemImage: "heart")
        } else {
          LibrarySongCollection(songs: model.favorites, key: "local")
        }
      } else if library.session == nil {
        ContentUnavailableView {
          Label("La tua libreria YouTube Music", systemImage: "person.crop.circle")
        } description: {
          Text("Accedi per sincronizzare album, brani, Mi piace, playlist e artisti seguiti.")
        } actions: {
          Button("Accedi a YouTube Music") { library.showLogin = true }.buttonStyle(
            .borderedProminent)
        }
      } else if let remote = section.remote {
        RemoteLibraryView(library: library, kind: remote).id(remote)
      } else {
        albumContent
      }
    }.navigationTitle("Libreria")
      .sheet(isPresented: $createPlaylist) { CreatePlaylistSheet() }
      .toolbar {
        Button {
          model.externalRoute = .received
        } label: {
          Label("Ricevuti", systemImage: "tray.and.arrow.down")
        }.accessibilityIdentifier("library-received")
        Menu {
          ForEach(LibrarySection.allCases) { value in
            Button(value.rawValue) { section = value }.accessibilityIdentifier(
              "library-menu-" + value.name)
          }
        } label: {
          Label("Raccolte", systemImage: "square.stack")
        }
        .accessibilityIdentifier("library-section-menu")
        if library.session != nil && section == .playlists {
          Button {
            createPlaylist = true
          } label: {
            Label("Nuova playlist", systemImage: "plus")
          }
        }
        if library.session != nil && section != .local && section != .offline {
          Button {
            if let remote = section.remote {
              Task { await library.load(remote, force: true) }
            } else {
              library.refresh()
            }
          } label: {
            Label("Aggiorna", systemImage: "arrow.clockwise")
          }
          .disabled(section.remote.map { library.state($0).loading } ?? library.loading)
        }
      }
      .task(id: library.session) {
        if library.session != nil && library.albums.isEmpty && !library.loading {
          library.refresh()
        }
      }
  }

  @ViewBuilder private var albumContent: some View {
    if library.loading {
      ProgressView("Carico tutti gli album…").frame(maxHeight: .infinity)
    } else if let error = library.error {
      ContentUnavailableView {
        Label("Libreria non disponibile", systemImage: "exclamationmark.triangle")
      } description: {
        Text(error)
      } actions: {
        Button("Riprova") { library.refresh() }
        Button("Accedi nuovamente") { library.showLogin = true }
      }
    } else {
      VStack(spacing: 0) {
        if library.albums.isEmpty {
          ContentUnavailableView("Nessun album salvato", systemImage: "opticaldisc")
        } else {
          Text("\(library.albums.count) album").font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("library-album-count")
          LibraryCollection(items: library.albums, key: "albums", title: \.title, artist: \.artist)
          { album, layout, _ in
            NavigationLink {
              AlbumView(album: album, identity: library.session?.identity).id(
                library.session?.identity)
            } label: {
              LibraryItemLabel(
                title: album.title, subtitle: album.artist, artwork: album.artwork, layout: layout)
            }.buttonStyle(.plain).accessibilityIdentifier("album-" + album.id)
          }
        }
      }.refreshable { await library.reload() }
    }
  }
}

extension LibrarySection {
  fileprivate var name: String {
    remote?.rawValue ?? (self == .albums ? "albums" : self == .offline ? "offline" : "local")
  }
}

private struct RemoteLibraryView: View {
  @ObservedObject var library: LibraryModel
  let kind: RemoteLibraryKind
  private var state: RemoteLibraryState { library.state(kind) }
  var body: some View {
    VStack(spacing: 12) {
      if let error = state.error {
        VStack(spacing: 8) {
          Text(error).font(.callout).foregroundStyle(.orange)
          Button("Riprova") { Task { await library.load(kind, force: true) } }
          Button("Accedi nuovamente") { library.showLogin = true }
        }.padding()
      }
      if state.loading {
        ProgressView("Sincronizzo \(kind.title.lowercased())…")
      }
      if state.loaded {
        Text("\(state.items.count) · YouTube Music").font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("library-remote-count")
      }
      if state.items.isEmpty && state.loaded && !state.loading && state.error == nil {
        ContentUnavailableView("Nessun elemento nella raccolta", systemImage: "music.note.list")
      } else if kind == .songs || kind == .likes {
        LibrarySongCollection(songs: state.items.map(Song.init), key: kind.rawValue)
      } else {
        LibraryCollection(
          items: state.items, key: kind.rawValue, title: \.title, artist: \.subtitle
        ) { item, layout, _ in
          if let target = item.target {
            NavigationLink {
              if kind == .playlists {
                RemotePlaylistView(playlist: item)
              } else {
                HomeBrowseView(title: item.title, target: target)
              }
            } label: {
              LibraryItemLabel(
                title: item.title, subtitle: item.subtitle, artwork: item.artwork, layout: layout,
                circular: kind == .artists)
            }.buttonStyle(.plain).accessibilityIdentifier("library-item-" + item.mediaId)
          }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .refreshable { await library.load(kind, force: true) }
      .task(id: library.session) { await library.load(kind) }
  }
}

struct AlbumView: View {
  let album: LibraryAlbum
  let identity: String?
  @EnvironmentObject var library: LibraryModel
  @Environment(\.dismiss) private var dismiss
  @State private var songs: [Song] = []
  @State private var loading = true
  @State private var error: String?
  var body: some View {
    Group {
      if loading {
        ProgressView("Carico l'album…")
      } else if let error {
        ContentUnavailableView {
          Label("Album non disponibile", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Riprova") { Task { await load() } }
        }
      } else if songs.isEmpty {
        ContentUnavailableView("Nessuna traccia disponibile", systemImage: "music.note")
      } else {
        SongList(songs: songs)
      }
    }.navigationTitle(album.title)
      .task { await load() }
      .onChange(of: library.session?.identity) { _, new in if new != identity { dismiss() } }
  }
  private func load() async {
    loading = true
    error = nil
    do {
      let result = try await YouTubeMusicClient().getAlbum(browseId: album.id)
      try Task.checkCancellation()
      songs = result.map { Song($0, albumArtwork: album.artwork) }
      loading = false
    } catch is CancellationError {} catch {
      self.error = "Impossibile caricare le tracce. Riprova."
      loading = false
    }
  }
}

/// Separate, ephemeral web session: credentials are entered only on Google's own pages.
/// Explicit confirmation allows selecting the intended YouTube/brand account before saving.
struct YouTubeLoginScreen: View {
  @ObservedObject var library: LibraryModel
  @StateObject private var browser = YouTubeLoginBrowser()
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      VStack(spacing: 8) {
        Text(
          "Accedi su YouTube Music e scegli il tuo account dal profilo, poi tocca Usa questo account."
        )
        .font(.footnote).padding(.horizontal)
        YouTubeLoginWebView(browser: browser)
        if browser.loading { ProgressView("Caricamento YouTube Music…") }
        Text(browser.ready ? "Scegli il tuo account su YouTube Music." : "Attendo YouTube Music…")
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("login-browser-status")
          .accessibilityValue(browser.ready ? "ready" : "loading")
        if let error = browser.error {
          Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal)
          Button("Ricarica pagina") { browser.reload() }
        }
        Button("Usa questo account") {
          Task {
            if let session = await browser.capture() { library.connect(session) }
          }
        }.buttonStyle(.borderedProminent).padding().disabled(browser.checking || !browser.ready)
      }.navigationTitle("YouTube Music").inlineNavigationTitle()
        .toolbar { Button("Annulla") { dismiss() } }
    }
  }
}

@MainActor
final class YouTubeLoginBrowser: NSObject, ObservableObject, WKNavigationDelegate {
  @Published var error: String?
  @Published var checking = false
  @Published var loading = true
  @Published var ready = false
  let web: WKWebView
  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.preferredContentMode = .desktop
    web = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    web.navigationDelegate = self
    // Default WKWebView omits Safari's identity and receives YT Music's unsupported-browser page.
    // Use a Safari/WebKit desktop identity only for login, not for the embedded video player.
    web.customUserAgent =
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    web.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
  }
  func reload() {
    error = nil
    ready = false
    loading = true
    web.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    loading = true
    ready = false
    error = nil
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    loading = false
    guard webView.url?.host == "music.youtube.com" else { return }
    Task {
      let supported =
        try? await webView.evaluateJavaScript(
          "Boolean(document.querySelector('ytmusic-app') && window.ytcfg && ytcfg.get('INNERTUBE_CLIENT_VERSION'))"
        ) as? Bool
      guard webView.url?.host == "music.youtube.com", !loading else { return }
      ready = supported == true
      if !ready {
        error =
          "YouTube Music non ha caricato la pagina di accesso. Ricarica la pagina per riprovare."
      }
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    loading = false
    ready = false
    self.error = "Pagina non disponibile. Controlla la connessione."
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    if (error as NSError).code != NSURLErrorCancelled {
      loading = false
      ready = false
      self.error = "Impossibile aprire YouTube Music. Riprova."
    }
  }
  func capture() async -> YouTubeSession? {
    checking = true
    error = nil
    defer { checking = false }
    do {
      guard web.url?.scheme == "https", web.url?.host == "music.youtube.com" else {
        throw LibraryError.authentication
      }
      let script = """
        JSON.stringify({loggedIn:ytcfg.get('LOGGED_IN'), index:String(ytcfg.get('SESSION_INDEX') || 0),
        delegated:ytcfg.get('DELEGATED_SESSION_ID') || null, identity:ytcfg.get('DATASYNC_ID') || '',
        version:ytcfg.get('INNERTUBE_CLIENT_VERSION') || ''})
        """
      guard let json = try await web.evaluateJavaScript(script) as? String,
        let data = json.data(using: .utf8),
        let config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        config["loggedIn"] as? Bool == true,
        let version = config["version"] as? String, !version.isEmpty
      else { throw LibraryError.authentication }
      let cookies = await web.configuration.websiteDataStore.httpCookieStore.allCookies()
      let relevant = cookies.filter {
        let host = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
        return (host == "youtube.com" || host == "music.youtube.com")
          && ($0.expiresDate.map { $0 > Date() } ?? true)
      }
      let value = YouTubeSession(
        cookies: relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
        accountIndex: config["index"] as? String ?? "0",
        delegatedID: config["delegated"] as? String,
        identity: (config["identity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
          ?? UUID().uuidString,
        clientVersion: version)
      _ = try value.authorization()
      return value
    } catch {
      self.error = "Completa l'accesso e torna su music.youtube.com prima di confermare."
      return nil
    }
  }
}

struct YouTubeLoginWebView: PlatformWebViewRepresentable {
  let browser: YouTubeLoginBrowser
  #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { browser.web }
    func updateNSView(_ view: WKWebView, context: Context) {}
  #else
    func makeUIView(context: Context) -> WKWebView { browser.web }
    func updateUIView(_ view: WKWebView, context: Context) {}
  #endif
}

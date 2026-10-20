import SwiftUI
import WebKit
import YouTubeSDK

extension LibraryModel {
  convenience init() {
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

struct LibraryView: View {
  @EnvironmentObject var model: MusicModel
  @ObservedObject var library: LibraryModel
  @State private var local = false
  var body: some View {
    VStack {
      Picker("Raccolta", selection: $local) {
        Text("Album YouTube Music").tag(false)
        Text("Preferiti locali").tag(true)
      }.pickerStyle(.segmented).padding(.horizontal)
      if local {
        if model.favorites.isEmpty {
          ContentUnavailableView("Nessun preferito locale", systemImage: "heart")
        } else {
          SongList(songs: model.favorites)
        }
      } else if library.session == nil {
        ContentUnavailableView {
          Label("La tua libreria YouTube Music", systemImage: "person.crop.circle")
        } description: {
          Text("Accedi per visualizzare gli album salvati nel tuo account.")
        } actions: {
          Button("Accedi a YouTube Music") { library.showLogin = true }.buttonStyle(
            .borderedProminent)
        }
      } else if library.loading {
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
        ScrollView {
          if library.albums.isEmpty {
            ContentUnavailableView(
              "Nessun album salvato", systemImage: "opticaldisc",
              description: Text("Gli album salvati in YouTube Music compariranno qui."))
          } else {
            Text("\(library.albums.count) album")
              .font(.caption).foregroundStyle(.secondary)
              .accessibilityIdentifier("library-album-count")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 22) {
              ForEach(library.albums) { album in
                NavigationLink {
                  AlbumView(album: album, identity: library.session?.identity)
                    .id(library.session?.identity)
                } label: {
                  VStack(alignment: .leading, spacing: 8) {
                    Artwork(url: album.artwork).aspectRatio(1, contentMode: .fit)
                      .clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(album.title).fontWeight(.semibold).lineLimit(2)
                    Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                  }.foregroundStyle(.primary)
                }.accessibilityIdentifier("album-\(album.id)")
              }
            }.padding()
          }
        }.refreshable { await library.reload() }
      }
    }.navigationTitle("Libreria")
      .toolbar {
        if library.session != nil {
          Button {
            library.refresh()
          } label: {
            Label("Aggiorna", systemImage: "arrow.clockwise")
          }
          .disabled(library.loading)
        }
      }
      .task { if library.session != nil && library.albums.isEmpty { library.refresh() } }
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

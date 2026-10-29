#if os(iOS)
  import CarPlay
  import Combine
  import UIKit
  @preconcurrency import Intents

  @MainActor
  final class CarPlayAppDelegate: NSObject, UIApplicationDelegate {
    func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      ReleaseNotifications.register()
      _ = AppleAppSession.shared
      return true
    }
    func application(
      _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
      completionHandler: @escaping () -> Void
    ) {
      if identifier == MusicDownloads.identifier {
        AppleAppSession.shared.music.downloads.backgroundCompletion = completionHandler
      } else {
        completionHandler()
      }
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
      if intent is INPlayMediaIntent || intent is INSearchForMediaIntent {
        return CarPlayMediaIntentHandler()
      }
      return nil
    }

    func application(
      _ application: UIApplication, handle intent: INIntent,
      completionHandler: @escaping (INIntentResponse) -> Void
    ) {
      Task { @MainActor in
        let handler = CarPlayMediaIntentHandler()
        if let play = intent as? INPlayMediaIntent {
          completionHandler(await handler.handle(intent: play))
        } else if let search = intent as? INSearchForMediaIntent {
          completionHandler(await handler.handle(intent: search))
        }
      }
    }

    func application(
      _ application: UIApplication,
      configurationForConnecting connectingSceneSession: UISceneSession,
      options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
      if connectingSceneSession.role == .carTemplateApplication {
        let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
        config.sceneClass = CPTemplateApplicationScene.self
        config.delegateClass = CarPlayScene.self
        return config
      }
      // Returning SwiftUI's already wrapped delegate recurses into AppSceneDelegate.
      return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
  }

  /// Native large cover rows and track lists; no lyrics, interpretation text or video on the vehicle display.
  @MainActor
  final class CarPlayScene: UIResponder, CPTemplateApplicationSceneDelegate,
    CPNowPlayingTemplateObserver
  {
    private enum Layout { case covers, tracks }
    private struct Tile {
      let id: String
      let title: String
      var detail: String? = nil
      var artwork: URL? = nil
      var videoID: String? = nil
      var symbol = "music.note"
      var action: (@MainActor () -> Void)? = nil
      var key: String {
        "\(id):\(title):\(detail ?? ""):\(artwork?.absoluteString ?? ""):\(videoID ?? "")"
      }
    }
    private final class ContentState: NSObject {
      let tiles: [Tile]
      let page: CarPlayPage
      let layout: Layout
      var imageUpdates: [Int: (UIImage) -> Void] = [:]
      var images: [UIImage]
      var loads: [Task<Void, Never>] = []
      let refresh: (@MainActor () -> Void)?
      init(tiles: [Tile], page: CarPlayPage, layout: Layout, refresh: (@MainActor () -> Void)?) {
        self.tiles = tiles
        self.page = page
        self.layout = layout
        self.refresh = refresh
        images = page.range.map { UIImage(systemName: tiles[$0].symbol)! }
      }
    }
    private let app = AppleAppSession.shared
    private var controller: CPInterfaceController?
    private var subscriptions = Set<AnyCancellable>()
    private var tasks: [Task<Void, Never>] = []
    private var grids = NSMapTable<CPListTemplate, ContentState>(
      keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var detailRevision = UUID()
    private var meaningAlert: CPAlertTemplate?
    private var meaningStarted = false
    private var meaningButtonState: String?
    private var account: YouTubeSession?
    private let home = CPListTemplate(title: "Home", sections: [])
    private let albums = CPListTemplate(title: "Album", sections: [])
    private let favorites = CPListTemplate(title: "Preferiti", sections: [])
    private let search = CPListTemplate(title: "Cerca", sections: [])
    private var searchQuery = ""
    private var searchFilter = MusicSearchFilter.songs
    private var searchTask: Task<Void, Never>?
    private var searchRevision = UUID()
    private var searchItems: [DiscoveryItem] = []
    private var searchRenderedState = ""
    private var searchMessage = "Chiedi a Siri una canzone, un artista o un album in NoteNarrate"
    private var voiceQueryID: UUID?
    private let queueTemplate = CPListTemplate(title: "Coda", sections: [])
    private var queueOffset = 0

    func templateApplicationScene(
      _ templateApplicationScene: CPTemplateApplicationScene,
      didConnect interfaceController: CPInterfaceController
    ) {
      controller = interfaceController
      home.tabTitle = "Home"
      home.tabImage = UIImage(systemName: "house.fill")
      albums.tabTitle = "Album"
      albums.tabImage = UIImage(systemName: "square.stack.fill")
      favorites.tabTitle = "Preferiti"
      favorites.tabImage = UIImage(systemName: "heart.fill")
      search.assistantCellConfiguration = CPAssistantCellConfiguration(
        position: .top, visibility: .always, assistantAction: .playMedia)
      search.tabTitle = "Cerca"
      search.tabImage = UIImage(systemName: "magnifyingglass")
      interfaceController.setRootTemplate(
        CPTabBarTemplate(templates: [home, albums, favorites, search]),
        animated: false, completion: { _, _ in })
      CPNowPlayingTemplate.shared.add(self)
      configureNowPlaying()
      app.library.$session.sink { [weak self] session in
        Task { @MainActor [weak self] in await self?.configureAccount(session) }
      }.store(in: &subscriptions)
      app.library.objectWillChange.merge(with: app.home.objectWillChange)
        .merge(with: app.music.objectWillChange)
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] _ in
          self?.render()
          self?.updateMeaning()
        }.store(in: &subscriptions)
      app.music.player.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.configureNowPlaying() }.store(in: &subscriptions)
      render()
    }

    func templateApplicationScene(
      _ templateApplicationScene: CPTemplateApplicationScene,
      didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
      CPNowPlayingTemplate.shared.remove(self)
      if meaningAlert != nil { app.music.stopMeaning(resume: true) }
      searchTask?.cancel()
      searchRevision = UUID()
      subscriptions.removeAll()
      for task in tasks { task.cancel() }
      tasks = []
      for state in grids.objectEnumerator()?.allObjects as? [ContentState] ?? [] {
        for load in state.loads { load.cancel() }
      }
      grids.removeAllObjects()
      controller = nil
      meaningAlert = nil
      meaningButtonState = nil
      detailRevision = UUID()
    }

    private func configureAccount(_ value: YouTubeSession?) async {
      guard controller != nil else { return }
      if account != value {
        account = value
        detailRevision = UUID()
        for task in tasks { task.cancel() }
        tasks = []
        searchTask?.cancel()
        searchRevision = UUID()
        searchItems = []
        searchQuery = ""
        voiceQueryID = nil
        grids.removeAllObjects()
        controller?.popToRootTemplate(animated: false, completion: { _, _ in })
      }
      await app.home.configure(session: value)
      if value != nil && app.library.albums.isEmpty && !app.library.loading {
        app.library.refresh()
      }
      render()
    }

    private func status(_ title: String) -> Tile {
      Tile(id: "status:" + title, title: title, symbol: "info.circle")
    }

    private func render() {
      guard controller != nil else { return }
      var shelves = app.home.shelves.map { shelf in
        Tile(id: shelf.id, title: shelf.title, artwork: shelf.items.first?.artwork) { [weak self] in
          self?.display(shelf.items, title: shelf.title)
        }
      }
      if let error = app.home.error { shelves.insert(status(error), at: 0) }
      if shelves.isEmpty { shelves = [status(app.home.loading ? "Caricamento…" : "Home vuota")] }
      if app.home.continuation != nil {
        shelves.append(
          Tile(id: "more-home", title: "Altre sezioni", symbol: "plus") { [weak self] in
            guard let self else { return }
            self.tasks.append(Task { await self.app.home.loadMore() })
          })
      }
      shelves.insert(
        Tile(id: "moods", title: "Stati d’animo", symbol: "music.note.list") { [weak self] in
          self?.displayFilters()
        }, at: 0)
      if !app.home.categories.isEmpty {
        shelves.insert(
          Tile(id: "genres", title: "Generi musicali", symbol: "guitars") { [weak self] in
            self?.displayCategories()
          }, at: 0)
      }
      setTiles(shelves, in: home) { [weak self] in
        guard let self else { return }
        self.tasks.append(Task { await self.app.home.refresh() })
      }
      if app.library.session == nil {
        setTiles([status("Accedi a YouTube Music sul telefono")], in: albums)
      } else if let error = app.library.error {
        setTiles([status(error)], in: albums) { [weak self] in self?.app.library.refresh() }
      } else {
        let entries = app.library.albums.map { album in
          Tile(id: album.id, title: album.title, detail: album.artist, artwork: album.artwork) {
            [weak self] in
            self?.browse(
              BrowseTarget(browseId: album.id), title: album.title,
              albumArtwork: album.artwork, albumArtist: album.artist)
          }
        }
        setTiles(
          entries.isEmpty
            ? [status(app.library.loading ? "Caricamento…" : "Nessun album salvato")] : entries,
          in: albums
        ) { [weak self] in self?.app.library.refresh() }
      }
      var preferred: [Tile] = []
      if app.library.session != nil {
        preferred.insert(
          Tile(
            id: "yt-favorites", title: "Brani piaciuti YouTube Music",
            symbol: "hand.thumbsup.fill"
          ) { [weak self] in
            self?.browse(BrowseTarget(browseId: "VLLM"), title: "Brani piaciuti")
          }, at: 0)
      }
      preferred.insert(
        Tile(
          id: "offline", title: "Download e offline",
          detail: "\(app.music.downloads.library.ready.count) brani",
          artwork: app.music.downloads.library.ready.first?.track.artwork,
          symbol: "arrow.down.circle.fill"
        ) { [weak self] in
          guard let self else { return }
          self.displaySongs(
            self.app.music.downloads.library.ready.map(\.track), title: "Download e offline")
        }, at: 0)
      setTiles(preferred, in: favorites)
      if let voice = app.music.carPlayVoiceQuery, voice.id != voiceQueryID {
        voiceQueryID = voice.id
        runSearch(voice.query, filter: voice.filter)
        (controller?.rootTemplate as? CPTabBarTemplate)?.select(search)
      }
      renderSearch()
      renderQueue()
      configureNowPlaying()
    }

    private func renderSearch() {
      let state =
        "\(searchQuery)|\(searchFilter.rawValue)|\(searchMessage)|\(searchItems.map(\.id).joined(separator: ","))"
      guard state != searchRenderedState else { return }
      searchRenderedState = state
      let filters = MusicSearchFilter.carPlay.map { filter in
        let row = CPListItem(
          text: filter.rawValue,
          detailText: filter == searchFilter ? "Selezionato" : nil,
          image: UIImage(
            systemName: filter == .songs
              ? "music.note" : filter == .artists ? "person.fill" : "square.stack.fill"))
        row.handler = { [weak self] _, done in
          done()
          guard let self, !self.searchQuery.isEmpty else { return }
          self.runSearch(self.searchQuery, filter: filter)
        }
        row.isEnabled = !searchQuery.isEmpty
        return row
      }
      let songs = searchItems.filter { $0.kind == .song }.map(Song.init)
      let results = searchItems.prefix(50).map { item in
        let row = CPListItem(text: item.title, detailText: item.subtitle)
        row.handler = { [weak self] _, done in
          done()
          guard let self else { return }
          if item.kind == .song {
            self.play(Song(item), queue: songs)
          } else if let target = item.target {
            self.browse(
              target, title: item.title,
              albumArtwork: item.kind == .album ? item.artwork : nil,
              albumArtist: item.kind == .album ? item.subtitle : nil)
          }
        }
        return row
      }
      let empty = CPListItem(text: searchMessage, detailText: nil)
      empty.isEnabled = false
      search.updateSections([
        CPListSection(
          items: filters, header: searchQuery.isEmpty ? "Filtra per" : searchQuery,
          sectionIndexTitle: nil),
        CPListSection(items: results.isEmpty ? [empty] : results),
      ])
    }

    private func runSearch(_ query: String, filter: MusicSearchFilter) {
      searchTask?.cancel()
      let token = UUID()
      searchRevision = token
      searchQuery = query
      searchFilter = filter
      searchItems = []
      searchMessage = "Ricerca in corso…"
      renderSearch()
      let session = app.library.session
      searchTask = Task { [weak self] in
        do {
          try await Task.sleep(for: .milliseconds(400))
          let items = try await HomeDiscovery(session: session).search(query: query, filter: filter)
          try Task.checkCancellation()
          guard let self, self.searchRevision == token, self.controller != nil else { return }
          self.searchItems = items
          self.searchMessage = "Nessun risultato"
          self.renderSearch()
        } catch {
          guard let self, !Task.isCancelled, self.searchRevision == token else { return }
          self.searchMessage = "Ricerca non disponibile. Seleziona un filtro per riprovare."
          self.renderSearch()
        }
      }
    }

    private func openCurrentContext(_ filter: MusicSearchFilter) {
      guard let song = app.music.current else { return }
      if filter == .artists, let artistID = song.artistBrowseID {
        browse(BrowseTarget(browseId: artistID), title: song.artist)
        return
      }
      if filter == .albums, let albumID = song.albumBrowseID {
        browse(
          BrowseTarget(browseId: albumID), title: "Album", albumArtwork: song.artwork,
          albumArtist: song.artist)
        return
      }
      let query =
        filter == .artists ? song.artist : "\(song.albumTitle ?? song.title) \(song.artist)"
      let loading = CPListTemplate(title: filter == .artists ? "Artista" : "Album", sections: [])
      setTiles([status("Caricamento…")], in: loading)
      controller?.pushTemplate(loading, animated: true, completion: { _, _ in })
      let expected = detailRevision
      let account = app.library.session
      tasks.append(
        Task { [weak self] in
          do {
            let items = try await HomeDiscovery(session: account).search(
              query: query, filter: filter)
            try Task.checkCancellation()
            guard let self, self.detailRevision == expected, self.controller != nil else { return }
            self.setTiles(
              items.isEmpty ? [self.status("Nessun risultato")] : self.tiles(items), in: loading)
          } catch {
            guard let self, !Task.isCancelled, self.detailRevision == expected else { return }
            self.setTiles([self.status("Contenuto non disponibile")], in: loading)
          }
        })
    }

    #if DEBUG
      /// Exercises real CPListItem page handlers without needing a connected car display.
      func verifyAlbumPageHandlers() -> String {
        let entries = (0..<25).map { n in
          Tile(id: "qa-\(n)", title: "Album \(n)", artwork: URL(string: "file:///qa-cover")) {}
        }
        setTiles(entries, in: albums)
        var visited: [Int] = []
        var pages = 0
        var completed = true
        while let state = grids.object(forKey: albums), pages < 10 {
          pages += 1
          visited += state.page.range
          guard state.page.next != nil else { break }
          guard let next = albums.sections.flatMap(\.items).compactMap({ $0 as? CPListItem })
            .first(where: { $0.text == "Altri album" }), let handler = next.handler else {
            return "missing-footer"
          }
          var done = false
          handler(next) { done = true }
          completed = completed && done
        }
        guard let back = albums.sections.flatMap(\.items).compactMap({ $0 as? CPListItem })
          .first(where: { $0.text == "Pagina precedente" }), let handler = back.handler else {
          return "missing-back"
        }
        handler(back) {}
        let previous = grids.object(forKey: albums)?.page.range == 12..<24
        return "\(visited == Array(0..<25)):\(pages):\(previous):\(completed)"
      }
    #endif

    private func sections(_ state: ContentState, in grid: CPListTemplate,
      leadingButtons: [CPBarButton]) -> [CPListSection] {
      var rows: [CPListTemplateItem] = []
      var index = 0
      let count = state.page.range.count
      while index < count {
        let position = state.page.range.lowerBound + index
        let tile = state.tiles[position]
        if state.layout == .tracks || tile.action == nil
          || (tile.artwork == nil && tile.videoID == nil)
        {
          let title =
            state.layout == .tracks && tile.videoID != nil
            ? "\(position + 1). \(tile.title)" : tile.title
          let row = CPListItem(text: title, detailText: tile.detail, image: state.images[index])
          row.isEnabled = tile.action != nil
          row.handler = { _, done in
            done()
            tile.action?()
          }
          state.imageUpdates[index] = { [weak row] image in row?.setImage(image) }
          rows.append(row)
          index += 1
          continue
        }
        // Album covers are square artwork, not portrait cards with cropped sides.
        let first = index
        var positions: [Int] = []
        let rowLimit: Int
        if #available(iOS 26.0, *) { rowLimit = Int(CPMaximumNumberOfGridImages) }
        else { rowLimit = 2 }
        while index < count && positions.count < rowLimit {
          let entry = state.tiles[state.page.range.lowerBound + index]
          guard entry.action != nil, entry.artwork != nil || entry.videoID != nil else { break }
          positions.append(index)
          index += 1
        }
        guard !positions.isEmpty else { break }
        let row: CPListImageRowItem
        if #available(iOS 26.0, *) {
          let elements = positions.map { local in
            let entry = state.tiles[state.page.range.lowerBound + local]
            let card = CPListImageRowItemRowElement(
              image: state.images[local], title: entry.title, subtitle: entry.detail)
            state.imageUpdates[local] = { [weak card] image in card?.image = image }
            return card
          }
          row = CPListImageRowItem(text: nil, elements: elements, allowsMultipleLines: true)
        } else {
          if #available(iOS 17.4, *) {
            row = CPListImageRowItem(
              text: "", images: positions.map { state.images[$0] },
              imageTitles: positions.map { state.tiles[state.page.range.lowerBound + $0].title })
          } else {
            row = CPListImageRowItem(
              text: positions.map { state.tiles[state.page.range.lowerBound + $0].title }.joined(
                separator: " · "), images: positions.map { state.images[$0] })
          }
          for local in positions {
            state.imageUpdates[local] = { [weak row, weak state] _ in
              guard let row, let state else { return }
              row.update(positions.map { state.images[$0] })
            }
          }
        }
        row.listImageRowHandler = { [weak state] _, selected, done in
          done()
          guard let state, selected >= 0, selected < positions.count else { return }
          state.tiles[state.page.range.lowerBound + first + selected].action?()
        }
        rows.append(row)
      }
      // Root tabs hide navigation-bar page controls. Keep navigation in the list
      // itself so the twelfth album can never become an inaccessible dead end.
      for (offset, title, symbol) in [
        (state.page.previous, "Pagina precedente", "chevron.up"),
        (state.page.next, grid === albums ? "Altri album" : "Altri elementi", "chevron.down")
      ] {
        guard let offset else { continue }
        let destination = CarPlayPage(count: state.tiles.count, offset: offset,
          capacity: state.page.capacity)
        let row = CPListItem(text: title,
          detailText: "\(destination.range.lowerBound + 1)–\(destination.range.upperBound) di \(state.tiles.count)",
          image: UIImage(systemName: symbol))
        row.handler = { [weak self, weak grid, weak state] _, done in
          done()
          guard let self, let grid, let state else { return }
          self.setTiles(state.tiles, in: grid, offset: offset, layout: state.layout,
            leadingButtons: leadingButtons, refresh: state.refresh)
        }
        rows.append(row)
      }
      return [CPListSection(items: rows)]
    }

    /// Page within the same template, preserving every album without deep navigation stacks.
    private func setTiles(
      _ tiles: [Tile], in grid: CPListTemplate, offset: Int? = nil,
      layout requestedLayout: Layout? = nil,
      leadingButtons: [CPBarButton] = [],
      refresh: (@MainActor () -> Void)? = nil
    ) {
      let previous = grids.object(forKey: grid)
      let layout = requestedLayout ?? previous?.layout ?? .covers
      let page = CarPlayPage(
        count: tiles.count, offset: offset ?? previous?.page.range.lowerBound ?? 0,
        capacity: min(Int(CPListTemplate.maximumItemCount), layout == .covers ? 12 : 60))
      if let previous, previous.page == page, previous.layout == layout,
        previous.tiles.map(\.key) == tiles.map(\.key)
      {
        return
      }
      for load in previous?.loads ?? [] { load.cancel() }
      let state = ContentState(tiles: tiles, page: page, layout: layout, refresh: refresh)
      grids.setObject(state, forKey: grid)
      grid.updateSections(sections(state, in: grid, leadingButtons: leadingButtons))
      grid.leadingNavigationBarButtons =
        refresh.map { action in
          [CPBarButton(image: UIImage(systemName: "arrow.clockwise")!) { _ in action() }]
        } ?? leadingButtons
      var navigation: [CPBarButton] = []
      for (offset, symbol) in [(page.previous, "chevron.left"), (page.next, "chevron.right")] {
        if let offset {
          navigation.append(
            CPBarButton(image: UIImage(systemName: symbol)!) { [weak self, weak grid] _ in
              guard let self, let grid else { return }
              self.setTiles(
                tiles, in: grid, offset: offset, layout: layout, leadingButtons: leadingButtons,
                refresh: refresh)
            })
        }
      }
      grid.trailingNavigationBarButtons = navigation
      for (index, position) in page.range.enumerated() {
        let tile = tiles[position]
        guard tile.artwork != nil || tile.videoID != nil else { continue }
        state.loads.append(
          Task { [weak self, weak grid, weak state] in
            let image = await AppleArtworkStore.shared.image(
              primary: tile.artwork, videoID: tile.videoID)
            guard let self, let grid, let state, let image, !Task.isCancelled,
              self.controller != nil, self.grids.object(forKey: grid) === state
            else { return }
            let displayImage = state.layout == .covers ? AppleArtworkStore.squareCover(image) : image
            state.images[index] = displayImage
            state.imageUpdates[index]?(displayImage)
          })
      }
    }

    private func displayFilters() {
      let tiles = HomeFilter.values.map { filter in
        Tile(id: filter.id, title: filter.title, symbol: "music.note.list") { [weak self] in
          guard let self else { return }
          self.tasks.append(
            Task {
              await self.app.home.select(filter)
              self.controller?.popTemplate(animated: true, completion: { _, _ in })
            })
        }
      }
      push(tiles, title: "Stati d’animo")
    }

    private func displayCategories() {
      let tiles = app.home.categories.flatMap(\.items).map { category in
        Tile(id: category.title, title: category.title, symbol: "guitars") { [weak self] in
          self?.browse(category.target, title: category.title)
        }
      }
      push(tiles, title: "Generi musicali")
    }

    private func push(_ tiles: [Tile], title: String, layout: Layout = .covers) {
      let grid = CPListTemplate(title: title, sections: [])
      setTiles(tiles.isEmpty ? [status("Nessun contenuto")] : tiles, in: grid, layout: layout)
      controller?.pushTemplate(grid, animated: true, completion: { _, _ in })
    }

    private func displaySongs(_ songs: [Song], title: String) {
      push(songTiles(songs), title: title, layout: .tracks)
    }

    private func songTiles(_ songs: [Song]) -> [Tile] {
      songs.enumerated().map { index, song in
        Tile(
          id: song.id, title: song.title, detail: song.artist, artwork: song.artwork,
          videoID: song.id
        ) {
          [weak self] in
          self?.play(song, queue: songs, selectedIndex: index)
        }
      }
    }

    private func play(_ song: Song, queue: [Song], selectedIndex: Int? = nil) {
      app.music.play(song, queue: queue, selectedIndex: selectedIndex)
      controller?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: { _, _ in })
    }

    private func tiles(
      _ items: [DiscoveryItem], albumArtwork: URL? = nil, albumArtist: String? = nil,
      albumID: String? = nil
    ) -> [Tile] {
      let artist = AlbumTrackMetadata.artist(from: albumArtist)
      let songs = items.filter { $0.kind == .song }.map {
        Song($0).withAlbumArtwork(albumArtwork, artist: artist, albumID: albumID)
      }
      return items.map { item in
        Tile(
          id: item.id, title: item.title, detail: item.subtitle,
          artwork: albumArtwork ?? item.artwork,
          videoID: item.kind == .song ? item.mediaId : nil
        ) { [weak self] in
          if item.kind == .song {
            self?.play(
              Song(item).withAlbumArtwork(albumArtwork, artist: artist, albumID: albumID),
              queue: songs)
          } else if let target = item.target {
            self?.browse(
              target, title: item.title,
              albumArtwork: item.kind == .album ? item.artwork : nil,
              albumArtist: item.kind == .album ? item.subtitle : nil)
          }
        }
      }
    }

    private func display(_ items: [DiscoveryItem], title: String) {
      push(tiles(items), title: title)
    }

    private func browse(
      _ target: BrowseTarget, title: String, albumArtwork: URL? = nil, albumArtist: String? = nil
    ) {
      let expected = detailRevision
      let account = app.library.session
      let loading = CPListTemplate(title: title, sections: [])
      let artistButtons: [CPBarButton] =
        target.browseId.hasPrefix("UC")
        ? [
          CPBarButton(title: "Radio") { [weak self] _ in
            self?.app.music.startRadio(artistID: target.browseId, title: title)
            self?.openQueue()
          }
        ] : []
      setTiles([status("Caricamento…")], in: loading, leadingButtons: artistButtons)
      controller?.pushTemplate(loading, animated: true, completion: { _, _ in })
      tasks.append(
        Task {
          do {
            if albumArtwork != nil || target.browseId.hasPrefix("MPRE") {
              let detail = try await AlbumDetail.load(
                album: LibraryAlbum(
                  id: target.browseId, title: title, artist: albumArtist ?? "",
                  artwork: albumArtwork),
                session: account)
              try Task.checkCancellation()
              guard detailRevision == expected, controller != nil else { return }
              setTiles(
                detail.songs.isEmpty ? [status("Nessun contenuto")] : songTiles(detail.songs),
                in: loading, layout: .tracks)
              return
            }
            let provider = HomeDiscovery(session: account)
            var items: [DiscoveryItem] = []
            var seen = Set<String>()
            var tokens = Set<String>()
            var token: String?
            repeat {
              let page = try await provider.page(target: target, continuation: token)
              try Task.checkCancellation()
              guard detailRevision == expected, controller != nil else { return }
              items += page.shelves.flatMap(\.items).filter { seen.insert($0.id).inserted }
              token = page.continuation
              if let token, !tokens.insert(token).inserted {
                throw LibraryError.repeatedContinuation
              }
            } while token != nil
            let content = tiles(
              items, albumArtwork: albumArtwork, albumArtist: albumArtist,
              albumID: albumArtwork != nil ? target.browseId : nil)
            setTiles(
              content.isEmpty ? [status("Nessun contenuto")] : content, in: loading,
              layout: albumArtwork != nil
                || (!items.isEmpty && items.allSatisfy { $0.kind == .song }) ? .tracks : .covers,
              leadingButtons: artistButtons)
          } catch {
            guard !Task.isCancelled, detailRevision == expected else { return }
            setTiles(
              [
                Tile(id: "retry", title: "Riprova", symbol: "arrow.clockwise") {
                  [weak owner = self] in
                  guard let self = owner else { return }
                  self.controller?.popTemplate(animated: false, completion: { _, _ in })
                  self.browse(
                    target, title: title, albumArtwork: albumArtwork, albumArtist: albumArtist)
                }
              ], in: loading)
          }
        })
    }

    nonisolated func nowPlayingTemplateUpNextButtonTapped(
      _ nowPlayingTemplate: CPNowPlayingTemplate
    ) {
      Task { @MainActor [weak self] in self?.openQueue() }
    }

    private func openQueue() {
      queueOffset = 0
      renderQueue()
      controller?.pushTemplate(queueTemplate, animated: true, completion: { _, _ in })
    }

    private func renderQueue() {
      let entries = app.music.queueRows
      let page = CarPlayPage(count: entries.count, offset: queueOffset, capacity: 20)
      queueOffset = page.range.lowerBound
      var rows: [CPListItem] = []
      for position in page.range {
        let entry = entries[position]
        let active = app.music.queueIndex == entry.index
        let row = CPListItem(
          text: "\(position + 1). \(entry.song.title)",
          detailText: active ? "Brano corrente · " + entry.song.artist : entry.song.artist,
          image: UIImage(systemName: active ? "waveform" : "music.note"))
        row.accessoryType = .disclosureIndicator
        row.handler = { [weak self] _, done in
          done()
          guard let self else { return }
          let play = CPAlertAction(title: "Riproduci", style: .default) { [weak self] _ in
            guard let self else { return }
            self.app.music.playQueueOccurrence(entry.id)
            self.controller?.dismissTemplate(animated: true, completion: { _, _ in })
          }
          let next = CPAlertAction(title: "Riproduci dopo", style: .default) { [weak self] _ in
            self?.app.music.playQueueOccurrenceNext(entry.id)
            self?.controller?.dismissTemplate(animated: true, completion: { _, _ in })
          }
          let remove = CPAlertAction(title: "Rimuovi dalla coda", style: .destructive) {
            [weak self] _ in
            self?.app.music.removeQueueOccurrence(entry.id)
            self?.controller?.dismissTemplate(animated: true, completion: { _, _ in })
          }
          let cancel = CPAlertAction(title: "Annulla", style: .cancel) { [weak self] _ in
            self?.controller?.dismissTemplate(animated: true, completion: { _, _ in })
          }
          self.controller?.presentTemplate(
            CPActionSheetTemplate(
              title: entry.song.title,
              message: nil, actions: [play, next, remove, cancel]), animated: true,
            completion: { _, _ in })
        }
        rows.append(row)
      }
      if let previous = page.previous {
        let row = CPListItem(text: "Precedenti", detailText: nil)
        row.handler = { [weak self] _, done in
          done()
          self?.queueOffset = previous
          self?.renderQueue()
        }
        rows.insert(row, at: 0)
      }
      if let next = page.next {
        let row = CPListItem(text: "Successivi", detailText: nil)
        row.handler = { [weak self] _, done in
          done()
          self?.queueOffset = next
          self?.renderQueue()
        }
        rows.append(row)
      }
      if rows.isEmpty {
        let empty = CPListItem(text: "Coda vuota", detailText: nil)
        empty.isEnabled = false
        rows = [empty]
      }
      let automatic = CPListItem(
        text: "Riproduzione automatica",
        detailText: app.music.autoplayEnabled ? "Attiva" : "Disattivata",
        image: UIImage(systemName: "infinity"))
      automatic.handler = { [weak self] _, done in
        done()
        self?.app.music.autoplayEnabled.toggle()
      }
      var radioRows = [automatic]
      if let song = app.music.current {
        let radio = CPListItem(
          text: "Radio del brano", detailText: song.title,
          image: UIImage(systemName: "dot.radiowaves.left.and.right"))
        radio.handler = { [weak self] _, done in
          done()
          self?.app.music.startRadio(song: song)
        }
        radioRows.append(radio)
        if let id = song.artistBrowseID {
          let artist = CPListItem(
            text: "Radio dell’artista", detailText: song.artist,
            image: UIImage(systemName: "person.fill"))
          artist.handler = { [weak self] _, done in
            done()
            self?.app.music.startRadio(artistID: id, title: song.artist)
          }
          radioRows.append(artist)
        }
      }
      if app.music.loadingRadio || app.music.radioError != nil {
        let status = CPListItem(
          text: app.music.loadingRadio ? "Preparo la radio…" : "Suggerimenti non disponibili",
          detailText: app.music.radioError == nil ? nil : "Tocca per riprovare")
        status.isEnabled = !app.music.loadingRadio
        status.handler = { [weak self] _, done in
          done()
          self?.app.music.retryRadio()
        }
        radioRows.append(status)
      }
      queueTemplate.updateSections([CPListSection(items: radioRows), CPListSection(items: rows)])
    }

    private func configureNowPlaying() {
      CPNowPlayingTemplate.shared.isUpNextButtonEnabled = !app.music.queue.isEmpty
      let active = app.music.busyMeaning || app.music.reading
      let enabled = app.music.current != nil && !app.music.player.isLoading
      let state =
        "\(enabled):\(active):\(app.music.current?.id ?? ""):\(app.music.shuffleEnabled):\(app.music.repeatMode.rawValue)"
      guard meaningButtonState != state else { return }
      meaningButtonState = state
      let light = CPNowPlayingImageButton(
        image: UIImage(systemName: active ? "stop.circle" : "lightbulb")!
      ) {
        [weak self] _ in
        guard let self else { return }
        if self.app.music.busyMeaning || self.app.music.reading {
          self.app.music.stopMeaning(resume: true)
          self.dismissMeaning()
        } else {
          self.explain()
        }
      }
      light.isEnabled = enabled
      let album = CPNowPlayingImageButton(image: UIImage(systemName: "square.stack.fill")!) {
        [weak self] _ in self?.openCurrentContext(.albums)
      }
      let artist = CPNowPlayingImageButton(image: UIImage(systemName: "person.fill")!) {
        [weak self] _ in self?.openCurrentContext(.artists)
      }
      album.isEnabled = app.music.current != nil && !active
      artist.isEnabled = album.isEnabled
      let shuffle = CPNowPlayingShuffleButton { [weak self] _ in
        guard let music = self?.app.music else { return }
        music.setShuffle(!music.shuffleEnabled)
      }
      let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in
        guard let music = self?.app.music else { return }
        music.repeatMode = music.repeatMode.next
      }
      shuffle.isEnabled = enabled && !active
      repeatButton.isEnabled = shuffle.isEnabled
      CPNowPlayingTemplate.shared.updateNowPlayingButtons([
        light, album, artist, shuffle, repeatButton,
      ])
    }

    private func explain() {
      guard meaningAlert == nil, !app.music.player.isLoading, app.music.current != nil else {
        return
      }
      let stop = CPAlertAction(title: "Interrompi", style: .cancel) {
        [weak self] _ in
        self?.app.music.stopMeaning(resume: true)
        self?.app.music.showMeaning = false
        self?.dismissMeaning()
      }
      let alert = CPAlertTemplate(titleVariants: ["Significato della canzone"], actions: [stop])
      meaningAlert = alert
      meaningStarted = true
      let started = CarPlayNarrationRequest.start(app.music) { [weak self] completion in
        self?.controller?.presentTemplate(alert, animated: true) { [weak self] success, _ in
          guard let self, self.meaningAlert === alert else { return }
          completion(success)
          if !success { self.meaningAlert = nil }
        }
      }
      if !started {
        meaningAlert = nil
        meaningStarted = false
      }
    }
    private func updateMeaning() {
      guard meaningAlert != nil, meaningStarted else { return }
      if !app.music.busyMeaning && !app.music.reading {
        if app.music.meaningError != nil {
          meaningStarted = false
          dismissMeaning { [weak self] in
            guard let self, self.controller != nil else { return }
            let retry = CPAlertAction(title: "Riprova", style: .default) { [weak self] _ in
              self?.dismissMeaning { [weak self] in self?.explain() }
            }
            let close = CPAlertAction(title: "Chiudi", style: .cancel) { [weak self] _ in
              self?.dismissMeaning()
            }
            let alert = CPAlertTemplate(
              titleVariants: ["Lettura non disponibile. Riprova."], actions: [retry, close])
            self.meaningAlert = alert
            self.controller?.presentTemplate(alert, animated: true, completion: { _, _ in })
          }
        } else {
          dismissMeaning()
        }
      }
    }
    private func dismissMeaning(then completion: (@MainActor () -> Void)? = nil) {
      guard meaningAlert != nil else { return }
      meaningAlert = nil
      app.music.showMeaning = false
      controller?.dismissTemplate(
        animated: true,
        completion: { success, _ in
          if success { completion?() }
        })
    }
  }
  /// Start work from the user action, independently of a vehicle's presentation callback.
  @MainActor
  enum CarPlayNarrationRequest {
    @discardableResult
    static func start(_ music: MusicModel, present: (@escaping (Bool) -> Void) -> Void) -> Bool {
      guard music.explain(presentOnPhone: false) else { return false }
      let request = music.meaningRequestID
      present { success in
        guard !success, music.meaningRequestID == request else { return }
        music.stopMeaning(resume: true)
        music.meaningError = "Impossibile aprire il comando CarPlay. Riprova."
        music.narrationDiagnostic = "CarPlay: presentazione rifiutata"
      }
      return true
    }
  }

  /// Siri resolves music on the vehicle and launches playback in the app's background session.
  @MainActor
  final class CarPlayMediaIntentHandler: NSObject, @preconcurrency INPlayMediaIntentHandling,
    @preconcurrency INSearchForMediaIntentHandling
  {
    private let app = AppleAppSession.shared

    private func request(_ search: INMediaSearch?, fallback: String? = nil) -> CarPlayVoiceQuery? {
      let filter: MusicSearchFilter =
        search?.mediaType == .album
        ? .albums
        : search?.mediaType == .artist ? .artists : .songs
      var parts: [String] = []
      for value in [search?.mediaName, search?.albumName, search?.artistName, fallback] {
        if let value, !value.isEmpty, !parts.contains(value) { parts.append(value) }
      }
      let query = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else { return nil }
      return CarPlayVoiceQuery(query: query, filter: filter)
    }

    private func mediaItem(_ item: DiscoveryItem) -> INMediaItem {
      INMediaItem(
        identifier: VoiceMediaIdentifier(kind: item.kind, mediaID: item.mediaId).encoded,
        title: item.title,
        type: item.kind == .album ? .album : item.kind == .artist ? .artist : .song,
        artwork: item.artwork.flatMap { INImage(url: $0) }, artist: item.subtitle)
    }

    func resolveMediaItems(for intent: INPlayMediaIntent) async
      -> [INPlayMediaMediaItemResolutionResult]
    {
      if let items = intent.mediaItems, !items.isEmpty,
        items.allSatisfy({ VoiceMediaIdentifier(encoded: $0.identifier ?? "") != nil })
      {
        return INPlayMediaMediaItemResolutionResult.successes(with: items)
      }
      guard let voice = request(intent.mediaSearch, fallback: intent.mediaItems?.first?.title)
      else {
        return [.needsValue()]
      }
      app.music.carPlayVoiceQuery = voice
      do {
        let results = try await HomeDiscovery(session: app.library.session).search(
          query: voice.query, filter: voice.filter)
        let items = results.prefix(5).map(mediaItem)
        if items.count == 1 { return [.success(with: items[0])] }
        return items.isEmpty ? [.unsupported()] : [.disambiguation(with: items)]
      } catch { return [.unsupported(forReason: .serviceUnavailable)] }
    }

    func handle(intent: INSearchForMediaIntent) async -> INSearchForMediaIntentResponse {
      guard let voice = request(intent.mediaSearch, fallback: intent.mediaItems?.first?.title)
      else {
        return INSearchForMediaIntentResponse(code: .failure, userActivity: nil)
      }
      app.music.carPlayVoiceQuery = voice
      do {
        let results = try await HomeDiscovery(session: app.library.session).search(
          query: voice.query, filter: voice.filter)
        let response = INSearchForMediaIntentResponse(code: .success, userActivity: nil)
        response.mediaItems = results.prefix(20).map(mediaItem)
        return response
      } catch { return INSearchForMediaIntentResponse(code: .failure, userActivity: nil) }
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
      if intent.resumePlayback == true, app.music.current != nil {
        app.music.player.play()
        return INPlayMediaIntentResponse(code: .success, userActivity: nil)
      }
      let voice = request(intent.mediaSearch, fallback: intent.mediaItems?.first?.title)
      if let voice { app.music.carPlayVoiceQuery = voice }
      do {
        let discovery = HomeDiscovery(session: app.library.session)
        let selected = intent.mediaItems?.first
        let identifier = selected?.identifier.flatMap { VoiceMediaIdentifier(encoded: $0) }
        var songs: [Song] = []
        if let identifier, identifier.kind == .song {
          songs = [
            Song(
              id: identifier.mediaID, title: selected?.title ?? "Brano",
              artist: selected?.artist ?? "", artwork: nil)
          ]
        } else {
          let item: DiscoveryItem?
          if let identifier {
            item = DiscoveryItem(
              kind: identifier.kind, mediaId: identifier.mediaID,
              title: selected?.title ?? "", subtitle: selected?.artist ?? "", artwork: nil)
          } else if let voice {
            item = try await discovery.search(query: voice.query, filter: voice.filter).first
          } else {
            item = nil
          }
          if let item, item.kind == .song {
            songs = [Song(item)]
          } else if let target = item?.target {
            let page = try await discovery.page(target: target)
            songs = page.shelves.flatMap(\.items).filter { $0.kind == .song }.map(Song.init)
          }
        }
        guard let first = songs.first else {
          return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
        }
        if let shuffled = intent.playShuffled { app.music.setShuffle(shuffled) }
        switch intent.playbackRepeatMode {
        case .one: app.music.repeatMode = .one
        case .all: app.music.repeatMode = .all
        case .none: app.music.repeatMode = .off
        default: break
        }
        app.music.play(first, queue: songs)
        app.music.showPlayer = false
        return INPlayMediaIntentResponse(code: .success, userActivity: nil)
      } catch { return INPlayMediaIntentResponse(code: .failure, userActivity: nil) }
    }
  }
#endif

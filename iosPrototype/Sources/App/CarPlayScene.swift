#if os(iOS)
  import CarPlay
  import Combine
  import UIKit

  @MainActor
  final class CarPlayAppDelegate: NSObject, UIApplicationDelegate {
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
  final class CarPlayScene: UIResponder, CPTemplateApplicationSceneDelegate {
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
      interfaceController.setRootTemplate(
        CPTabBarTemplate(templates: [home, albums, favorites]),
        animated: false, completion: { _, _ in })
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
      if meaningAlert != nil { app.music.stopMeaning(resume: true) }
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
      var preferred = [
        Tile(
          id: "local-favorites", title: "Preferiti NoteNarrate",
          artwork: app.music.favorites.first?.artwork, symbol: "heart.fill"
        ) { [weak self] in
          guard let self else { return }
          self.displaySongs(self.app.music.favorites, title: "Preferiti NoteNarrate")
        }
      ]
      if app.library.session != nil {
        preferred.insert(
          Tile(
            id: "yt-favorites", title: "Brani piaciuti YouTube Music",
            symbol: "hand.thumbsup.fill"
          ) { [weak self] in
            self?.browse(BrowseTarget(browseId: "VLLM"), title: "Brani piaciuti")
          }, at: 0)
      }
      setTiles(preferred, in: favorites)
      configureNowPlaying()
    }

    private func sections(_ state: ContentState) -> [CPListSection] {
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
        // Cover content is not an icon grid. Two full-height cards remain legible in a car.
        let first = index
        var positions: [Int] = []
        while index < count && positions.count < min(2, Int(CPMaximumNumberOfGridImages)) {
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
            let card = CPListImageRowItemCardElement(
              image: state.images[local], showsImageFullHeight: true,
              title: entry.title, subtitle: entry.detail, tintColor: nil)
            state.imageUpdates[local] = { [weak card] image in card?.image = image }
            return card
          }
          row = CPListImageRowItem(text: nil, cardElements: elements, allowsMultipleLines: false)
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
      return [CPListSection(items: rows)]
    }

    /// Page within the same template, preserving every album without deep navigation stacks.
    private func setTiles(
      _ tiles: [Tile], in grid: CPListTemplate, offset: Int? = nil,
      layout requestedLayout: Layout? = nil,
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
      grid.updateSections(sections(state))
      grid.leadingNavigationBarButtons =
        refresh.map { action in
          [CPBarButton(image: UIImage(systemName: "arrow.clockwise")!) { _ in action() }]
        } ?? []
      var navigation: [CPBarButton] = []
      for (offset, symbol) in [(page.previous, "chevron.left"), (page.next, "chevron.right")] {
        if let offset {
          navigation.append(
            CPBarButton(image: UIImage(systemName: symbol)!) { [weak self, weak grid] _ in
              guard let self, let grid else { return }
              self.setTiles(tiles, in: grid, offset: offset, layout: layout, refresh: refresh)
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
            state.images[index] = image
            state.imageUpdates[index]?(image)
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
      let tiles = songs.map { song in
        Tile(
          id: song.id, title: song.title, detail: song.artist, artwork: song.artwork,
          videoID: song.id
        ) {
          [weak self] in
          self?.play(song, queue: songs)
        }
      }
      push(tiles, title: title, layout: .tracks)
    }

    private func play(_ song: Song, queue: [Song]) {
      app.music.play(song, queue: queue)
      controller?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: { _, _ in })
    }

    private func tiles(
      _ items: [DiscoveryItem], albumArtwork: URL? = nil, albumArtist: String? = nil
    ) -> [Tile] {
      let artist = AlbumTrackMetadata.artist(from: albumArtist)
      let songs = items.filter { $0.kind == .song }.map {
        Song($0).withAlbumArtwork(albumArtwork, artist: artist)
      }
      return items.map { item in
        Tile(
          id: item.id, title: item.title, detail: item.subtitle,
          artwork: albumArtwork ?? item.artwork,
          videoID: item.kind == .song ? item.mediaId : nil
        ) { [weak self] in
          if item.kind == .song {
            self?.play(Song(item).withAlbumArtwork(albumArtwork, artist: artist), queue: songs)
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
      setTiles([status("Caricamento…")], in: loading)
      controller?.pushTemplate(loading, animated: true, completion: { _, _ in })
      tasks.append(
        Task {
          do {
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
            let content = tiles(items, albumArtwork: albumArtwork, albumArtist: albumArtist)
            setTiles(
              content.isEmpty ? [status("Nessun contenuto")] : content, in: loading,
              layout: albumArtwork != nil
                || (!items.isEmpty && items.allSatisfy { $0.kind == .song }) ? .tracks : .covers)
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

    private func configureNowPlaying() {
      let active = app.music.busyMeaning || app.music.reading
      let enabled = app.music.current != nil && !app.music.player.isLoading
      let state = "\(enabled):\(active)"
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
      CPNowPlayingTemplate.shared.updateNowPlayingButtons([light])
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
#endif

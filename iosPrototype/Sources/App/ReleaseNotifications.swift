#if os(iOS)
  import BackgroundTasks
  import Combine
  import UIKit
  import UserNotifications

  @MainActor final class ReleaseNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let taskID = "com.stivy.simpmusic.prototype.artist-releases"
    private let music: MusicModel
    private let library: LibraryModel
    private let center = UNUserNotificationCenter.current()
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var refreshID = UUID()
    init(music: MusicModel, library: LibraryModel) {
      self.music = music
      self.library = library
      super.init()
      center.delegate = self
      library.$session.removeDuplicates().sink { [weak self] session in
        guard let self else { return }
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = UUID()
        music.releases.configure(session)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        Task {
          await self.removeAccountNotifications()
          self.schedule()
        }
      }.store(in: &subscriptions)
      library.$collections.debounce(for: .milliseconds(100), scheduler: RunLoop.main).sink {
        [weak self] collections in
        guard let self, let artists = collections[.artists], artists.loaded, artists.error == nil,
          music.releases.session == library.session
        else { return }
        music.releases.reconcile(artists: artists.items)
      }.store(in: &subscriptions)
    }
    static func register() {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
        guard let refresh = task as? BGAppRefreshTask else {
          task.setTaskCompleted(success: false)
          return
        }
        let work = Task { @MainActor in
          let service = AppleAppSession.shared.releaseNotifications!
          await service.refresh(force: true)
          service.schedule()
          refresh.setTaskCompleted(success: !Task.isCancelled)
        }
        refresh.expirationHandler = { work.cancel() }
      }
    }
    func enable(_ enabled: Bool) async {
      guard library.session != nil else {
        library.showLogin = true
        return
      }
      if enabled {
        let account = library.session
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard library.session == account else { return }
      }
      music.releases.setEnabled(enabled)
      if enabled {
        schedule()
        await refresh(force: true)
      } else {
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = UUID()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        await removeAccountNotifications()
      }
    }
    func authorizationMessage() async -> String {
      let settings = await center.notificationSettings()
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: return "Notifiche iOS abilitate."
      case .denied:
        return
          "Notifiche disattivate in iOS: gli avvisi restano consultabili qui. Puoi abilitarle nelle Impostazioni di sistema."
      default: return "Puoi attivare le notifiche per ricevere gli avvisi anche fuori dall’app."
      }
    }
    func schedule() {
      guard music.releases.state.enabled, library.session != nil else { return }
      let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
      request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
      try? BGTaskScheduler.shared.submit(request)
    }
    func refresh(force: Bool = false) async {
      if let refreshTask {
        await refreshTask.value
        return
      }
      let task = Task { await self.performRefresh(force: force) }
      let expected = UUID()
      refreshID = expected
      refreshTask = task
      await withTaskCancellationHandler {
        await task.value
      } onCancel: {
        task.cancel()
      }
      if refreshID == expected { refreshTask = nil }
    }
    private func performRefresh(force: Bool) async {
      guard let account = library.session, music.releases.state.enabled else { return }
      music.releases.configure(account)
      if !force, let checked = music.releases.state.lastCheck,
        Date().timeIntervalSince(checked) < 6 * 3600
      {
        return
      }
      await library.load(.artists, force: true)
      guard !Task.isCancelled, library.session == account, library.state(.artists).error == nil,
        library.state(.artists).loaded
      else { return }
      let added = await music.releases.check(artists: library.state(.artists).items, force: force)
      guard !Task.isCancelled, library.session == account, music.releases.state.enabled else {
        return
      }
      let settings = await center.notificationSettings()
      guard
        settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
      else { return }
      // One summary per check avoids a burst of banners after a long absence.
      guard let first = added.first else { return }
      let content = UNMutableNotificationContent()
      content.title =
        added.count == 1
        ? "Nuova uscita di " + first.artist.title : "Novità dagli artisti che segui"
      content.body =
        added.count == 1
        ? first.release.title : "\(added.count) nuove uscite. Apri NoteNarrate per ascoltarle."
      content.sound = .default
      content.threadIdentifier = "notenarrate.artist-releases"
      content.userInfo = ["route": AppRoute.album(first.release.mediaId).url.absoluteString]
      let id = "notenarrate.release." + LocalFiles.key(account.identity + first.id)
      guard library.session == account, music.releases.state.enabled else { return }
      try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
    private func removeAccountNotifications() async {
      let delivered = await center.deliveredNotifications()
      center.removeDeliveredNotifications(
        withIdentifiers: delivered.map(\.request.identifier).filter {
          $0.hasPrefix("notenarrate.release.")
        })
      let pending = await center.pendingNotificationRequests()
      center.removePendingNotificationRequests(
        withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("notenarrate.release.") })
    }
    nonisolated func userNotificationCenter(
      _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
      guard let text = response.notification.request.content.userInfo["route"] as? String,
        let url = URL(string: text), let route = AppRoute(url: url)
      else { return }
      await MainActor.run { AppleAppSession.shared.music.externalRoute = route }
    }
    nonisolated func userNotificationCenter(
      _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
      [.banner, .sound]
    }
  }
#endif

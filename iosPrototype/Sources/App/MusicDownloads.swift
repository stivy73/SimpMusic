import Combine
import Foundation

/// Two user-initiated background transfers. Only validated complete files enter the offline collection.
@MainActor
final class MusicDownloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
  typealias Resolve = @Sendable (String, YouTubeSession?, AudioQuality, Bool) async throws -> YouTubeAudio.Source
  static let identifier = "com.stivy.simpmusic.prototype.music-downloads"
  let library: OfflineLibrary
  @Published var wifiOnly =
    UserDefaults.standard.object(forKey: "downloadsWiFiOnly") as? Bool ?? true
  {
    didSet { UserDefaults.standard.set(wifiOnly, forKey: "downloadsWiFiOnly") }
  }
  @Published var limitGB = UserDefaults.standard.object(forKey: "downloadsLimitGB") as? Int ?? 5 {
    didSet { UserDefaults.standard.set(limitGB, forKey: "downloadsLimitGB") }
  }
  var backgroundCompletion: (() -> Void)?
  private var subscription: AnyCancellable?
  private var queued: [(Song, YouTubeSession?)] = []
  private var active = Set<String>()
  private var resolutions: [String: Task<Void, Never>] = [:]
  private var transfers: [String: URLSessionDownloadTask] = [:]
  private var verifications: [String: Task<Void, Never>] = [:]
  private let resolve: Resolve
  private let configuration: URLSessionConfiguration?
  private var restored = false
  private lazy var session: URLSession = {
    #if os(iOS)
      let config = configuration ?? .background(withIdentifier: Self.identifier)
      if config.identifier != nil { config.sessionSendsLaunchEvents = true }
    #else
      let config = configuration ?? .default
    #endif
    config.httpMaximumConnectionsPerHost = 2
    config.isDiscretionary = false
    return URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }()
  init(
    library: OfflineLibrary = OfflineLibrary(
      directory: ProcessInfo.processInfo.arguments.contains("--test-local-playback")
        ? LocalFiles.directory("QAOffline") : LocalFiles.directory("Offline")),
    resolve: @escaping Resolve = { id, account, quality, accountOnly in
      try await YouTubeAudio().resolve(videoID: id, session: account, quality: quality, accountOnly: accountOnly)
    }, configuration: URLSessionConfiguration? = nil
  ) {
    self.library = library
    self.resolve = resolve
    self.configuration = configuration
    super.init()
    subscription = library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--test-offline-library")
        || ProcessInfo.processInfo.arguments.contains("--test-local-playback")
      {
        restored = true
        return
      }
    #endif
    Task {
      let tasks: [URLSessionTask] = await withCheckedContinuation { continuation in
        session.getAllTasks { continuation.resume(returning: $0) }
      }
      for task in tasks {
        guard let task = task as? URLSessionDownloadTask, let id = task.taskDescription,
          task.state == .running || task.state == .suspended else { continue }
        guard ownsTransfer(task, id: id) else {
          // The user may have paused or removed it while the system was reconnecting.
          task.cancel()
          continue
        }
        library.recordTransfer(id, received: task.countOfBytesReceived, responseLength: task.countOfBytesExpectedToReceive)
      }
      queued.removeAll { active.contains($0.0.id) || library.url(for: $0.0.id) != nil }
      for (track, _) in queued where library.records.first(where: { $0.id == track.id })?.state != .preparing {
        library.begin(track)
      }
      library.reconcile(active: active.union(queued.map { $0.0.id }))
      restored = true
      pump()
    }
  }
  func start(_ track: Song, account: YouTubeSession?) {
    guard library.url(for: track.id) == nil, !active.contains(track.id),
      !queued.contains(where: { $0.0.id == track.id })
    else { return }
    queued.append((track, account))
    if !restored, let state = library.records.first(where: { $0.id == track.id })?.state,
      state == .downloading || state == .verifying { return }
    library.begin(track)
    pump()
  }
  private func pump() {
    guard restored else { return }
    while active.count < 2, !queued.isEmpty {
      let (track, account) = queued.removeFirst()
      active.insert(track.id)
      resolutions[track.id] = Task {
        do {
          let source = try await resolve(track.id, account, AudioPreferences.shared.downloadQuality, track.isUploaded == true)
          try Task.checkCancellation()
          guard active.contains(track.id) else { return }
          guard !source.isHLS else { throw OfflineError.unsupportedStream }
          if let bytes = source.byteCount {
            let free =
              (try? FileManager.default.attributesOfFileSystem(forPath: library.directory.path)[
                .systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
            guard bytes > 0, bytes <= Int64(limitGB) * 1_073_741_824 - library.totalBytes,
              free > 50_000_000, bytes < free - 50_000_000
            else { throw OfflineError.storage }
          }
          var request = URLRequest(url: source.url, timeoutInterval: 60)
          request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
          request.allowsCellularAccess = !wifiOnly
          request.allowsConstrainedNetworkAccess = !wifiOnly
          let task = session.downloadTask(with: request)
          task.taskDescription = track.id
          transfers[track.id] = task
          library.update(
            track.id, state: .downloading, expected: source.byteCount,
            expectedDuration: source.duration)
          resolutions[track.id] = nil
          task.resume()
        } catch {
          guard !Task.isCancelled else { return }
          library.update(
            track.id, state: .failed,
            error: (error as? OfflineError)?.localizedDescription
              ?? "Download non disponibile. Controlla la connessione e riprova.")
          active.remove(track.id)
          resolutions[track.id] = nil
          pump()
        }
      }
    }
  }
  func pause(_ id: String) {
    guard let record = library.records.first(where: { $0.id == id }),
      [.preparing, .downloading, .verifying].contains(record.state) else { return }
    queued.removeAll { $0.0.id == id }
    resolutions.removeValue(forKey: id)?.cancel()
    transfers.removeValue(forKey: id)?.cancel()
    verifications.removeValue(forKey: id)?.cancel()
    active.remove(id)
    library.update(id, state: .paused)
    pump()
  }
  func remove(_ id: String) {
    pause(id)
    do { try library.remove(id) } catch {
      library.persistenceError = "Non riesco a rimuovere il file scaricato."
    }
  }
  private func ownsTransfer(_ task: URLSessionDownloadTask, id: String) -> Bool {
    if let current = transfers[id] { return current.taskIdentifier == task.taskIdentifier }
    // A background callback can arrive before getAllTasks returns after relaunch.
    guard !restored, library.records.contains(where: { $0.id == id && $0.state == .downloading })
    else { return false }
    active.insert(id)
    transfers[id] = task
    return true
  }
  private func endTransfer(_ id: String, taskID: Int) {
    guard transfers[id]?.taskIdentifier == taskID else { return }
    verifications[id] = nil
    transfers[id] = nil
    active.remove(id)
    pump()
  }
  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let id = downloadTask.taskDescription else { return }
    // This session's serial delegate queue is OperationQueue.main. Process
    // callbacks in order so a late progress event can't undo verification.
    MainActor.assumeIsolated {
      guard ownsTransfer(downloadTask, id: id) else { return }
      library.recordTransfer(id, received: totalBytesWritten, responseLength: totalBytesExpectedToWrite)
    }
  }
  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let id = downloadTask.taskDescription else { return }
    // The system removes its temporary file when this callback returns.
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(
      "notenarrate-download-" + UUID().uuidString + ".m4a")
    let response = downloadTask.response as? HTTPURLResponse
    let taskID = downloadTask.taskIdentifier
    let status = response?.statusCode ?? 0
    let contentRange = response?.value(forHTTPHeaderField: "Content-Range")
    do { try FileManager.default.moveItem(at: location, to: staged) } catch {
      MainActor.assumeIsolated {
        guard ownsTransfer(downloadTask, id: id) else { return }
        library.update(id, state: .failed, error: "Impossibile conservare il file scaricato.")
        endTransfer(id, taskID: taskID)
      }
      return
    }
    MainActor.assumeIsolated {
      guard ownsTransfer(downloadTask, id: id),
        library.records.contains(where: { $0.id == id && $0.state == .downloading })
      else {
        try? FileManager.default.removeItem(at: staged)
        return
      }
      verifications[id] = Task {
        defer {
          try? FileManager.default.removeItem(at: staged)
          endTransfer(id, taskID: taskID)
        }
        do {
          try await library.finish(
            id, temporary: staged, status: status, contentRange: contentRange,
            maxBytes: Int64(limitGB) * 1_073_741_824)
        } catch {
          if !Task.isCancelled, transfers[id]?.taskIdentifier == taskID {
            library.update(
              id, state: .failed,
              error: (error as? OfflineError)?.localizedDescription
                ?? OfflineError.incomplete.localizedDescription)
          }
        }
      }
    }
  }
  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    guard let id = task.taskDescription else { return }
    guard error != nil, let transfer = task as? URLSessionDownloadTask else { return }
    MainActor.assumeIsolated {
      guard ownsTransfer(transfer, id: id) else { return }
      if library.records.first(where: { $0.id == id })?.state == .downloading {
        library.update(
          id, state: .failed, error: "Download interrotto. Controlla la connessione e riprova.")
      }
      endTransfer(id, taskID: task.taskIdentifier)
    }
  }
  nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      for pending in Array(verifications.values) { await pending.value }
      backgroundCompletion?()
      backgroundCompletion = nil
    }
  }
}

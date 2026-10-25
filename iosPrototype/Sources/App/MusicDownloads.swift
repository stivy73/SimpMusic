import Combine
import Foundation

/// Two user-initiated background transfers. Only validated complete files enter the offline collection.
@MainActor
final class MusicDownloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
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
  private var restored = false
  private lazy var session: URLSession = {
    #if os(iOS)
      let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
      config.sessionSendsLaunchEvents = true
    #else
      let config = URLSessionConfiguration.default
    #endif
    config.httpMaximumConnectionsPerHost = 2
    config.isDiscretionary = false
    return URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }()
  init(
    library: OfflineLibrary = OfflineLibrary(
      directory: ProcessInfo.processInfo.arguments.contains("--test-local-playback")
        ? LocalFiles.directory("QAOffline") : LocalFiles.directory("Offline"))
  ) {
    self.library = library
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
        if let id = task.taskDescription, let task = task as? URLSessionDownloadTask {
          active.insert(id)
          transfers[id] = task
        }
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
    library.begin(track)
    queued.append((track, account))
    pump()
  }
  private func pump() {
    guard restored else { return }
    while active.count < 2, !queued.isEmpty {
      let (track, account) = queued.removeFirst()
      active.insert(track.id)
      resolutions[track.id] = Task {
        do {
          let source = try await YouTubeAudio().resolve(
            videoID: track.id, session: account, quality: AudioPreferences.shared.downloadQuality)
          try Task.checkCancellation()
          guard active.contains(track.id) else { return }
          guard !source.isHLS else { throw OfflineError.unsupportedStream }
          if let bytes = source.byteCount {
            let free =
              (try? FileManager.default.attributesOfFileSystem(forPath: library.directory.path)[
                .systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
            guard bytes + library.totalBytes <= Int64(limitGB) * 1_073_741_824,
              bytes + 50_000_000 < free
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
  nonisolated func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let id = downloadTask.taskDescription else { return }
    let taskID = downloadTask.taskIdentifier
    let progress =
      totalBytesExpectedToWrite > 0
      ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
    Task { @MainActor [weak self] in
      guard let self, active.contains(id), transfers[id]?.taskIdentifier == taskID else { return }
      library.update(id, state: .downloading, progress: progress)
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
      Task { @MainActor [weak self] in
        self?.library.update(id, state: .failed, error: "Impossibile conservare il file scaricato.")
      }
      return
    }
    Task { @MainActor [weak self] in
      guard let self, transfers[id]?.taskIdentifier == taskID,
        library.records.contains(where: { $0.id == id && $0.state == .downloading })
      else {
        try? FileManager.default.removeItem(at: staged)
        return
      }
      verifications[id] = Task {
        defer {
          try? FileManager.default.removeItem(at: staged)
          verifications[id] = nil
          if transfers[id]?.taskIdentifier == taskID {
            active.remove(id)
            transfers[id] = nil
            pump()
          }
        }
        do {
          let size = Int64(try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
          guard size + library.totalBytes <= Int64(limitGB) * 1_073_741_824 else {
            throw OfflineError.storage
          }
          try await library.finish(
            id, temporary: staged, status: status, contentRange: contentRange,
            maxBytes: Int64(limitGB) * 1_073_741_824)
        } catch {
          if !Task.isCancelled {
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
    let failed = error != nil
    let taskID = task.taskIdentifier
    Task { @MainActor [weak self] in
      guard let self, transfers[id]?.taskIdentifier == taskID else { return }
      guard failed else { return }
      if library.records.first(where: { $0.id == id })?.state == .downloading {
        library.update(
          id, state: .failed, error: "Download interrotto. Controlla la connessione e riprova.")
      }
      active.remove(id)
      transfers[id] = nil
      pump()
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

#if os(iOS) || os(watchOS)
  import Foundation
  import Combine
  @preconcurrency import WatchConnectivity

  private final class WatchReplyBox: @unchecked Sendable {
    let reply: ([String: Any]) -> Void
    init(_ reply: @escaping ([String: Any]) -> Void) { self.reply = reply }
  }

  @MainActor final class WatchSessionLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = WatchSnapshot()
    @Published var reachable = false
    @Published var pending = false
    @Published var message: String?
    var onCommand: ((WatchCommand) throws -> WatchSnapshot)?
    var onAvailabilityChanged: (() -> Void)?
    private var activeRequest: UUID?
    private var timeout: Task<Void, Never>?
    private var replies: [UUID: [String: Any]] = [:]
    private var replyOrder: [UUID] = []
    private var receivedAt = Date.distantPast
    override init() {
      super.init()
      #if os(iOS)
        activate()
      #endif
    }
    /// On Watch, called after the application has finished launching, not while SwiftUI constructs it.
    func activate() {
      guard WCSession.isSupported() else { return }
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
    func accept(_ value: WatchSnapshot) {
      guard value.date >= receivedAt else { return }
      receivedAt = value.date
      snapshot = value
    }
    func publish(_ value: WatchSnapshot) {
      snapshot = value
      guard WCSession.isSupported() else { return }
      let session = WCSession.default
      guard session.activationState == .activated,
        let data = try? value.encoded()
      else { return }
      #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
      #endif
      try? session.updateApplicationContext(["snapshot": data])
    }
    func send(_ action: WatchCommand.Action, occurrenceID: String? = nil) {
      guard WCSession.isSupported() else { return }
      let session = WCSession.default
      guard session.activationState == .activated, session.isReachable else {
        reachable = false
        message = "iPhone non raggiungibile. Avvicinalo e apri NoteNarrate."
        return
      }
      guard !pending else { return }
      let command = WatchCommand(
        action: action, expectedTrackID: snapshot.track?.id, occurrenceID: occurrenceID)
      guard let data = try? JSONEncoder().encode(command) else { return }
      activeRequest = command.id
      pending = true
      message = nil
      timeout?.cancel()
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(12)) } catch { return }
        self?.finished(command.id, data: nil, error: "iPhone non risponde. Riprova.")
      }
      session.sendMessage(
        ["command": data],
        replyHandler: { @Sendable [weak self] response in
          let data = response["snapshot"] as? Data
          let error = response["error"] as? String
          Task { @MainActor in self?.finished(command.id, data: data, error: error) }
        },
        errorHandler: { @Sendable [weak self] _ in
          Task { @MainActor in
            self?.finished(
              command.id, data: nil, error: "Collegamento con iPhone interrotto. Riprova.")
          }
        })
    }
    private func finished(_ id: UUID, data: Data?, error: String?) {
      guard activeRequest == id else { return }
      activeRequest = nil
      pending = false
      timeout?.cancel()
      timeout = nil
      reachable = WCSession.default.isReachable
      if let data, let value = try? WatchSnapshot.decode(data) { accept(value) }
      message = error
    }
    nonisolated func session(
      _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?
    ) {
      let data = session.receivedApplicationContext["snapshot"] as? Data
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.reachable = WCSession.default.isReachable
        if let data, let value = try? WatchSnapshot.decode(data) { self.accept(value) }
        #if os(iOS)
          self.publish(self.snapshot)
          self.onAvailabilityChanged?()
        #endif
        #if os(watchOS)
          if self.reachable { self.send(.refresh) }
        #endif
      }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.reachable = WCSession.default.isReachable
        #if os(watchOS)
          if self.reachable { self.send(.refresh) }
        #endif
      }
    }
    nonisolated func session(
      _ session: WCSession, didReceiveApplicationContext context: [String: Any]
    ) {
      guard let data = context["snapshot"] as? Data,
        let value = try? WatchSnapshot.decode(data)
      else { return }
      Task { @MainActor [weak self] in self?.accept(value) }
    }
    nonisolated func session(
      _ session: WCSession, didReceiveMessage message: [String: Any],
      replyHandler: @escaping ([String: Any]) -> Void
    ) {
      let box = WatchReplyBox(replyHandler)
      guard let data = message["command"] as? Data,
        let command = try? WatchCommand.decode(data)
      else {
        box.reply(["error": "Comando non riconosciuto."])
        return
      }
      Task { @MainActor [weak self] in
        guard let self else {
          box.reply(["error": "App non disponibile."])
          return
        }
        if let old = self.replies[command.id] {
          box.reply(old)
          return
        }
        let result: [String: Any]
        do {
          guard let handler = self.onCommand else { throw WatchCommandError.malformed }
          let value = try handler(command)
          result = ["snapshot": try value.encoded()]
        } catch { result = ["error": error.localizedDescription] }
        self.replies[command.id] = result
        self.replyOrder.append(command.id)
        while self.replyOrder.count > 32 {
          self.replies.removeValue(forKey: self.replyOrder.removeFirst())
        }
        box.reply(result)
      }
    }
    #if os(iOS)
      nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
      nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
      nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.publish(self.snapshot)
          self.onAvailabilityChanged?()
        }
      }
    #endif
  }
#endif

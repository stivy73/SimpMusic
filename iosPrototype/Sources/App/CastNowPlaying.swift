#if os(iOS)
  import Foundation
  import MediaPlayer
  import NowPlaying
  import UIKit

  @MainActor
  final class CastNowPlaying {
    private var backend: CastSystemSessionController?
    private var previousLegacy: [String: Any]?
    private var desired: CastRemoteState?
    private var draining: Task<Void, Never>?
    private var last: CastRemoteState?
    private var pinTask: Task<Void, Never>?
    private var pins: [String: Data] = [:]
    private var pinRetryAfter: [String: Date] = [:]
    private var pinErrors: [String: String] = [:]
    private var retryAfter = Date.distantPast
    private var promotionRevision = 0
    private var appliedPromotionRevision = -1
    private var mayPromote = true
    var published: Bool { desired != nil && backend?.registered == true }
    var isPrimary: Bool { desired != nil && backend?.isPrimary == true }
    var suppressesLegacy: Bool { desired != nil && backend?.suppressesLegacy == true }
    private(set) var diagnostic = "Sessione remota non avviata"

    #if DEBUG
      func verifySystemSession() async -> String {
        guard #available(iOS 27, *) else { return "FAIL iOS 27 required" }
        let value = CastRemoteState(id: "notenarrate-cast-qa", receiverSession: "qa-receiver",
          host: "192.168.255.254", port: 8009, certificate: Data(repeating: 1, count: 32),
          deviceName: "Chromecast QA", trackID: "qa-track", title: "Brano Cast QA", artist: "NoteNarrate",
          artwork: nil, duration: 240, position: 60, timestamp: Date(), playback: "PLAYING", volume: 0.5)
        pins[value.host + ":8009:" + value.receiverSession] = value.certificate
        publish(value)
        for _ in 0..<100 {
          if published || diagnostic.hasPrefix("Now Playing Cast:") { break }
          try? await Task.sleep(for: .milliseconds(100))
        }
        let available = (try? await RemoteMediaSession<CastRemoteState>.sessions())?
          .contains(where: { $0.id == backend?.sessionID }) == true
        let result = published && isPrimary && available
          ? "PASS remote Cast system session primary, finite clock, extension registered" : "FAIL " + diagnostic
        end()
        for _ in 0..<50 where backend?.registered == true { try? await Task.sleep(for: .milliseconds(100)) }
        return result
      }
    #endif

    func refresh() {
      promotionRevision += 1; retryAfter = .distantPast
      if desired == nil { desired = last }
      if #available(iOS 27, *), desired != nil { drain() }
    }

    func publish(_ value: CastRemoteState, allowPromotion: Bool = true) {
      guard #available(iOS 27, *) else {
        diagnostic = "La scheda Chromecast remota richiede iOS 27"
        return
      }
      if !mayPromote && allowPromotion { promotionRevision += 1; retryAfter = .distantPast }
      mayPromote = allowPromotion
      var value = value
      let endpoint = value.host + ":" + String(value.port) + ":" + value.receiverSession
      value.certificate = pins[endpoint] ?? Data()
      if value.certificate.isEmpty, pinTask == nil, Date() >= (pinRetryAfter[endpoint] ?? .distantPast) {
        pinTask = Task { [weak self] in
          let channel = CastDeviceChannel(host: value.host, port: value.port, pin: nil)
          do {
            let pin = try await channel.captureCertificate(receiverSession: value.receiverSession)
            guard let self, !Task.isCancelled else { return }
            self.pins[endpoint] = pin; self.pinErrors[endpoint] = nil
          } catch {
            guard let self, !Task.isCancelled else { return }
            self.pinRetryAfter[endpoint] = Date().addingTimeInterval(30)
            self.pinErrors[endpoint] = CastControlDiagnostics.failure(error)
          }
          self?.pinTask = nil
        }
      }
      updateDiagnostic(value)
      let needsFocus = mayPromote && UIApplication.shared.applicationState == .active
        && (!isPrimary || promotionRevision != appliedPromotionRevision)
      if let last, !needsFocus {
        let predicted = last.position + (last.playback == "PLAYING" ? Date().timeIntervalSince(last.timestamp) : 0)
        var comparable = value; comparable.position = last.position; comparable.timestamp = last.timestamp
        if comparable == last, abs(predicted - value.position) < 1,
          Date().timeIntervalSince(last.timestamp) < 10 { return }
      }
      desired = value
      drain()
    }

    func end() {
      desired = nil; last = nil; pinTask?.cancel(); pinTask = nil
      retryAfter = .distantPast; appliedPromotionRevision = -1
      pinRetryAfter.removeAll(); pins.removeAll(); pinErrors.removeAll()
      diagnostic = "Sessione Chromecast chiusa"
      if #available(iOS 27, *) { drain() }
    }

    private func updateDiagnostic(_ value: CastRemoteState) {
      guard let backend, backend.registered else { return }
      diagnostic = backend.isPrimary ? "Scheda Cast principale nel sistema" : "Sessione Cast registrata; non principale"
      if let error = backend.lastError { diagnostic += "; attivazione: " + String(describing: error) }
      if value.certificate.count == 32 { diagnostic += "; comandi collegati" }
      else {
        let endpoint = value.host + ":" + String(value.port) + ":" + value.receiverSession
        diagnostic += "; comandi non collegati: " + (pinErrors[endpoint] ?? "verifica certificato in corso")
      }
    }

    @available(iOS 27, *)
    private func controller() -> CastSystemSessionController {
      if let backend { return backend }
      let backend = CastSystemSessionController(driver: AppleCastSystemDriver(), beginHandoff: { [weak self] in
        guard let self else { return }
        self.previousLegacy = MPNowPlayingInfoCenter.default().nowPlayingInfo
        // Clear BEFORE promotion. Clearing after promotion can remove the new
        // system card belonging to this same app.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      }, finishHandoff: { [weak self] success in
        guard let self else { return }
        if !success { MPNowPlayingInfoCenter.default().nowPlayingInfo = self.previousLegacy }
        self.previousLegacy = nil
      })
      self.backend = backend
      return backend
    }

    @available(iOS 27, *)
    private func drain() {
      guard draining == nil, desired == nil || Date() >= retryAfter else { return }
      draining = Task { [weak self] in
        guard let self else { return }
        defer { self.draining = nil }
        while true {
          let value = self.desired
          let revision = self.promotionRevision
          do {
            if let value {
              let foreground = self.mayPromote && UIApplication.shared.applicationState == .active
              try await self.controller().publish(value, foreground: foreground,
                forcePromotion: revision != self.appliedPromotionRevision,
                now: ProcessInfo.processInfo.systemUptime)
              if foreground { self.appliedPromotionRevision = revision }
              self.last = value
              self.updateDiagnostic(value)
            } else { await self.backend?.end() }
          } catch {
            self.diagnostic = "Now Playing Cast: " + String(describing: error)
            self.retryAfter = Date().addingTimeInterval(5)
            break
          }
          if self.desired == value && self.promotionRevision == revision { break }
        }
      }
    }
  }

  @available(iOS 27, *) @MainActor
  private struct AppleCastSystemDriver: CastSystemSessionDriver {
    func sessions() async throws -> [any CastSystemSessionHandle] {
      try await RemoteMediaSession<CastRemoteState>.sessions().map { AppleCastSystemHandle($0) }
    }
    func start(_ state: CastRemoteState) async throws -> any CastSystemSessionHandle {
      AppleCastSystemHandle(try await RemoteMediaSession<CastRemoteState>.start(attributes: state))
    }
  }

  @available(iOS 27, *) @MainActor
  private final class AppleCastSystemHandle: CastSystemSessionHandle {
    private let value: RemoteMediaSession<CastRemoteState>
    init(_ value: RemoteMediaSession<CastRemoteState>) { self.value = value }
    var id: String { value.id }
    var isPrimary: Bool { value.isSystemPrimary }
    func update(_ state: CastRemoteState) async throws {
      do { try await value.update(state) }
      catch RemoteMediaSessionError.invalidAttributes { throw CastSystemSessionError.differentAttributes }
    }
    func promote() async throws {
      try await value.requestToBecomeSystemPrimary()
      // The primary-state observation can arrive after the request returns.
      // Keep the handoff protected until that observation has had time to land.
      for _ in 0..<20 where !value.isSystemPrimary {
        try await Task.sleep(for: .milliseconds(50))
      }
    }
    func end() async throws { try await value.end() }
  }
#endif

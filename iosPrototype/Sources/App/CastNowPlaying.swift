#if os(iOS)
  import Foundation
  import NowPlaying
  import UIKit

  @MainActor
  final class CastNowPlaying {
    private var session: Any?
    private var desired: CastRemoteState?
    private var draining: Task<Void, Never>?
    private var last: CastRemoteState?
    private var pinTask: Task<Void, Never>?
    private var pins: [String: Data] = [:]
    private var pinRetryAfter: [String: Date] = [:]
    private var retryAfter = Date.distantPast
    private(set) var published = false
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
        let active = (session as? RemoteMediaSession<CastRemoteState>)?.isSystemPrimary == true
        let available = (try? await RemoteMediaSession<CastRemoteState>.sessions())?.contains(where: { $0.id == (session as? RemoteMediaSession<CastRemoteState>)?.id }) == true
        let result = published && active && available ? "PASS remote Cast system session primary, finite clock, extension registered" : "FAIL " + diagnostic
        end()
        for _ in 0..<50 where published { try? await Task.sleep(for: .milliseconds(100)) }
        return result
      }
    #endif

    func publish(_ value: CastRemoteState) {
      guard #available(iOS 27, *) else {
        diagnostic = "La scheda Chromecast remota richiede iOS 27"
        return
      }
      var value = value
      let endpoint = value.host + ":" + String(value.port) + ":" + value.receiverSession
      value.certificate = pins[endpoint] ?? Data()
      if value.certificate.isEmpty, pinTask == nil, Date() >= (pinRetryAfter[endpoint] ?? .distantPast) {
        pinTask = Task { [weak self] in
          let channel = CastDeviceChannel(host: value.host, port: value.port, pin: nil)
          do {
            let pin = try await channel.captureCertificate(receiverSession: value.receiverSession)
            guard let self, !Task.isCancelled else { return }
            self.pins[endpoint] = pin
          } catch {
            guard let self, !Task.isCancelled else { return }
            self.pinRetryAfter[endpoint] = Date().addingTimeInterval(30)
            self.diagnostic = "Scheda Cast disponibile; collegamento comandi da verificare sul ricevitore"
          }
          self?.pinTask = nil
        }
      }
      if let last {
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
      retryAfter = .distantPast
      pinRetryAfter.removeAll(); pins.removeAll()
      if #available(iOS 27, *) { drain() }
    }

    @available(iOS 27, *)
    private func drain() {
      guard draining == nil, desired == nil || Date() >= retryAfter else { return }
      draining = Task { [weak self] in
        guard let self else { return }
        defer { self.draining = nil }
        while true {
          let value = self.desired
          do {
            if let value {
              var current = self.session as? RemoteMediaSession<CastRemoteState>
              if current == nil || self.last?.id != value.id {
                if let current { try await current.end() }
                current = try await RemoteMediaSession<CastRemoteState>.start(attributes: value)
                self.session = current
              } else { try await current?.update(value) }
              self.last = value; self.published = true
              do {
                if UIApplication.shared.applicationState == .active, current?.isSystemPrimary == false {
                  try await current?.requestToBecomeSystemPrimary()
                }
                self.diagnostic = current?.isSystemPrimary == true ? "Scheda Cast attiva nel blocco schermo" : "Sessione Cast pubblicata; scheda gestita da iOS"
              } catch {
                self.diagnostic = "Sessione Cast pubblicata; iOS non ha ancora attivato la scheda: " + String(describing: error)
              }
            } else {
              if let current = self.session as? RemoteMediaSession<CastRemoteState> { try await current.end() }
              self.session = nil; self.published = false
            }
          } catch {
            self.diagnostic = "Now Playing Cast: " + String(describing: error)
            self.published = false
            self.retryAfter = Date().addingTimeInterval(30)
            break
          }
          if self.desired == value { break }
        }
      }
    }
  }
#endif

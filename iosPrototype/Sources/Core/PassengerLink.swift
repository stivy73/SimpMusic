import Combine
import Foundation
@preconcurrency import Network
import Security

/// A local, TLS-PSK authenticated star: only the host plays audio. No remote server or login.
@MainActor
public final class PassengerLink: ObservableObject {
  public enum Mode: Equatable {
    case idle, hosting, browsing, connecting, awaitingApproval, connected
  }
  public struct NearbyHost: Identifiable, Equatable {
    public let id: UUID
    public var label: String { "Auto · " + String(id.uuidString.prefix(6)) }
  }
  public struct Peer: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var approved: Bool
  }
  public static let serviceType = "_nnpassenger._tcp"
  @Published public private(set) var mode: Mode = .idle
  @Published public private(set) var invitation: PassengerInvitation?
  @Published public private(set) var hosts: [NearbyHost] = []
  @Published public private(set) var peers: [Peer] = []
  @Published public private(set) var playback = PassengerPlayback()
  @Published public private(set) var pendingRequest: UUID?
  @Published public private(set) var receipt: PassengerReceipt?
  @Published public var error: String?
  public var onSelection: ((PassengerSelection) -> PassengerReceipt)?
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var endpoints: [UUID: NWEndpoint] = [:]
  private var links: [UUID: Link] = [:]
  private var guestID: UUID?
  var connectionID: UUID? { guestID }
  private var ownName = "Passeggero"
  private var desiredInvitation: PassengerInvitation?
  private var heartbeat: Task<Void, Never>?
  private var requestTimer: Task<Void, Never>?
  private var revision = UUID()
  private var ledger = PassengerRequestLedger()
  private var lastRequest: [UUID: Date] = [:]
  private var lastResponse = Date()
  private(set) var listeningPort: NWEndpoint.Port?

  private final class Link {
    let connection: NWConnection
    var buffer = PassengerFrameBuffer()
    var joined = false
    var approved = false
    var sentBytes = 0
    var deadline: Task<Void, Never>?
    init(_ connection: NWConnection) { self.connection = connection }
  }

  public init() {}
  public var canSend: Bool { mode == .connected && pendingRequest == nil }
  public var isPassenger: Bool {
    mode == .connecting || mode == .awaitingApproval || mode == .connected
  }
  public var status: String {
    switch mode {
    case .idle: "Nessuna sessione"
    case .hosting: "Telefono principale · \(peers.filter(\.approved).count) passeggeri"
    case .browsing: "Cerco le auto vicine…"
    case .connecting: "Collegamento protetto…"
    case .awaitingApproval: "Attendi la conferma sul telefono principale"
    case .connected: "Collegato all’auto · audio sul telefono principale"
    }
  }

  public func startHosting() {
    stop()
    let invite = PassengerInvitation()
    invitation = invite
    mode = .hosting
    let generation = revision
    do {
      let listener = try NWListener(using: Self.parameters(invite))
      self.listener = listener
      listener.service = .init(name: invite.serviceName, type: Self.serviceType)
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in
          guard let self, self.revision == generation, self.mode == .hosting,
            self.links.count < 4
          else {
            connection.cancel()
            return
          }
          self.accept(connection)
        }
      }
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        Task { @MainActor in
          guard let self, self.revision == generation else { return }
          if case .ready = state {
            self.listeningPort = listener?.port
            self.error = nil
          }
          if case .failed = state {
            self.fail("Impossibile aprire la sessione. Verifica Wi-Fi e il permesso Rete locale.")
          }
          if case .waiting = state {
            self.error =
              "Sessione in attesa della rete. Verifica Wi-Fi e Rete locale nelle impostazioni di iOS."
          }
        }
      }
      listener.start(queue: .main)
      startHeartbeat()
    } catch { fail("Impossibile aprire la sessione locale. Riprova.") }
  }

  public func browse(name: String) {
    stop()
    ownName = Self.safeName(name)
    mode = .browsing
    startBrowser()
  }

  public func join(text: String, name: String) {
    do {
      let invite = try PassengerInvitation(text: text)
      browse(name: name)
      desiredInvitation = invite
      connectIfDiscovered()
    } catch { self.error = error.localizedDescription }
  }

  public func join(host: NearbyHost, code: String, name: String) {
    do {
      let invite = try PassengerInvitation(sessionID: host.id, code: code)
      ownName = Self.safeName(name)
      desiredInvitation = invite
      connectIfDiscovered()
    } catch { self.error = error.localizedDescription }
  }

  private func startBrowser() {
    let generation = revision
    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
    self.browser = browser
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      Task { @MainActor in
        guard let self, self.revision == generation else { return }
        var found: [UUID: NWEndpoint] = [:]
        for result in results {
          guard case .service(let name, _, _, _) = result.endpoint, name.hasPrefix("NN-"),
            let id = UUID(uuidString: String(name.dropFirst(3)))
          else { continue }
          found[id] = result.endpoint
        }
        self.endpoints = found
        self.hosts = found.keys.sorted { $0.uuidString < $1.uuidString }.map { NearbyHost(id: $0) }
        self.connectIfDiscovered()
      }
    }
    browser.stateUpdateHandler = { [weak self] state in
      Task { @MainActor in
        guard let self, self.revision == generation else { return }
        if case .failed = state {
          self.error = "Ricerca non disponibile. Abilita Wi-Fi e Rete locale per NoteNarrate."
        }
        if case .waiting = state {
          self.error =
            "Ricerca in attesa della rete. Verifica il permesso Rete locale nelle impostazioni di iOS."
        }
      }
    }
    browser.start(queue: .main)
  }

  private func connectIfDiscovered() {
    guard mode == .browsing, let invite = desiredInvitation,
      let endpoint = endpoints[invite.sessionID]
    else { return }
    connect(invitation: invite, endpoint: endpoint)
  }

  // Internal for loopback transport integration tests; production endpoints come only from Bonjour.
  func connect(invitation invite: PassengerInvitation, endpoint: NWEndpoint) {
    mode = .connecting
    error = nil
    invitation = invite
    desiredInvitation = nil
    let connection = NWConnection(to: endpoint, using: Self.parameters(invite))
    let id = UUID()
    guestID = id
    install(connection, id: id)
  }

  private func accept(_ connection: NWConnection) { install(connection, id: UUID()) }

  private func install(_ connection: NWConnection, id: UUID) {
    let link = Link(connection)
    links[id] = link
    let generation = revision
    connection.stateUpdateHandler = { [weak self] state in
      Task { @MainActor in
        guard let self, self.revision == generation, self.links[id] != nil else { return }
        switch state {
        case .ready:
          self.setDeadline(id, seconds: 90)
          self.receive(id)
          if id == self.guestID {
            self.mode = .awaitingApproval
            self.send(.hello(self.ownName), to: id)
          }
        case .failed, .cancelled, .waiting:
          self.disconnect(
            id,
            message: "Collegamento interrotto o codice errato. Riapri la sessione e riconnettiti.")
        default: break
        }
      }
    }
    setDeadline(id, seconds: 10)
    connection.start(queue: .main)
  }

  private func setDeadline(_ id: UUID, seconds: Double) {
    guard let link = links[id] else { return }
    link.deadline?.cancel()
    link.deadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled, let self, self.links[id]?.approved == false else { return }
      self.disconnect(
        id, message: "Collegamento o autorizzazione scaduti. Verifica il codice e riconnettiti.")
    }
  }

  private func receive(_ id: UUID) {
    guard let link = links[id] else { return }
    link.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      [weak self] data, _, complete, error in
      Task { @MainActor in
        guard let self, let live = self.links[id] else { return }
        do {
          if let data {
            for frame in try live.buffer.append(data) {
              try self.handle(PassengerMessage.decode(frame).body, from: id)
            }
          }
          if complete || error != nil {
            self.disconnect(id)
            return
          }
          self.receive(id)
        } catch { self.disconnect(id, message: error.localizedDescription) }
      }
    }
  }

  private func handle(_ body: PassengerBody, from id: UUID) throws {
    guard let link = links[id] else { return }
    if mode == .hosting {
      switch body {
      case .hello(let name):
        guard !link.joined, !name.isEmpty, name.count <= 40 else { throw PassengerError.malformed }
        link.joined = true
        peers.append(Peer(id: id, name: Self.safeName(name), approved: false))
      case .selection(let request):
        guard link.approved, let invite = invitation else { throw PassengerError.notApproved }
        try request.validate(sessionID: invite.sessionID)
        if let reply = ledger.reply(for: request.id) {
          send(.receipt(reply), to: id)
          return
        }
        guard ledger.hasCapacity() else { throw PassengerError.busy }
        let reply: PassengerReceipt
        if lastRequest[id].map({ Date().timeIntervalSince($0) < 1 }) == true {
          reply = PassengerReceipt(
            requestID: request.id, success: false,
            message: "Attendi un istante prima della prossima selezione.")
        } else {
          lastRequest[id] = Date()
          reply =
            onSelection?(request)
            ?? PassengerReceipt(
              requestID: request.id, success: false, message: "Player non disponibile.")
        }
        ledger.remember(reply)
        send(.receipt(reply), to: id)
        broadcast()
      case .goodbye: disconnect(id)
      default: throw PassengerError.malformed
      }
    } else {
      guard id == guestID else { throw PassengerError.malformed }
      lastResponse = Date()
      switch body {
      case .approved:
        guard mode == .awaitingApproval else { throw PassengerError.malformed }
        link.approved = true
        link.deadline?.cancel()
        error = nil
        mode = .connected
        startHeartbeat()
      case .state(let state):
        guard link.approved, state.title.count <= 160, state.artist.count <= 160,
          (0...5000).contains(state.queueCount)
        else { throw PassengerError.malformed }
        playback = state
      case .receipt(let reply):
        guard link.approved, reply.message.count <= 240 else { throw PassengerError.malformed }
        if reply.requestID == pendingRequest {
          requestTimer?.cancel()
          pendingRequest = nil
          receipt = reply
        }
      case .goodbye: disconnect(id, message: "Il telefono principale ha chiuso il collegamento.")
      default: throw PassengerError.malformed
      }
    }
  }

  public func approve(_ id: UUID) {
    guard mode == .hosting, let link = links[id], link.joined, !link.approved,
      let index = peers.firstIndex(where: { $0.id == id })
    else { return }
    link.approved = true
    link.deadline?.cancel()
    peers[index].approved = true
    send(.approved, to: id)
    send(.state(playback), to: id)
  }
  public func remove(_ id: UUID) { disconnect(id) }

  public func submit(action: PassengerSelection.Action, tracks: [PassengerTrack]) {
    do {
      guard mode == .connected, let id = guestID, let invite = invitation else {
        throw PassengerError.disconnected
      }
      guard pendingRequest == nil else { throw PassengerError.busy }
      let request = PassengerSelection(sessionID: invite.sessionID, action: action, tracks: tracks)
      try request.validate(sessionID: invite.sessionID)
      pendingRequest = request.id
      receipt = nil
      error = nil
      send(.selection(request), to: id)
      requestTimer = Task { [weak self] in
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled, let self, self.pendingRequest == request.id else { return }
        // No automatic replay: a missing acknowledgement does not prove the host rejected the music.
        self.error =
          "Conferma non ricevuta. Controlla la coda dell’auto prima di ripetere la richiesta."
        self.pendingRequest = nil
      }
    } catch { self.error = error.localizedDescription }
  }

  public func publish(_ state: PassengerPlayback) {
    guard playback != state else { return }
    playback = state
    if mode == .hosting { broadcast() }
  }
  private func broadcast() {
    for (id, link) in links where link.approved { send(.state(playback), to: id) }
  }
  func send(_ body: PassengerBody, to id: UUID) {
    guard let link = links[id], let data = try? PassengerMessage(body).encoded() else { return }
    guard link.sentBytes + data.count <= PassengerFrameBuffer.maximum * 2 else {
      disconnect(id)
      return
    }
    link.sentBytes += data.count
    link.connection.send(
      content: data,
      completion: .contentProcessed { [weak self] error in
        Task { @MainActor in
          guard let self, let live = self.links[id] else { return }
          live.sentBytes = max(0, live.sentBytes - data.count)
          if error != nil { self.disconnect(id) }
        }
      })
  }

  private func startHeartbeat() {
    heartbeat?.cancel()
    heartbeat = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled, let self else { return }
        if self.mode == .hosting {
          self.broadcast()
        } else if self.mode == .connected, Date().timeIntervalSince(self.lastResponse) > 30,
          let id = self.guestID
        {
          self.disconnect(
            id, message: "Il telefono principale non risponde. Riapri NoteNarrate e riconnettiti.")
        }
      }
    }
  }
  private func disconnect(_ id: UUID, message: String? = nil) {
    guard let link = links.removeValue(forKey: id) else { return }
    link.deadline?.cancel()
    link.connection.stateUpdateHandler = nil
    link.connection.cancel()
    peers.removeAll { $0.id == id }
    lastRequest.removeValue(forKey: id)
    if id == guestID {
      stop()
      error = message ?? PassengerError.disconnected.localizedDescription
    }
  }
  private func fail(_ message: String) {
    stop()
    error = message
  }
  public func stop() {
    revision = UUID()
    heartbeat?.cancel()
    requestTimer?.cancel()
    listener?.cancel()
    browser?.cancel()
    for link in links.values {
      link.deadline?.cancel()
      link.connection.stateUpdateHandler = nil
      link.connection.cancel()
    }
    links = [:]
    peers = []
    hosts = []
    endpoints = [:]
    guestID = nil
    listener = nil
    browser = nil
    invitation = nil
    desiredInvitation = nil
    pendingRequest = nil
    receipt = nil
    error = nil
    mode = .idle
    listeningPort = nil
    ledger = PassengerRequestLedger()
    lastRequest = [:]
    playback = PassengerPlayback()
  }
  private static func safeName(_ name: String) -> String {
    let value = String(
      name.filter {
        !$0.isNewline && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      }.prefix(40)
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "Passeggero" : value
  }
  private static func parameters(_ invitation: PassengerInvitation) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let options = tls.securityProtocolOptions
    let key = invitation.key.withUnsafeBytes { DispatchData(bytes: $0) }
    let identity = Data(invitation.sessionID.uuidString.utf8).withUnsafeBytes {
      DispatchData(bytes: $0)
    }
    sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
    sec_protocol_options_append_tls_ciphersuite(
      options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
    sec_protocol_options_add_pre_shared_key(
      options, key as __DispatchData, identity as __DispatchData)
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    tcp.connectionTimeout = 15
    let parameters = NWParameters(tls: tls, tcp: tcp)
    parameters.includePeerToPeer = true
    parameters.prohibitedInterfaceTypes = [.cellular]
    return parameters
  }
}

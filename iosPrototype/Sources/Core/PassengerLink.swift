import Combine
import Foundation
@preconcurrency import Network
import Security

/// A local, QR-authenticated star: TLS over Wi-Fi or encrypted Bluetooth. Only the host plays audio.
@MainActor
public final class PassengerLink: ObservableObject {
  public enum Mode: Equatable {
    case idle, hosting, browsing, connecting, joining, connected
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
  @Published public private(set) var diagnostics: [String] = []
  private var diagnosticStart = ProcessInfo.processInfo.systemUptime
  public var diagnosticReport: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "test"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "test"
    return
      "NoteNarrate \(version) (\(build))\n\(ProcessInfo.processInfo.operatingSystemVersionString)\n\(status)\n"
      + "Collegamenti attivi: Wi-Fi \(links.values.filter { $0.connection != nil }.count), Bluetooth \(links.values.filter { $0.connection == nil }.count)\n"
      + diagnostics.joined(separator: "\n")
  }
  private func record(_ event: String) {
    diagnostics.append(
      "+\(Int(max(0, ProcessInfo.processInfo.systemUptime - diagnosticStart)))s \(event)")
    if diagnostics.count > 60 { diagnostics.removeFirst(diagnostics.count - 60) }
  }
  private static func networkError(_ error: NWError) -> String {
    switch error {
    case .posix(let code): "POSIX \(code.rawValue)"
    case .dns(let code): "DNS \(code)"
    case .tls(let code): "TLS \(code)"
    default: "rete non disponibile"
    }
  }
  public var onSelection: ((PassengerSelection) -> PassengerReceipt)?
  #if DEBUG
    var serviceNameOverride: ((PassengerInvitation) -> String)?
    var bluetoothFactory: (() -> any PassengerBluetoothTransport)?
    var bluetoothFallbackDelay: Double = 4
  #endif
  private var listener: NWListener?
  private var listenerRevision = UUID()
  private var recovery: Task<Void, Never>?
  private var discoveryTimeout: Task<Void, Never>?
  private var recoveryAttempts = 0
  private var browser: NWBrowser?
  private var bluetooth: (any PassengerBluetoothTransport)?
  private var bluetoothFallback: Task<Void, Never>?
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
    let connection: NWConnection?
    var buffer = PassengerFrameBuffer()
    var joined = false
    var approved = false
    var sentBytes = 0
    var deadline: Task<Void, Never>?
    init(_ connection: NWConnection? = nil) { self.connection = connection }
  }

  public init() {}
  public var canSend: Bool { mode == .connected && pendingRequest == nil }
  public var isPassenger: Bool {
    mode == .connecting || mode == .joining || mode == .connected
  }
  public var status: String {
    switch mode {
    case .idle: "Nessuna sessione"
    case .hosting: "Telefono principale · \(peers.filter(\.approved).count) passeggeri"
    case .browsing: "Cerco le auto vicine…"
    case .connecting: "Collegamento protetto…"
    case .joining: "Completo il collegamento all’auto…"
    case .connected:
      "Collegato all’auto via \(guestID.flatMap { links[$0] }?.connection == nil ? "Bluetooth" : "Wi-Fi") · audio sul telefono principale"
    }
  }

  public func startHosting() {
    stop()
    resetDiagnostics()
    record("Principale: apertura sessione")
    let invite = PassengerInvitation()
    invitation = invite
    mode = .hosting
    openListener(invite)
    if bluetoothAvailable {
      bluetooth = makeBluetooth()
      bluetooth?.host(invite)
    }
    startHeartbeat()
  }

  /// Reuse a live session or create one when CarPlay connects after an app/phone restart.
  public func activateForCarPlay() {
    if mode == .hosting, invitation != nil {
      resumeHosting(force: true)
      record("CarPlay: sessione esistente ripresa")
    } else {
      startHosting()
      record("CarPlay: sessione avviata automaticamente")
    }
  }

  /// Re-advertise the same invitation after a foreground/CarPlay network transition.
  /// Established connections and the deduplication ledger stay intact.
  public func resumeHosting(force: Bool = false) {
    guard mode == .hosting, let invite = invitation else { return }
    if !force, let listener, case .ready = listener.state { return }
    record("Principale: ripristino annuncio")
    recoveryAttempts = 0
    openListener(invite)
  }

  private func openListener(_ invite: PassengerInvitation) {
    recovery?.cancel()
    listenerRevision = UUID()
    let listenerID = listenerRevision
    listener?.cancel()
    listeningPort = nil
    let generation = revision
    do {
      let listener = try NWListener(using: Self.parameters(invite))
      self.listener = listener
      #if DEBUG
        let serviceName = serviceNameOverride?(invite) ?? invite.serviceName
      #else
        let serviceName = invite.serviceName
      #endif
      listener.service = .init(name: serviceName, type: Self.serviceType)
      listener.serviceRegistrationUpdateHandler = { @Sendable [weak self] change in
        Task { @MainActor in
          guard let self, self.listenerRevision == listenerID else { return }
          switch change {
          case .add(let endpoint):
            if case .service(let name, _, _, _) = endpoint {
              self.record(
                "Bonjour: annuncio pubblicato; suffisso \(PassengerInvitation.advertisedSession(name)?.suffix ?? -1)"
              )
            }
          case .remove: self.record("Bonjour: annuncio rimosso")
          @unknown default: break
          }
        }
      }
      listener.newConnectionHandler = { @Sendable [weak self] connection in
        Task { @MainActor in
          guard let self, self.revision == generation, self.listenerRevision == listenerID,
            self.mode == .hosting,
            self.links.count < 4
          else {
            connection.cancel()
            return
          }
          self.accept(connection)
          self.record("Principale: connessione ricevuta")
        }
      }
      listener.stateUpdateHandler = { @Sendable [weak self, weak listener] state in
        Task { @MainActor in
          guard let self, self.revision == generation, self.listenerRevision == listenerID else {
            return
          }
          if case .ready = state {
            self.record("Principale: listener pronto")
            self.recovery?.cancel()
            self.recoveryAttempts = 0
            self.listeningPort = listener?.port
            self.error = nil
          }
          if case .failed(let reason) = state {
            self.record("Principale: listener fallito, " + Self.networkError(reason))
            self.error = "Collegamento locale interrotto. Ripristino la sessione…"
            self.scheduleRecovery()
          }
          if case .waiting(let reason) = state {
            self.record("Principale: listener in attesa, " + Self.networkError(reason))
            self.error =
              "Sessione in attesa della rete. Verifica Wi-Fi e Rete locale nelle impostazioni di iOS."
            self.scheduleRecovery()
          }
        }
      }
      listener.start(queue: .main)
    } catch {
      self.error = "Impossibile riaprire il collegamento locale. Usa Ripristina collegamento."
      scheduleRecovery()
    }
  }

  private func scheduleRecovery() {
    guard recoveryAttempts < 3 else { return }
    recoveryAttempts += 1
    recovery?.cancel()
    recovery = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled, let self, self.mode == .hosting, let invite = self.invitation else {
        return
      }
      self.openListener(invite)
    }
  }

  public func browse(name: String) {
    stop()
    resetDiagnostics()
    record("Passeggero: avvio ricerca Bonjour")
    ownName = Self.safeName(name)
    mode = .browsing
    startBrowser()
  }

  public func join(text: String, name: String) {
    do {
      let invite = try PassengerInvitation(text: text)
      // Opening our own invitation, or scanning again while already linked, is a no-op.
      if invitation == invite, mode == .hosting || isPassenger {
        error = nil
        return
      }
      browse(name: name)
      waitForHost(invite)
      connectIfDiscovered()
    } catch { self.error = error.localizedDescription }
  }

  public func join(host: NearbyHost, code: String, name: String) {
    do {
      let invite = try PassengerInvitation(sessionID: host.id, code: code)
      ownName = Self.safeName(name)
      waitForHost(invite)
      connectIfDiscovered()
    } catch { self.error = error.localizedDescription }
  }

  private func waitForHost(_ invite: PassengerInvitation) {
    record("QR/invito valido: attendo annuncio dell’auto")
    desiredInvitation = invite
    bluetoothFallback?.cancel()
    // Prefer existing Wi-Fi peers, but do not wait for a Wi-Fi discovery timeout in the car.
    // Core Bluetooth remains usable even when the phones have no shared IP network.
    #if DEBUG
      let fallbackDelay = bluetoothFallbackDelay
    #else
      let fallbackDelay: Double = 4
    #endif
    bluetoothFallback = Task { [weak self] in
      try? await Task.sleep(for: .seconds(fallbackDelay))
      guard !Task.isCancelled, let self, self.mode == .browsing,
        self.desiredInvitation == invite, self.bluetoothAvailable
      else { return }
      self.bluetooth = self.makeBluetooth()
      self.bluetooth?.join(invite)
    }
    discoveryTimeout?.cancel()
    discoveryTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(25))
      guard !Task.isCancelled, let self, self.mode == .browsing,
        self.desiredInvitation == invite
      else { return }
      self.error =
        "Auto non raggiungibile. Attiva Bluetooth e consenti l’accesso a NoteNarrate su entrambi gli iPhone. Tieni le app aperte e scansiona il QR attuale. Con CarPlay wireless il solo Wi-Fi acceso può non bastare."
      self.record("Timeout scoperta: auto richiesta non trovata")
    }
  }

  private func resetDiagnostics() {
    diagnosticStart = ProcessInfo.processInfo.systemUptime
    diagnostics = []
  }

  private var bluetoothAvailable: Bool {
    #if os(iOS)
      true
    #elseif DEBUG
      bluetoothFactory != nil
    #else
      false
    #endif
  }

  private func makeBluetooth() -> any PassengerBluetoothTransport {
    #if DEBUG
      let transport: any PassengerBluetoothTransport = bluetoothFactory?() ?? PassengerBluetooth()
    #else
      let transport = PassengerBluetooth()
    #endif
    let generation = revision
    transport.onDiagnostic = { [weak self] event in
      guard let self, self.revision == generation else { return }
      self.record(event)
    }
    transport.onReady = { [weak self] id in
      guard let self, self.revision == generation else { return false }
      if self.mode == .hosting {
        guard self.links.count < 4 else { return false }
        self.links[id] = Link()
        self.setDeadline(id, seconds: 90)
        self.record("Principale: collegamento Bluetooth ricevuto")
        return true
      }
      guard self.mode == .browsing, let invite = self.desiredInvitation else { return false }
      self.discoveryTimeout?.cancel()
      self.browser?.cancel()
      self.browser = nil
      self.invitation = invite
      self.desiredInvitation = nil
      self.guestID = id
      self.links[id] = Link()
      self.error = nil
      self.mode = .joining
      self.setDeadline(id, seconds: 90)
      self.record("Bluetooth: invio identità del passeggero")
      self.send(.hello(self.ownName), to: id)
      return true
    }
    transport.onData = { [weak self] id, data in
      guard let self, self.revision == generation, let link = self.links[id] else { return }
      do {
        for frame in try link.buffer.append(data) {
          guard self.links[id] != nil else { return }
          try self.handle(PassengerMessage.decode(frame).body, from: id)
        }
      } catch {
        self.disconnect(id, message: "Richiesta Bluetooth non valida. Riconnettiti con il QR.")
      }
    }
    transport.onClose = { [weak self] id in
      guard let self, self.revision == generation, self.links[id] != nil else { return }
      self.disconnect(id)
    }
    return transport
  }

  private func startBrowser() {
    let generation = revision
    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
    self.browser = browser
    browser.browseResultsChangedHandler = { @Sendable [weak self] results, _ in
      Task { @MainActor in
        guard let self, self.revision == generation else { return }
        var found: [UUID: NWEndpoint] = [:]
        var ranks: [UUID: Int] = [:]
        for result in results {
          guard case .service(let name, let type, let domain, _) = result.endpoint,
            let session = PassengerInvitation.advertisedSession(name)
          else { continue }
          guard session.suffix >= (ranks[session.id] ?? -1) else { continue }
          ranks[session.id] = session.suffix
          found[session.id] = .service(name: name, type: type, domain: domain, interface: nil)
        }
        self.record("Bonjour: \(results.count) annunci; \(found.count) sessioni riconosciute")
        self.endpoints = found
        self.hosts = found.keys.sorted { $0.uuidString < $1.uuidString }.map { NearbyHost(id: $0) }
        self.connectIfDiscovered()
      }
    }
    browser.stateUpdateHandler = { @Sendable [weak self] state in
      Task { @MainActor in
        guard let self, self.revision == generation, self.mode == .browsing else { return }
        if case .ready = state { self.record("Passeggero: ricerca pronta") }
        if case .failed(let reason) = state {
          self.record("Passeggero: ricerca fallita, " + Self.networkError(reason))
          self.error = "Ricerca non disponibile. Abilita Wi-Fi e Rete locale per NoteNarrate."
        }
        if case .waiting(let reason) = state {
          self.record("Passeggero: ricerca in attesa, " + Self.networkError(reason))
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
    record("Auto trovata: avvio connessione TLS")
    discoveryTimeout?.cancel()
    bluetoothFallback?.cancel()
    bluetooth?.stop()
    bluetooth = nil
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
    connection.stateUpdateHandler = { @Sendable [weak self] state in
      Task { @MainActor in
        guard let self, self.revision == generation, self.links[id] != nil else { return }
        switch state {
        case .ready:
          self.record("Connessione TLS pronta")
          self.setDeadline(id, seconds: 90)
          self.receive(id)
          if id == self.guestID {
            self.record("Invio identità del passeggero")
            self.mode = .joining
            self.send(.hello(self.ownName), to: id)
          }
        case .failed(let reason), .waiting(let reason):
          self.record("Connessione interrotta, " + Self.networkError(reason))
          self.disconnect(
            id,
            message: "Collegamento interrotto o codice errato. Riapri la sessione e riconnettiti.")
        case .cancelled:
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
        id, message: "Collegamento scaduto. Verifica il QR e riconnettiti.")
    }
  }

  private func receive(_ id: UUID) {
    guard let link = links[id], let connection = link.connection else { return }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
      @Sendable [weak self] data, _, complete, error in
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
        link.approved = true
        link.deadline?.cancel()
        peers.append(Peer(id: id, name: Self.safeName(name), approved: true))
        record("Principale: passeggero collegato automaticamente con invito valido")
        // Legacy wire name: this is the ready acknowledgement for authenticated older guests.
        send(.approved, to: id)
        send(.state(playback), to: id)
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
        guard mode == .joining else { throw PassengerError.malformed }
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
      let timeout: Double = links[id]?.connection == nil ? 60 : 15
      requestTimer = Task { [weak self] in
        try? await Task.sleep(for: .seconds(timeout))
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
    guard let connection = link.connection else {
      if bluetooth?.send(data, to: id) != true { disconnect(id) }
      return
    }
    guard link.sentBytes + data.count <= PassengerFrameBuffer.maximum * 2 else {
      disconnect(id)
      return
    }
    link.sentBytes += data.count
    connection.send(
      content: data,
      completion: .contentProcessed { @Sendable [weak self] error in
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
    record("Connessione chiusa")
    guard let link = links.removeValue(forKey: id) else { return }
    link.deadline?.cancel()
    link.connection?.stateUpdateHandler = nil
    link.connection?.cancel()
    if link.connection == nil { bluetooth?.close(id) }
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
    recovery?.cancel()
    discoveryTimeout?.cancel()
    bluetoothFallback?.cancel()
    bluetooth?.stop()
    bluetooth = nil
    recoveryAttempts = 0
    heartbeat?.cancel()
    requestTimer?.cancel()
    listener?.cancel()
    browser?.cancel()
    for link in links.values {
      link.deadline?.cancel()
      link.connection?.stateUpdateHandler = nil
      link.connection?.cancel()
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

import Foundation
import Network

public struct CastRemoteState: Codable, Equatable, Sendable {
  public var id: String
  public var receiverSession: String
  public var host: String
  public var port: UInt16
  public var certificate: Data
  public var deviceName: String
  public var trackID: String
  public var title: String
  public var artist: String
  public var artwork: URL?
  public var duration: Double
  public var position: Double
  public var timestamp: Date
  public var playback: String
  public var volume: Double
  public var mediaSessionID: Int? = nil
}

#if os(iOS)
  import NowPlaying
  @available(iOS 27, *)
  extension CastRemoteState: RemoteMediaSessionAttributes {}
#endif

public enum CastRemoteError: Error { case invalidDevice, invalidMessage, disconnected, timeout, changedSession, notConfirmed, rejected }

/// Cast V2 framing, based on Google's cast_channel.proto. No signed media URL
/// or account credential is needed to control an already selected receiver.
public enum CastWire {
  public static let connection = "urn:x-cast:com.google.cast.tp.connection"
  public static let receiver = "urn:x-cast:com.google.cast.receiver"
  public static let media = "urn:x-cast:com.google.cast.media"
  public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
  public static let limit = 1024 * 1024

  public static func frame(source: String, destination: String, namespace: String, json: Data) throws -> Data {
    guard json.count < limit / 2 else { throw CastRemoteError.invalidMessage }
    func field(_ number: UInt8, _ bytes: Data) -> Data {
      var result = Data([number << 3 | 2]); var count = bytes.count
      repeat { result.append(UInt8(count & 127) | (count > 127 ? 128 : 0)); count >>= 7 } while count > 0
      result.append(bytes); return result
    }
    var body = Data([8, 0])
    body.append(field(2, Data(source.utf8))); body.append(field(3, Data(destination.utf8)))
    body.append(field(4, Data(namespace.utf8))); body.append(contentsOf: [40, 0])
    body.append(field(6, json))
    var length = UInt32(body.count).bigEndian
    var result = withUnsafeBytes(of: &length) { Data($0) }; result.append(body); return result
  }

  public static func decode(_ body: Data) throws -> (namespace: String, json: Data) {
    let bytes = [UInt8](body); var cursor = 0; var namespace: String?; var json: Data?
    guard body.count <= limit else { throw CastRemoteError.invalidMessage }
    func number() throws -> Int {
      var result = 0
      for shift in stride(from: 0, to: 56, by: 7) {
        guard cursor < bytes.count else { throw CastRemoteError.invalidMessage }
        let byte = bytes[cursor]; cursor += 1; result |= Int(byte & 127) << shift
        if byte & 128 == 0 { return result }
      }
      throw CastRemoteError.invalidMessage
    }
    while cursor < bytes.count {
      let tag = try number()
      if tag & 7 == 0 { _ = try number() }
      else if tag & 7 == 2 {
        let count = try number()
        guard count <= bytes.count - cursor else { throw CastRemoteError.invalidMessage }
        let data = Data(bytes[cursor..<(cursor + count)]); cursor += count
        if tag >> 3 == 4 { namespace = String(data: data, encoding: .utf8) }
        if tag >> 3 == 6 { json = data }
      } else { throw CastRemoteError.invalidMessage }
    }
    guard let namespace, let json, (try? JSONSerialization.jsonObject(with: json)) != nil else {
      throw CastRemoteError.invalidMessage
    }
    return (namespace, json)
  }

  public static func localAddress(_ host: String) -> Bool {
    // Numeric, unicast LAN addresses only; never accept a URL, DNS name or public endpoint.
    let host = host.lowercased()
    if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:") {
      return IPv6Address(host) != nil
    }
    guard IPv4Address(host) != nil else { return false }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    return parts.count == 4 && (parts[0] == 10 || (parts[0] == 192 && parts[1] == 168)
      || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254))
  }
}

#if canImport(Security)
  import Security
  import CryptoKit

  protocol CastByteConnection: Sendable {
    func open(host: String, port: UInt16, pin: Data?) async throws -> Data
    func write(_ data: Data) async throws
    func read(_ count: Int) async throws -> Data
    func close() async
  }

  public enum CastControlDiagnostics {
    public static var latest: String {
      #if os(iOS)
        guard var query else { return "Diagnostica comandi non configurata" }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
          return status == errSecItemNotFound ? "Nessun comando registrato" : "Diagnostica comandi: Keychain \(status)"
        }
        return value
      #else
        return "Nessun comando registrato"
      #endif
    }
    static func record(_ command: String, _ stage: String) {
      #if os(iOS)
        guard ["PLAY", "PAUSE", "SEEK", "SET_VOLUME"].contains(command) else { return }
        guard var query else { return }
        let data = Data((Date().formatted(date: .omitted, time: .standard) + " · " + command + " · " + stage).utf8)
        let values = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, values as CFDictionary) == errSecItemNotFound {
          query[kSecValueData as String] = data
          query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          _ = SecItemAdd(query as CFDictionary, nil)
        }
      #endif
    }
    static func failure(_ error: Error) -> String {
      if let error = error as? CastRemoteError { return String(describing: error) }
      if let error = error as? NWError {
        switch error {
        case .posix(let code): return "rete POSIX " + String(code.rawValue)
        case .tls(let code): return "TLS " + String(code)
        case .dns(let code): return "DNS " + String(code)
        default: return "rete"
        }
      }
      return "errore di sistema"
    }
    #if os(iOS)
      private static var query: [String: Any]? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "CastControlKeychainGroup") as? String,
          !group.contains("$(") else { return nil }
        return [kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.stivy.notenarrate.cast-control",
          kSecAttrAccount as String: "last-result", kSecAttrAccessGroup as String: group]
      }
    #endif
  }

  /// One connection to the receiver chosen by the user. The app captures its
  /// certificate while the Cast SDK session is connected. The extension must
  /// match that exact pin; it never accepts arbitrary replacement certificates.
  public actor CastDeviceChannel {
    private let host: String
    private let port: UInt16
    private let pin: Data?
    private let connection: any CastByteConnection
    private let sender = "notenarrate-" + UUID().uuidString
    private var request = 0
    public init(host: String, port: UInt16, pin: Data?) {
      self.host = host; self.port = port; self.pin = pin
      self.connection = CastTLSConnection()
    }
    init(host: String, port: UInt16, pin: Data?, connection: any CastByteConnection) {
      self.host = host; self.port = port; self.pin = pin; self.connection = connection
    }
    public func close() async { await connection.close() }

    public func captureCertificate(receiverSession: String) async throws -> Data {
      do {
        let value = try await connect()
        _ = try await application(receiverSession)
        await close()
        return value
      } catch { await close(); throw error }
    }

    public func perform(_ command: String, value: Double? = nil, state: CastRemoteState) async throws -> CastRemoteState {
      guard pin?.count == 32 else { throw CastRemoteError.invalidDevice }
      var phase = "connessione TLS"
      CastControlDiagnostics.record(command, phase)
      do {
        _ = try await connect()
        phase = "verifica sessione ricevitore"
        CastControlDiagnostics.record(command, phase)
        let destination = try await application(state.receiverSession)
        _ = try await send(CastWire.connection, to: destination, payload: ["type": "CONNECT"])
        phase = "verifica sessione brano"
        let current = try await exchange(CastWire.media, to: destination, payload: ["type": "GET_STATUS"])
        let status = try mediaStatus(current, expectedID: state.mediaSessionID)
        guard let mediaID = status["mediaSessionId"] as? Int else { throw CastRemoteError.invalidMessage }
        if state.mediaSessionID == nil {
          guard let media = status["media"] as? [String: Any],
            let metadata = media["metadata"] as? [String: Any],
            metadata["notenarrateTrackID"] as? String == state.trackID
          else { throw CastRemoteError.changedSession }
        }
        var payload: [String: Any] = ["type": command, "mediaSessionId": mediaID]
        var receivedVolume: Double?
        phase = "invio comando"
        CastControlDiagnostics.record(command, phase)
        if command == "SET_VOLUME" {
          guard let value, value.isFinite else { throw CastRemoteError.invalidMessage }
          let receiverReply = try await exchange(CastWire.receiver, to: "receiver-0", payload: ["type": "SET_VOLUME", "volume": ["level": min(1, max(0, value)), "muted": false]])
          receivedVolume = ((receiverReply["status"] as? [String: Any])?["volume"] as? [String: Any])?["level"] as? Double
        } else {
          guard ["PLAY", "PAUSE", "SEEK"].contains(command) else { throw CastRemoteError.invalidMessage }
          if command == "SEEK" {
            guard let value, value.isFinite else { throw CastRemoteError.invalidMessage }
            payload["currentTime"] = min(state.duration, max(0, value))
          }
          // PLAY/PAUSE/SEEK have no mandatory direct reply. Confirm the actual
          // receiver state with GET_STATUS instead of awaiting their requestId.
          _ = try await send(CastWire.media, to: destination, payload: payload)
        }
        phase = "attesa conferma ricevitore"
        CastControlDiagnostics.record(command, phase)
        var result: [String: Any] = [:]
        var confirmed = false
        for attempt in 0..<3 {
          if attempt > 0 { try await Task.sleep(for: .milliseconds(150)) }
          let reply = try await exchange(CastWire.media, to: destination, payload: ["type": "GET_STATUS", "mediaSessionId": mediaID])
          result = try mediaStatus(reply, expectedID: mediaID)
          let playback = result["playerState"] as? String
          switch command {
          case "PAUSE": confirmed = playback == "PAUSED"
          case "PLAY": confirmed = playback == "PLAYING" || playback == "BUFFERING"
          case "SEEK": confirmed = (result["currentTime"] as? Double).map { abs($0 - min(state.duration, max(0, value ?? 0))) <= 3 } == true
          case "SET_VOLUME": confirmed = receivedVolume.map { abs($0 - min(1, max(0, value ?? 0))) < 0.02 } == true
          default: break
          }
          if confirmed { break }
        }
        guard confirmed else { throw CastRemoteError.notConfirmed }
        guard let playback = result["playerState"] as? String,
          ["PLAYING", "PAUSED", "BUFFERING", "LOADING", "IDLE"].contains(playback)
        else { throw CastRemoteError.invalidMessage }
        var next = state
        next.position = (result["currentTime"] as? Double) ?? state.position
        next.playback = playback
        next.timestamp = Date()
        if let receivedVolume, receivedVolume.isFinite { next.volume = min(1, max(0, receivedVolume)) }
        await close()
        CastControlDiagnostics.record(command, "confermato · " + next.playback)
        return next
      } catch {
        await close()
        CastControlDiagnostics.record(command, phase + " · " + CastControlDiagnostics.failure(error))
        throw error
      }
    }

    private func mediaStatus(_ reply: [String: Any], expectedID: Int?) throws -> [String: Any] {
      guard let rows = reply["status"] as? [[String: Any]],
        let status = rows.first(where: { expectedID == nil || $0["mediaSessionId"] as? Int == expectedID })
      else { throw CastRemoteError.changedSession }
      return status
    }

    private func connect() async throws -> Data {
      guard CastWire.localAddress(host), port > 0 else { throw CastRemoteError.invalidDevice }
      let certificate = try await connection.open(host: host, port: port, pin: pin)
      guard certificate.count == 32, pin == nil || pin == certificate else { throw CastRemoteError.invalidDevice }
      return certificate
    }

    private func deadline() -> Task<Void, Never> {
      let connection = self.connection
      return Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { await connection.close() } }
    }

    private func application(_ session: String) async throws -> String {
      _ = try await send(CastWire.connection, to: "receiver-0", payload: ["type": "CONNECT"])
      let reply = try await exchange(CastWire.receiver, to: "receiver-0", payload: ["type": "GET_STATUS"])
      guard let status = reply["status"] as? [String: Any], let apps = status["applications"] as? [[String: Any]],
        let app = apps.first(where: { $0["appId"] as? String == "CC1AD845" && $0["sessionId"] as? String == session }),
        let transport = app["transportId"] as? String else { throw CastRemoteError.changedSession }
      return transport
    }

    private func send(_ namespace: String, to destination: String, payload: [String: Any]) async throws -> Int {
      request += 1; var payload = payload; payload["requestId"] = request
      let frame = try CastWire.frame(source: sender, destination: destination, namespace: namespace, json: JSONSerialization.data(withJSONObject: payload))
      try await connection.write(frame)
      return request
    }

    private func exchange(_ namespace: String, to destination: String, payload: [String: Any]) async throws -> [String: Any] {
      let timeout = deadline(); defer { timeout.cancel() }
      let id = try await send(namespace, to: destination, payload: payload)
      for _ in 0..<40 {
        let prefix = try await connection.read(4)
        let length = prefix.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= CastWire.limit else { throw CastRemoteError.invalidMessage }
        let message = try CastWire.decode(await connection.read(length))
        guard let json = try JSONSerialization.jsonObject(with: message.json) as? [String: Any] else { continue }
        if message.namespace == CastWire.heartbeat, json["type"] as? String == "PING" {
          _ = try await send(CastWire.heartbeat, to: "receiver-0", payload: ["type": "PONG"])
        }
        if message.namespace == namespace, json["requestId"] as? Int == id {
          if ["INVALID_REQUEST", "INVALID_PLAYER_STATE", "LOAD_FAILED"].contains(json["type"] as? String ?? "") { throw CastRemoteError.rejected }
          return json
        }
      }
      throw CastRemoteError.invalidMessage
    }

  }

  private actor CastTLSConnection: CastByteConnection {
    private var socket: NWConnection?
    private let certificate = CertificateBox()
    func close() { socket?.cancel(); socket = nil }
    func open(host: String, port: UInt16, pin: Data?) async throws -> Data {
      let tls = NWProtocolTLS.Options(); let box = certificate
      sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
        let trust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
        let hash = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
        box.value = hash
        complete(pin.map { $0 == hash } ?? true)
      }, .global(qos: .userInitiated))
      let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: tls))
      socket = connection
      let states = AsyncThrowingStream<Void, Error> { continuation in
        connection.stateUpdateHandler = { state in
          switch state {
          case .ready: continuation.yield(()); continuation.finish()
          case .failed(let error): continuation.finish(throwing: error)
          case .cancelled: continuation.finish(throwing: CastRemoteError.disconnected)
          default: break
          }
        }
      }
      let timeout = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { connection.cancel() } }
      defer { timeout.cancel() }
      connection.start(queue: .global(qos: .userInitiated))
      for try await _ in states {
        guard let value = certificate.value else { throw CastRemoteError.invalidDevice }
        return value
      }
      throw CastRemoteError.disconnected
    }
    func write(_ data: Data) async throws {
      guard let socket else { throw CastRemoteError.disconnected }
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        socket.send(content: data, completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
      }
    }
    func read(_ count: Int) async throws -> Data {
      guard let socket else { throw CastRemoteError.disconnected }
      var result = Data()
      while result.count < count {
        let remaining = count - result.count
        let data: Data = try await withCheckedThrowingContinuation { continuation in
          socket.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, error in
            if let error { continuation.resume(throwing: error) }
            else if let data, !data.isEmpty { continuation.resume(returning: data) }
            else { continuation.resume(throwing: CastRemoteError.disconnected) }
          }
        }
        result.append(data)
      }
      return result
    }
  }

  private final class CertificateBox: @unchecked Sendable {
    private let lock = NSLock(); private var data: Data?
    var value: Data? { get { lock.withLock { data } } set { lock.withLock { data = newValue } } }
  }
#endif

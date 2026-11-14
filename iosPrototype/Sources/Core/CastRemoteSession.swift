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
}

#if os(iOS)
  import NowPlaying
  @available(iOS 27, *)
  extension CastRemoteState: RemoteMediaSessionAttributes {}
#endif

public enum CastRemoteError: Error { case invalidDevice, invalidMessage, disconnected, timeout, changedSession }

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

  /// One connection to the receiver chosen by the user. The app captures its
  /// certificate while the Cast SDK session is connected. The extension must
  /// match that exact pin; it never accepts arbitrary replacement certificates.
  public actor CastDeviceChannel {
    private let host: String
    private let port: UInt16
    private let pin: Data?
    private let certificate = CertificateBox()
    private var socket: NWConnection?
    private let sender = "notenarrate-" + UUID().uuidString
    private var request = 0
    public init(host: String, port: UInt16, pin: Data?) {
      self.host = host; self.port = port; self.pin = pin
    }
    public func close() { socket?.cancel(); socket = nil }

    public func captureCertificate(receiverSession: String) async throws -> Data {
      defer { close() }
      try await connect()
      _ = try await application(receiverSession)
      guard let value = certificate.value else { throw CastRemoteError.invalidDevice }
      return value
    }

    public func perform(_ command: String, value: Double? = nil, state: CastRemoteState) async throws -> CastRemoteState {
      guard pin?.count == 32 else { throw CastRemoteError.invalidDevice }
      defer { close() }
      try await connect()
      let destination = try await application(state.receiverSession)
      _ = try await send(CastWire.connection, to: destination, payload: ["type": "CONNECT"])
      let current = try await exchange(CastWire.media, to: destination, payload: ["type": "GET_STATUS"])
      guard let status = (current["status"] as? [[String: Any]])?.first,
        let mediaID = status["mediaSessionId"] as? Int,
        let media = status["media"] as? [String: Any],
        let metadata = media["metadata"] as? [String: Any],
        metadata["notenarrateTrackID"] as? String == state.trackID
      else { throw CastRemoteError.changedSession }
      var payload: [String: Any] = ["type": command, "mediaSessionId": mediaID]
      let reply: [String: Any]
      var receivedVolume: Double?
      if command == "SET_VOLUME" {
        guard let value, value.isFinite else { throw CastRemoteError.invalidMessage }
        let receiverReply = try await exchange(CastWire.receiver, to: "receiver-0", payload: ["type": "SET_VOLUME", "volume": ["level": min(1, max(0, value)), "muted": false]])
        receivedVolume = ((receiverReply["status"] as? [String: Any])?["volume"] as? [String: Any])?["level"] as? Double
        reply = try await exchange(CastWire.media, to: destination, payload: ["type": "GET_STATUS"])
      } else {
        guard ["PLAY", "PAUSE", "SEEK"].contains(command) else { throw CastRemoteError.invalidMessage }
        if command == "SEEK" {
          guard let value, value.isFinite else { throw CastRemoteError.invalidMessage }
          payload["currentTime"] = min(state.duration, max(0, value))
        }
        reply = try await exchange(CastWire.media, to: destination, payload: payload)
      }
      guard let result = (reply["status"] as? [[String: Any]])?.first else { throw CastRemoteError.invalidMessage }
      var next = state
      next.position = (result["currentTime"] as? Double) ?? state.position
      next.playback = (result["playerState"] as? String) ?? state.playback
      next.timestamp = Date()
      if let receivedVolume, receivedVolume.isFinite { next.volume = min(1, max(0, receivedVolume)) }
      return next
    }

    private func connect() async throws {
      guard CastWire.localAddress(host), port > 0 else { throw CastRemoteError.invalidDevice }
      let tls = NWProtocolTLS.Options(); let expected = pin; let box = certificate
      sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
        let trust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
        let hash = Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
        box.value = hash
        complete(expected.map { $0 == hash } ?? true)
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
      let timeout = deadline(connection); defer { timeout.cancel() }
      connection.start(queue: .global(qos: .userInitiated))
      for try await _ in states { return }
      throw CastRemoteError.disconnected
    }

    private func deadline(_ connection: NWConnection) -> Task<Void, Never> {
      Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { connection.cancel() } }
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
      guard let socket else { throw CastRemoteError.disconnected }
      request += 1; var payload = payload; payload["requestId"] = request
      let frame = try CastWire.frame(source: sender, destination: destination, namespace: namespace, json: JSONSerialization.data(withJSONObject: payload))
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        socket.send(content: frame, completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
      }
      return request
    }

    private func exchange(_ namespace: String, to destination: String, payload: [String: Any]) async throws -> [String: Any] {
      guard let socket else { throw CastRemoteError.disconnected }
      let timeout = deadline(socket); defer { timeout.cancel() }
      let id = try await send(namespace, to: destination, payload: payload)
      for _ in 0..<40 {
        let prefix = try await read(4)
        let length = prefix.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= CastWire.limit else { throw CastRemoteError.invalidMessage }
        let message = try CastWire.decode(await read(length))
        guard let json = try JSONSerialization.jsonObject(with: message.json) as? [String: Any] else { continue }
        if message.namespace == CastWire.heartbeat, json["type"] as? String == "PING" {
          _ = try await send(CastWire.heartbeat, to: "receiver-0", payload: ["type": "PONG"])
        }
        if message.namespace == namespace, json["requestId"] as? Int == id { return json }
      }
      throw CastRemoteError.invalidMessage
    }

    private func read(_ count: Int) async throws -> Data {
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

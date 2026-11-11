import CryptoKit
import Foundation

/// Ephemeral invitation. Never persisted, advertised in Bonjour, logged or sent over the connection.
public struct PassengerInvitation: Equatable, Sendable {
  public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
  public let sessionID: UUID
  public let code: String
  public init() {
    sessionID = UUID()
    code = String((0..<24).map { _ in Self.alphabet.randomElement()! })
  }
  public init(sessionID: UUID, code: String) throws {
    let value = code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    guard value.count == 24, value.allSatisfy({ Self.alphabet.contains($0) }) else {
      throw PassengerError.invalidInvitation
    }
    self.sessionID = sessionID
    self.code = value
  }
  public var serviceName: String { "NN-" + sessionID.uuidString }
  /// Bonjour can append a collision suffix when an advertisement is reopened.
  public static func advertisedSession(_ name: String) -> (id: UUID, suffix: Int)? {
    guard name.hasPrefix("NN-"), name.utf8.count <= 63 else { return nil }
    let remainder = String(name.dropFirst(3))
    guard let id = UUID(uuidString: String(remainder.prefix(36))) else { return nil }
    let suffix = String(remainder.dropFirst(36))
    if suffix.isEmpty { return (id, 0) }
    guard suffix.range(of: #"^ \([0-9]{1,6}\)$"#, options: .regularExpression) != nil,
      let number = Int(suffix.dropFirst(2).dropLast())
    else { return nil }
    return (id, number)
  }
  public var displayCode: String {
    stride(from: 0, to: 24, by: 4).map { offset in
      String(Array(code)[offset..<offset + 4])
    }.joined(separator: " ")
  }
  public var text: String {
    "notenarrate://passenger/" + sessionID.uuidString + "#" + code
  }
  public init(text: String) throws {
    guard text.utf8.count < 256,
      let url = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "notenarrate", url.host == "passenger", url.query == nil,
      url.user == nil, url.password == nil, url.port == nil,
      let id = UUID(uuidString: String(url.path.dropFirst())), let code = url.fragment
    else { throw PassengerError.invalidInvitation }
    try self.init(sessionID: id, code: code)
  }
  public var key: Data {
    Data(SHA256.hash(data: Data(("NoteNarrate.Passenger.v1:" + code).utf8)))
  }
}

public enum PassengerError: Error, LocalizedError {
  case invalidInvitation, malformed, disconnected, notApproved, busy, expired, tooManyTracks
  public var errorDescription: String? {
    switch self {
    case .invalidInvitation:
      "Codice non valido. Scansiona il QR o ricopia il codice della sessione."
    case .malformed: "Richiesta non valida. Aggiorna NoteNarrate su entrambi i telefoni."
    case .disconnected:
      "Collegamento interrotto. Riapri la sessione sul telefono principale e riconnettiti."
    case .notApproved: "Invito non valido per questa sessione. Scansiona il QR attuale."
    case .busy: "Attendi la conferma della richiesta precedente."
    case .expired: "Richiesta scaduta: ripeti la selezione."
    case .tooManyTracks:
      "Puoi inviare da 1 a 500 brani alla volta. Seleziona una raccolta più piccola."
    }
  }
}

/// Only catalog identifiers, display metadata and public cover URLs cross phones.
/// No playback URLs, cookies, lyrics or keys.
public struct PassengerTrack: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let artist: String
  public let artwork: URL?
  public init(id: String, title: String, artist: String, artwork: URL? = nil) {
    self.id = id
    self.title = String(title.prefix(160))
    self.artist = String(artist.prefix(160))
    self.artwork = Self.publicArtwork(artwork)
  }
  public var valid: Bool {
    id.utf8.count == 11
      && id.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      } && !title.isEmpty && title.count <= 160 && artist.count <= 160
      && (artwork == nil || Self.publicArtwork(artwork) != nil)
  }

  private static func publicArtwork(_ url: URL?) -> URL? {
    guard let url, url.absoluteString.utf8.count <= 512,
      url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
      url.user == nil, url.password == nil, url.fragment == nil,
      url.port == nil || url.port == 443,
      ["googleusercontent.com", "ggpht.com", "ytimg.com", "mzstatic.com", "scdn.co"].contains(
        where: {
          host == $0 || host.hasSuffix("." + $0)
        }), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    let credentials: Set<String> = [
      "token", "access_token", "key", "api_key", "authorization", "cookie", "session", "sid",
      "sapisid",
    ]
    guard !(parts.queryItems ?? []).contains(where: { credentials.contains($0.name.lowercased()) })
    else { return nil }
    return url
  }
}

public struct PassengerSelection: Codable, Equatable, Sendable {
  public typealias Action = PlaybackSelectionAction
  public var id = UUID()
  public var created = Date()
  public let sessionID: UUID
  public let action: Action
  public let tracks: [PassengerTrack]
  public init(sessionID: UUID, action: Action, tracks: [PassengerTrack]) {
    self.sessionID = sessionID
    self.action = action
    self.tracks = tracks
  }
  public func validate(sessionID: UUID, now: Date = Date()) throws {
    guard self.sessionID == sessionID else { throw PassengerError.notApproved }
    guard abs(created.timeIntervalSince(now)) <= 90 else { throw PassengerError.expired }
    guard (1...500).contains(tracks.count) else { throw PassengerError.tooManyTracks }
    guard tracks.allSatisfy(\.valid) else { throw PassengerError.malformed }
  }
}

public struct PassengerPlayback: Codable, Equatable, Sendable {
  public var title: String
  public var artist: String
  public var playing: Bool
  public var queueCount: Int
  public init(title: String = "", artist: String = "", playing: Bool = false, queueCount: Int = 0) {
    self.title = String(title.prefix(160))
    self.artist = String(artist.prefix(160))
    self.playing = playing
    self.queueCount = max(0, queueCount)
  }
}

public struct PassengerReceipt: Codable, Equatable, Sendable {
  public let requestID: UUID
  public let success: Bool
  public let message: String
  public init(requestID: UUID, success: Bool, message: String) {
    self.requestID = requestID
    self.success = success
    self.message = String(message.prefix(240))
  }
}

/// TCP has no message boundaries. A checked length prefix bounds memory before JSON decoding.
public struct PassengerFrameBuffer: Sendable {
  public static let maximum = 1_048_576
  private var bytes = Data()
  public init() {}
  public mutating func append(_ data: Data) throws -> [Data] {
    guard bytes.count + data.count <= Self.maximum + 4 + 65_536 else {
      throw PassengerError.malformed
    }
    bytes.append(data)
    var frames: [Data] = []
    while bytes.count >= 4 {
      let length = bytes.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
      guard length > 0, length <= Self.maximum else { throw PassengerError.malformed }
      guard bytes.count >= length + 4 else { break }
      frames.append(Data(bytes.dropFirst(4).prefix(length)))
      bytes = Data(bytes.dropFirst(length + 4))
    }
    return frames
  }
  public static func encode(_ data: Data) throws -> Data {
    guard !data.isEmpty, data.count <= maximum else { throw PassengerError.malformed }
    let length = UInt32(data.count).bigEndian
    return withUnsafeBytes(of: length) { Data($0) } + data
  }
}

enum PassengerBody: Codable, Sendable {
  case hello(String)
  case approved
  case state(PassengerPlayback)
  case selection(PassengerSelection)
  case receipt(PassengerReceipt)
  case goodbye
}
struct PassengerMessage: Codable, Sendable {
  var version = 1
  let body: PassengerBody
  init(_ body: PassengerBody) { self.body = body }
  func encoded() throws -> Data {
    try PassengerFrameBuffer.encode(JSONEncoder().encode(self))
  }
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= PassengerFrameBuffer.maximum else { throw PassengerError.malformed }
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version == 1 else { throw PassengerError.malformed }
    return value
  }
}

/// Cache replies before sending acknowledgements so duplicate deliveries never add/play twice.
public struct PassengerRequestLedger: Sendable {
  private var replies: [UUID: PassengerReceipt] = [:]
  private var dates: [UUID: Date] = [:]
  public init() {}
  public func reply(for id: UUID) -> PassengerReceipt? { replies[id] }
  public mutating func hasCapacity(now: Date = Date()) -> Bool {
    // A request can be at most 90 seconds old or 90 seconds in the future.
    // Never evict an actionable ID just because other peers send more requests.
    for (id, date) in dates where now.timeIntervalSince(date) > 181 {
      replies.removeValue(forKey: id)
      dates.removeValue(forKey: id)
    }
    return replies.count < 2048
  }
  public mutating func remember(_ reply: PassengerReceipt, now: Date = Date()) {
    guard replies[reply.requestID] == nil, hasCapacity(now: now) else { return }
    replies[reply.requestID] = reply
    dates[reply.requestID] = now
  }
}

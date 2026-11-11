import Foundation
import Network

#if canImport(Darwin)
  import Darwin
#endif

/// Ephemeral, token-protected LAN endpoint. Signed CDN addresses never leave the phone.
@MainActor
final class CastAudioRelay {
  private var listener: NWListener?
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var connections: [UUID: NWConnection] = [:]
  private var ready: CheckedContinuation<URL, Error>?
  private var buffer: AudioRangeBuffer?
  private var file: URL?
  private var length: Int64 = 0
  private var path = ""

  func start(source: YouTubeAudio.Source?, file: URL?) async throws -> URL {
    stop()
    if let source, !source.isHLS, let count = source.byteCount, count > 0 {
      buffer = AudioRangeBuffer(source: source, diagnostic: nil)
      length = count
    } else if let file {
      self.file = file
      length = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
    } else {
      throw AudioPlaybackError.unavailable
    }
    guard length > 0, let ip = Self.wifiAddress() else { throw AudioPlaybackError.unavailable }
    path = "/" + UUID().uuidString + "/audio.m4a"
    let listener = try NWListener(using: .tcp, on: .any)
    self.listener = listener
    listener.newConnectionHandler = { [weak self] connection in
      Task { @MainActor in self?.accept(connection) }
    }
    return try await withCheckedThrowingContinuation { continuation in
      ready = continuation
      listener.stateUpdateHandler = { [weak self, weak listener] state in
        Task { @MainActor in
          guard let self, self.listener === listener, let ready = self.ready else { return }
          switch state {
          case .ready:
            guard let port = listener?.port else { return }
            self.ready = nil
            ready.resume(returning: URL(string: "http://\(ip):\(port.rawValue)\(self.path)")!)
          case .failed(let error):
            self.ready = nil
            ready.resume(throwing: error)
          default: break
          }
        }
      }
      listener.start(queue: .global(qos: .userInitiated))
    }
  }
  func stop() {
    listener?.cancel()
    listener = nil
    ready?.resume(throwing: CancellationError())
    ready = nil
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
    for connection in connections.values { connection.cancel() }
    connections.removeAll()
    if let buffer { Task { await buffer.close() } }
    buffer = nil
    file = nil
    path = ""
  }
  private func accept(_ connection: NWConnection) {
    guard connections.count < 4 else {
      connection.cancel()
      return
    }
    let id = UUID()
    connections[id] = connection
    connection.start(queue: .global(qos: .userInitiated))
    tasks[id] = Task { [weak self] in
      guard let self else { return }
      defer {
        connection.cancel()
        self.connections[id] = nil
        self.tasks[id] = nil
      }
      do {
        let deadline = Task {
          try? await Task.sleep(for: .seconds(10))
          if !Task.isCancelled { connection.cancel() }
        }
        defer { deadline.cancel() }
        var header = Data()
        while header.range(of: Data("\r\n\r\n".utf8)) == nil {
          let data: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
              data, _, complete, error in
              if let error {
                continuation.resume(throwing: error)
              } else if let data, !data.isEmpty {
                continuation.resume(returning: data)
              } else {
                continuation.resume(throwing: CancellationError())
              }
            }
          }
          header.append(data)
          guard header.count <= 16384 else { return }
        }
        deadline.cancel()
        guard let text = String(data: header, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[1] == self.path, first[0] == "GET" || first[0] == "HEAD"
        else {
          try await send(
            Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
            to: connection)
          return
        }
        let range = lines.first { $0.lowercased().hasPrefix("range:") }?.split(
          separator: ":", maxSplits: 1
        ).last?.trimmingCharacters(in: .whitespaces)
        let bounds: Range<Int64>
        do { bounds = try Self.bounds(range, length: self.length) } catch {
          try await send(
            Data(
              "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(self.length)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                .utf8), to: connection)
          return
        }
        let status = range == nil ? "200 OK" : "206 Partial Content"
        let contentRange =
          range == nil
          ? ""
          : "Content-Range: bytes \(bounds.lowerBound)-\(bounds.upperBound - 1)/\(self.length)\r\n"
        try await send(
          Data(
            "HTTP/1.1 \(status)\r\nContent-Type: audio/mp4\r\nAccept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nContent-Length: \(bounds.count)\r\n\(contentRange)Connection: close\r\n\r\n"
              .utf8), to: connection)
        if first[0] == "HEAD" { return }
        var offset = bounds.lowerBound
        while offset < bounds.upperBound {
          try Task.checkCancellation()
          let blockStart = offset / AudioRangeBuffer.blockSize * AudioRangeBuffer.blockSize
          let data: Data
          if let buffer = self.buffer {
            data = try await buffer.block(at: blockStart)
          } else if let file = self.file {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(blockStart))
            data = try handle.read(upToCount: Int(AudioRangeBuffer.blockSize)) ?? Data()
          } else {
            return
          }
          let start = Int(offset - blockStart)
          let count = min(data.count - start, Int(bounds.upperBound - offset))
          guard count > 0 else { return }
          try await send(data.subdata(in: start..<(start + count)), to: connection)
          offset += Int64(count)
        }
      } catch { /* Closing the connection aborts incomplete responses; never log signed URLs. */  }
    }
  }
  private func send(_ data: Data, to connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
    }
  }
  static func bounds(_ header: String?, length: Int64) throws -> Range<Int64> {
    guard length > 0 else { throw AudioPlaybackError.unavailable }
    guard let header else { return 0..<length }
    guard header.hasPrefix("bytes="), !header.contains(",") else {
      throw AudioPlaybackError.unavailable
    }
    let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2 else { throw AudioPlaybackError.unavailable }
    if parts[0].isEmpty, let suffix = Int64(parts[1]), suffix > 0 {
      return max(0, length - suffix)..<length
    }
    guard let first = Int64(parts[0]), first >= 0, first < length else {
      throw AudioPlaybackError.unavailable
    }
    let last = parts[1].isEmpty ? length - 1 : (Int64(parts[1]) ?? -1)
    guard last >= first else { throw AudioPlaybackError.unavailable }
    return first..<(min(last, length - 1) + 1)
  }
  private static func wifiAddress() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return nil }
    defer { freeifaddrs(list) }
    var entry = list
    while let current = entry {
      defer { entry = current.pointee.ifa_next }
      guard String(cString: current.pointee.ifa_name) == "en0",
        let address = current.pointee.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET)
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
        NI_NUMERICHOST) == 0
      {
        return String(cString: host)
      }
    }
    return nil
  }
}

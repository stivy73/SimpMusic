import AVFoundation
import Foundation

/// AVPlayer sometimes requests the whole signed file, which YouTube rejects with 403.
/// Serve its byte requests with the same bounded ranges accepted by the CDN probe.
/// No local HTTP server, full-song download, signed URL logging or persistent cache.
public final class AudioRangeLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
  private let source: YouTubeAudio.Source
  private let queue = DispatchQueue(label: "NoteNarrate.AudioRanges")
  private let diagnostic: (@Sendable (String) -> Void)?
  private let buffer: AudioRangeBuffer
  private let assetURL = URL(string: "notenarrate-audio://stream/\(UUID().uuidString)/audio.m4a")!
  // Accessed exclusively on queue, including cancellation and completion.
  private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
  public init(source: YouTubeAudio.Source, diagnostic: (@Sendable (String) -> Void)? = nil) {
    self.source = source
    self.diagnostic = diagnostic
    buffer = AudioRangeBuffer(source: source, diagnostic: diagnostic)
  }
  deinit {
    let buffer = buffer
    Task { await buffer.close() }
  }

  /// Fill a small head start before AVPlayer starts consuming the custom asset.
  public func prepare() async throws {
    guard !source.isHLS else { return }
    _ = try await buffer.block(at: 0)
    await buffer.prefetch(after: 0)
  }

  static func rangeRequest(source: YouTubeAudio.Source, offset: Int64, last: Int64) throws
    -> URLRequest
  {
    guard offset >= 0, last >= offset,
      var url = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
    else { throw AudioPlaybackError.unavailable }
    // The signature covers opaque query values. queryItems would decode/re-encode
    // their escapes (for example %2B -> + or %2f -> /), invalidating some CDN URLs.
    // Strip only the old range fields and preserve every other byte and its order.
    if let query = url.percentEncodedQuery {
      let fields = query.split(separator: "&", omittingEmptySubsequences: false).filter {
        $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first?
          .removingPercentEncoding != "range"
      }
      url.percentEncodedQuery = fields.isEmpty ? nil : fields.joined(separator: "&")
    }
    guard let target = url.url else { throw AudioPlaybackError.unavailable }
    var request = URLRequest(url: target, timeoutInterval: 20)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
    return request
  }

  public func asset() -> AVURLAsset {
    if source.isHLS {
      return AVURLAsset(url: source.url, options: [AVURLAssetHTTPUserAgentKey: source.userAgent])
    }
    // The original signed address stays private to this loader.
    // A shared URL lets AVFoundation reuse another song's duration/sample index.
    let asset = AVURLAsset(url: assetURL)
    asset.resourceLoader.setDelegate(self, queue: queue)
    return asset
  }

  public func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let length = source.byteCount, length > 0 else {
      loadingRequest.finishLoading(with: AudioPlaybackError.unavailable)
      return false
    }
    if let info = loadingRequest.contentInformationRequest {
      info.contentType = AVFileType.m4a.rawValue
      info.contentLength = length
      info.isByteRangeAccessSupported = true
    }
    guard let data = loadingRequest.dataRequest else {
      loadingRequest.finishLoading()
      return true
    }
    let offset = max(data.requestedOffset, data.currentOffset)
    let end =
      data.requestsAllDataToEndOfResource
      ? length
      : min(length, data.requestedOffset + Int64(data.requestedLength))
    diagnostic?("AVF bytes \(offset)..<\(end)")
    let box = LoadingBox(loadingRequest)
    let id = ObjectIdentifier(loadingRequest)
    requests[id] = Task { [weak self] in
      guard let self else { return }
      do {
        var current = offset
        while current < end {
          try Task.checkCancellation()
          let blockOffset = current / AudioRangeBuffer.blockSize * AudioRangeBuffer.blockSize
          let bytes = try await buffer.block(at: blockOffset)
          try Task.checkCancellation()
          let start = Int(current - blockOffset)
          let count = min(bytes.count - start, Int(end - current))
          guard count > 0 else { throw AudioPlaybackError.unavailable }
          let chunk = bytes.subdata(in: start..<(start + count))
          current += Int64(count)
          await buffer.prefetch(after: blockOffset)
          await withCheckedContinuation { continuation in
            queue.async {
              if !box.request.isCancelled { box.request.dataRequest?.respond(with: chunk) }
              continuation.resume()
            }
          }
        }
        queue.async { [weak self] in
          self?.requests[id] = nil
          if !box.request.isCancelled { box.request.finishLoading() }
        }
      } catch {
        queue.async { [weak self] in
          self?.requests[id] = nil
          if !box.request.isCancelled {
            box.request.finishLoading(with: AudioPlaybackError.unavailable)
          }
        }
      }
    }
    return true
  }
  public func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    requests.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
  }
}

private final class LoadingBox: @unchecked Sendable {
  let request: AVAssetResourceLoadingRequest
  init(_ request: AVAssetResourceLoadingRequest) { self.request = request }
}

/// Per-track, bounded memory read-ahead. Shared range requests survive seeks without
/// refetching the same bytes; no signed addresses or song data are persisted.
actor AudioRangeBuffer {
  static let blockSize: Int64 = 512 * 1024
  private let source: YouTubeAudio.Source
  private let session: URLSession
  private let diagnostic: (@Sendable (String) -> Void)?
  private var cached: [Int64: Data] = [:]
  private var order: [Int64] = []
  private var pending: [Int64: Task<Data, Error>] = [:]
  private var closed = false

  init(
    source: YouTubeAudio.Source, session: URLSession? = nil,
    diagnostic: (@Sendable (String) -> Void)? = nil
  ) {
    self.source = source
    self.diagnostic = diagnostic
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.ephemeral
      config.httpShouldSetCookies = false
      config.httpMaximumConnectionsPerHost = 2
      self.session = URLSession(configuration: config)
    }
  }

  func block(at offset: Int64) async throws -> Data {
    try Task.checkCancellation()
    guard !closed, let length = source.byteCount, offset >= 0, offset < length,
      offset.isMultiple(of: Self.blockSize)
    else { throw AudioPlaybackError.unavailable }
    if let data = cached[offset] {
      touch(offset)
      return data
    }
    let task: Task<Data, Error>
    if let existing = pending[offset] {
      task = existing
    } else {
      let source = source
      let session = session
      let diagnostic = diagnostic
      let last = min(length, offset + Self.blockSize) - 1
      task = Task {
        try await Self.fetch(
          source: source, session: session, offset: offset, last: last, diagnostic: diagnostic)
      }
      pending[offset] = task
    }
    do {
      let data = try await task.value
      guard !closed else { throw CancellationError() }
      pending[offset] = nil
      cached[offset] = data
      touch(offset)
      while order.count > 8 { cached.removeValue(forKey: order.removeFirst()) }
      try Task.checkCancellation()
      return data
    } catch {
      pending[offset] = nil
      throw error
    }
  }

  private func touch(_ offset: Int64) {
    order.removeAll { $0 == offset }
    order.append(offset)
  }

  func prefetch(after offset: Int64) {
    let next = offset + Self.blockSize
    guard !closed, let length = source.byteCount, next < length,
      cached[next] == nil, pending[next] == nil
    else { return }
    // The normal reader shares this task. At most one block ahead is requested.
    Task { _ = try? await block(at: next) }
  }

  func close() {
    closed = true
    for task in pending.values { task.cancel() }
    pending.removeAll()
    cached.removeAll()
    order.removeAll()
    session.invalidateAndCancel()
  }

  private static func fetch(
    source: YouTubeAudio.Source, session: URLSession, offset: Int64, last: Int64,
    diagnostic: (@Sendable (String) -> Void)?
  ) async throws -> Data {
    for attempt in 0..<3 {
      try Task.checkCancellation()
      do {
        let request = try AudioRangeLoader.rangeRequest(source: source, offset: offset, last: last)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AudioPlaybackError.unavailable }
        diagnostic?(
          "CDN offset \(offset): HTTP \(http.statusCode), bytes \(data.count), range \(http.value(forHTTPHeaderField: "Content-Range") ?? "none")"
        )
        if [408, 429, 500, 502, 503, 504].contains(http.statusCode), attempt < 2 {
          let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0.5
          guard retry <= 3 else { throw AudioPlaybackError.unavailable }
          try await Task.sleep(for: .seconds(max(0.3, retry)))
          continue
        }
        guard http.statusCode == 206, data.count == last - offset + 1,
          http.value(forHTTPHeaderField: "Content-Range")
            == "bytes \(offset)-\(last)/\(source.byteCount!)"
        else { throw AudioPlaybackError.unavailable }
        return data
      } catch let error as URLError {
        diagnostic?("CDN network error \(error.code.rawValue)")
        try Task.checkCancellation()
        guard attempt < 2,
          [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
        else { throw AudioPlaybackError.unavailable }
        try await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
      }
    }
    throw AudioPlaybackError.unavailable
  }
}

import AVFoundation
import Foundation

/// AVPlayer sometimes requests the whole signed file, which YouTube rejects with 403.
/// Serve its byte requests with the same bounded ranges accepted by the CDN probe.
/// No local HTTP server, full-song download, signed URL logging or persistent cache.
public final class AudioRangeLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
  private let source: YouTubeAudio.Source
  private let queue = DispatchQueue(label: "NoteNarrate.AudioRanges")
  private let session: URLSession
  // Accessed exclusively on queue, including cancellation and completion.
  private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
  public init(source: YouTubeAudio.Source) {
    self.source = source
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    session = URLSession(configuration: config)
  }
  deinit { session.invalidateAndCancel() }

  static func rangeRequest(source: YouTubeAudio.Source, offset: Int64, last: Int64) throws
    -> URLRequest
  {
    guard offset >= 0, last >= offset,
      var url = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
    else { throw AudioPlaybackError.unavailable }
    var query = url.queryItems ?? []
    query.removeAll { $0.name == "range" }
    query.append(URLQueryItem(name: "range", value: "\(offset)-\(last)"))
    url.queryItems = query
    guard let target = url.url else { throw AudioPlaybackError.unavailable }
    var request = URLRequest(url: target, timeoutInterval: 20)
    request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
    return request
  }

  public func asset() -> AVURLAsset {
    if source.isHLS {
      return AVURLAsset(url: source.url, options: [AVURLAssetHTTPUserAgentKey: source.userAgent])
    }
    // The original signed address stays private to this loader.
    let asset = AVURLAsset(url: URL(string: "notenarrate-audio://stream/audio.m4a")!)
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
    let box = LoadingBox(loadingRequest)
    let id = ObjectIdentifier(loadingRequest)
    requests[id] = Task { [weak self] in
      guard let self else { return }
      do {
        var current = offset
        while current < end {
          try Task.checkCancellation()
          let last = min(end, current + 512 * 1024) - 1
          let request = try Self.rangeRequest(source: source, offset: current, last: last)
          let (chunk, response) = try await session.data(for: request)
          try Task.checkCancellation()
          guard let http = response as? HTTPURLResponse, http.statusCode == 206,
            !chunk.isEmpty, chunk.count <= last - current + 1,
            http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(current)-") == true
          else { throw AudioPlaybackError.unavailable }
          current += Int64(chunk.count)
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

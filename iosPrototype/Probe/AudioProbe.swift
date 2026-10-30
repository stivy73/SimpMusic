import AVFoundation
import Foundation
import PrototypeCore
import YouTubeSDK

func probeAudioIfRequested(_ args: [String]) async throws -> Bool {
  if args.first == "--audio-timing" || args.first == "--audio-startup" {
    let query = args.dropFirst().joined(separator: " ")
    let results = try await HomeDiscovery(session: nil).search(query: query, filter: .songs)
    guard let song = results.first else { throw AudioPlaybackError.unavailable }
    print("Catalog: \(song.title), duration \(song.durationSeconds ?? 0)s")
    let began = Date()
    let source = try await YouTubeAudio().resolve(videoID: song.mediaId)
    print("Source safety checks complete: \(String(format: "%.2f", Date().timeIntervalSince(began)))s")
    print("Source duration: \(source.duration)s; HLS: \(source.isHLS)")
    let loader = AudioRangeLoader(source: source)
    try await loader.prepare()
    print("Initial range ready: \(String(format: "%.2f", Date().timeIntervalSince(began)))s")
    let asset = loader.asset()
    print("Asset duration: \(try await asset.load(.duration).seconds)s")
    for track in try await asset.loadTracks(withMediaType: .audio) {
      let range = try await track.load(.timeRange)
      let segments = try await track.load(.segments)
      print("Audio range: \(range.start.seconds)..<\(range.end.seconds); segments: \(segments.count)")
      for segment in segments {
        print("Segment empty: \(segment.isEmpty), target: \(segment.timeMapping.target.start.seconds)..<\(segment.timeMapping.target.end.seconds)")
      }
    }
    if args.first == "--audio-startup" {
      let timing = try await AudioPlaybackTiming.resolve(asset, source: source.duration)
      let player = await MainActor.run {
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5
        if timing.duration > 0 { item.forwardPlaybackEndTime = CMTime(seconds: timing.duration, preferredTimescale: 600) }
        let player = AVPlayer(playerItem: item)
        player.volume = 0
        player.playImmediately(atRate: 1)
        return player
      }
      var started = false
      for _ in 0..<60 {
        try await Task.sleep(for: .milliseconds(500))
        let position = await MainActor.run { player.currentTime().seconds }
        if position > 0.2 {
          print("Playback started after \(String(format: "%.2f", Date().timeIntervalSince(began)))s")
          started = true
          break
        }
      }
      guard started else { throw AudioPlaybackError.unavailable }
      await MainActor.run { player.currentItem?.preferredForwardBufferDuration = 30 }
      let initial = await MainActor.run { player.currentTime().seconds }
      try await Task.sleep(for: .seconds(95))
      let progress = await MainActor.run { player.currentTime().seconds - initial }
      await MainActor.run { player.pause() }
      print("Playback advance across 95 seconds: \(String(format: "%.2f", progress))s")
      guard progress >= 90 else { throw AudioPlaybackError.unavailable }
    }
    return true
  }
  guard args.first == "--audio" || args.first == "--audio-long" || args.first == "--audio-ranges"
  else { return false }
  let long = args.first == "--audio-long"
  let id = args.count > 1 ? args[1] : "dQw4w9WgXcQ"
  let video = try await YouTubeClient().video(id: id)
  print("Player metadata: \(video.id), duration \(video.lengthInSeconds)s")
  let streams =
    video.streamingData?.adaptiveFormats.filter {
      $0.mimeType.hasPrefix("audio/mp4") && $0.url != nil
    } ?? []
  print("Native AAC candidates: \(streams.count), HLS: \(video.hlsURL != nil)")
  for stream in streams {
    guard let url = stream.url.flatMap(URL.init(string:)) else { continue }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
    request.setValue(ClientConfig.ios.userAgent, forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    print(
      "AAC itag \(stream.itag): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), \(data.count) bytes"
    )
    if let http = response as? HTTPURLResponse {
      print(
        "MIME: \(http.mimeType ?? "unknown"), range \(http.value(forHTTPHeaderField: "Content-Range") ?? "unknown")"
      )
    }
  }
  let source = try await YouTubeAudio().resolve(videoID: id)
  print("Validated native audio source (signed URL omitted), bytes \(source.byteCount ?? 0)")
  let queryNames =
    URLComponents(url: source.url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
  print("Media query has n: \(queryNames.contains("n")), has pot: \(queryNames.contains("pot"))")
  if long, !source.isHLS {
    var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)!
    var query = components.queryItems ?? []
    query.removeAll { $0.name == "range" }
    components.queryItems = query
    var request = URLRequest(url: components.url!, timeoutInterval: 20)
    request.setValue("bytes=0-524287", forHTTPHeaderField: "Range")
    request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
    let config = URLSessionConfiguration.ephemeral
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(for: request)
    let http = response as? HTTPURLResponse
    print(
      "Range check: HTTP \(http?.statusCode ?? 0), count \(data.count), range \(http?.value(forHTTPHeaderField: "Content-Range") ?? "none")"
    )
  }
  let diagnostic: @Sendable (String) -> Void = { line in
    if long {
      print(line)
      fflush(nil)
    }
  }
  if args.first == "--audio-ranges" {
    for mode in [
      "header", "query", "both", "query-relative", "full-scope", "whole-get", "whole-range",
    ] {
      var url = URLComponents(url: source.url, resolvingAgainstBaseURL: false)!
      var query = url.queryItems ?? []
      query.removeAll { $0.name == "range" }
      if !["header", "whole-get", "whole-range"].contains(mode) {
        query.append(
          URLQueryItem(
            name: "range",
            value: mode == "full-scope" ? "0-\((source.byteCount ?? 1) - 1)" : "1048576-1572863"))
      }
      url.queryItems = query
      var request = URLRequest(url: url.url!, timeoutInterval: 20)
      request.cachePolicy = .reloadIgnoringLocalCacheData
      request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
      if mode != "query" && mode != "whole-get" {
        request.setValue(
          mode == "whole-range"
            ? "bytes=0-\((source.byteCount ?? 1) - 1)"
            : mode == "query-relative" ? "bytes=0-524287" : "bytes=1048576-1572863",
          forHTTPHeaderField: "Range")
      }
      let session = URLSession(configuration: .ephemeral)
      let (bytes, response) = try await session.data(for: request)
      session.invalidateAndCancel()
      let http = response as? HTTPURLResponse
      print(
        "Range mode \(mode): HTTP \(http?.statusCode ?? 0), bytes \(bytes.count), Content-Range \(http?.value(forHTTPHeaderField: "Content-Range") ?? "none")"
      )
    }
    return true
  }
  let loader = AudioRangeLoader(source: source, diagnostic: diagnostic)
  try await loader.prepare()
  let player = await MainActor.run {
    let asset = loader.asset()
    let item = AVPlayerItem(asset: asset)
    item.preferredForwardBufferDuration = 30
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    player.volume = 0
    player.playImmediately(atRate: 1)
    return player
  }
  var advanced = false
  for _ in 0..<30 {
    try await Task.sleep(for: .milliseconds(500))
    let seconds = await MainActor.run { player.currentTime().seconds }
    if seconds.isFinite && seconds > 2 {
      print("Native AVPlayer decoded AAC: \(String(format: "%.1f", seconds)) seconds advanced")
      advanced = true
      break
    }
  }
  if advanced && long {
    var previous = await MainActor.run { player.currentTime().seconds }
    let start = previous
    var stalledSamples = 0
    for second in 1...95 {
      try await Task.sleep(for: .seconds(1))
      let current = await MainActor.run { player.currentTime().seconds }
      if current - previous < 0.5 { stalledSamples += 1 }
      previous = current
      if second.isMultiple(of: 30) {
        print(
          "Playback after \(second)s: media advanced \(String(format: "%.1f", current - start))s, stalled samples \(stalledSamples)"
        )
      }
    }
    guard previous - start >= 90, stalledSamples <= 2 else {
      await MainActor.run { player.pause() }
      throw AudioPlaybackError.unavailable
    }
    print(
      "Long playback passed: \(String(format: "%.1f", previous - start))s, stalled samples \(stalledSamples)"
    )
  }
  await MainActor.run { player.pause() }
  if !advanced {
    let error = await MainActor.run { player.currentItem?.error as NSError? }
    print("AVPlayer failure: \(error?.domain ?? "pending"), code \(error?.code ?? 0)")
    var underlying = error
    while let nested = underlying?.userInfo[NSUnderlyingErrorKey] as? NSError {
      print("Underlying: \(nested.domain), code \(nested.code)")
      underlying = nested
    }
    let events = await MainActor.run { player.currentItem?.errorLog()?.events ?? [] }
    for event in events {
      print("AVPlayer HTTP error: \(event.errorStatusCode), domain \(event.errorDomain)")
    }
  }
  guard advanced else { throw AudioPlaybackError.unavailable }
  return true
}

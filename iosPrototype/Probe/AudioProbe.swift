import AVFoundation
import Foundation
import PrototypeCore
import YouTubeSDK

func probeAudioIfRequested(_ args: [String]) async throws -> Bool {
  if args.first == "--audio-layout" {
    let query = args.dropFirst().joined(separator: " ")
    guard let song = try await HomeDiscovery(session: nil).search(query: query, filter: .songs).first
    else { throw AudioPlaybackError.unavailable }
    let source = try await YouTubeAudio().resolve(videoID: song.mediaId)
    print(source.resolutionReport)
    guard !source.isHLS, let length = source.byteCount else { return true }
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    var offset: Int64 = 0
    for _ in 0..<24 {
      guard offset + 16 <= length else { break }
      var request = URLRequest(url: source.url, timeoutInterval: 20)
      request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
      request.setValue("bytes=\(offset)-\(offset + 15)", forHTTPHeaderField: "Range")
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 206, data.count == 16 else {
        throw AudioPlaybackError.unavailable
      }
      func uint(_ range: Range<Int>) -> UInt64 {
        data[range].reduce(0) { ($0 << 8) | UInt64($1) }
      }
      var size = uint(0..<4)
      let kind = String(bytes: data[4..<8], encoding: .ascii) ?? "unknown"
      if size == 1 { size = uint(8..<16) }
      print("MP4 atom offset=\(offset), type=\(kind), bytes=\(size)")
      guard size >= 8, size <= UInt64(length - offset) else { break }
      offset += Int64(size)
    }
    return true
  }
  if args.first == "--apple-audio-full", args.count == 2 {
    let source = try await YouTubeAudio().resolve(videoID: args[1], quality: .normal)
    print(source.resolutionReport)
    print("Selected source: HLS=\(source.isHLS), bytes=\(source.byteCount ?? -1), seconds=\(source.duration)")
    guard source.resolutionReport.contains("Selected PUBLIC_APPLE"), !source.isHLS,
      let length = source.byteCount, length > 0
    else { throw AudioPlaybackError.unavailable }
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    var total: Int64 = 0
    var complete = Data()
    for offset in stride(from: Int64(0), to: length, by: 131072) {
      let last = min(length - 1, offset + 131071)
      var request = URLRequest(url: source.url, timeoutInterval: 20)
      request.setValue(source.userAgent, forHTTPHeaderField: "User-Agent")
      request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 206,
        http.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(last)/\(length)",
        data.count == last - offset + 1
      else { throw AudioPlaybackError.rejectedRange(offset: offset,
        status: (response as? HTTPURLResponse)?.statusCode) }
      total += Int64(data.count)
      complete.append(data)
    }
    print("PUBLIC_APPLE anonymous complete AAC: \(total)/\(length) bytes; exact ranges; duration \(source.duration)s")
    let loader = AudioRangeLoader(source: source, diagnostic: { print($0) })
    defer { withExtendedLifetime(loader) {} }
    try await loader.prepare()
    let duration = try await loader.asset().load(.duration).seconds
    print("Native AVFoundation raw duration: \(duration)s")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    try complete.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let fileDuration = try await AVURLAsset(url: file).load(.duration).seconds
    print("Native AVFoundation file duration: \(fileDuration)s")
    let preciseFile = AVURLAsset(url: file,
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    print("Native precise file duration: \(try await preciseFile.load(.duration).seconds)s")
    if let track = try await preciseFile.loadTracks(withMediaType: .audio).first {
      print("Native audio timescale: \(try await track.load(.naturalTimeScale))")
      for format in try await track.load(.formatDescriptions) {
        if let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
          print("Native audio sample rate: \(description.pointee.mSampleRate)")
        }
      }
      let reader = try AVAssetReader(asset: preciseFile)
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      reader.add(output)
      guard reader.startReading() else { throw AudioPlaybackError.unavailable }
      var lastEnd = 0.0
      var summed = 0.0
      while let sample = output.copyNextSampleBuffer() {
        let duration = CMSampleBufferGetDuration(sample).seconds
        let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        if duration.isFinite { summed += duration }
        if start.isFinite && duration.isFinite { lastEnd = max(lastEnd, start + duration) }
      }
      print("Native compressed audio timeline: last=\(lastEnd)s, summed=\(summed)s, completed=\(reader.status == .completed)")
    }
    if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffprobe") {
      let probe = Process()
      probe.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
      probe.arguments = ["-v", "error", "-show_entries", "format=duration:stream=sample_rate,duration,time_base", "-of", "json", file.path]
      let output = Pipe()
      probe.standardOutput = output
      probe.standardError = FileHandle.nullDevice
      try probe.run()
      let info = output.fileHandleForReading.readDataToEndOfFile()
      probe.waitUntilExit()
      if probe.terminationStatus == 0, let text = String(data: info, encoding: .utf8) {
        print("Independent container metadata: " + text)
      }
    }
    let timing = try await AudioPlaybackTiming.resolve(loader.asset(), source: source.duration)
    guard timing.duration.isFinite, timing.duration > 0,
      abs(timing.duration - source.duration) < 5 else {
      throw AudioPlaybackError.unavailable
    }
    print("Native AVFoundation timing: \(timing.diagnostic); no account credentials used")
    return true
  }
  if args.first == "--audio-access" {
    let query = args.dropFirst().joined(separator: " ")
    let results = try await HomeDiscovery(session: nil).search(query: query, filter: .songs)
    guard let song = results.first else { throw AudioPlaybackError.unavailable }
    print("Public access probe: \(song.title)")
    let cipher = YouTubePlayerCipher.shared
    let info = try await cipher.playerInfo()
    let video = try await cipher.decipher(
      video: YouTubeBrowse(session: nil).player(
        videoID: song.mediaId,
        signatureTimestamp: info.signatureTimestamp), player: info)
    guard let address = YouTubeAudio.candidates(video, quality: .normal).first else {
      throw AudioPlaybackError.unavailable
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var length: Int64?
    for mode in ["header", "query", "both", "full-scope"] {
      for index in 0..<3 {
        let offset: Int64 =
          index == 0 ? 0 : index == 1 ? 1_048_576 : max(0, (length ?? 1024) - 1024)
        let last = offset + 1023
        var clean = URLComponents(url: address, resolvingAgainstBaseURL: false)!
        clean.percentEncodedQuery = clean.percentEncodedQuery?.split(
          separator: "&",
          omittingEmptySubsequences: false
        ).filter {
          $0.split(separator: "=", maxSplits: 1).first?.removingPercentEncoding != "range"
        }.joined(separator: "&")
        var request = URLRequest(url: clean.url!, timeoutInterval: 15)
        request.setValue(ClientConfig.webRemix.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
        if mode != "header",
          var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        {
          let value = mode == "full-scope" ? "0-\((length ?? 10_000_000) - 1)" : "\(offset)-\(last)"
          url.percentEncodedQuery =
            (url.percentEncodedQuery.map { $0 + "&" } ?? "") + "range=" + value
          request.url = url.url
          if mode == "query" { request.setValue(nil, forHTTPHeaderField: "Range") }
        }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        let http = response as? HTTPURLResponse
        let range = http?.value(forHTTPHeaderField: "Content-Range") ?? "none"
        if mode == "header", index == 0,
          let total = range.split(separator: "/").last.flatMap({ Int64($0) })
        {
          length = total
        }
        var count = 0
        for try await _ in bytes {
          count += 1
          if count >= 1024 { break }
        }
        bytes.task.cancel()
        print(
          "\(mode) offset \(offset): HTTP \(http?.statusCode ?? 0), sample \(count), range \(range)"
        )
      }
    }
    return true
  }
  if args.first == "--audio-timing" || args.first == "--audio-startup"
    || args.first == "--audio-startup-id" || args.first == "--audio-startup-resume" {
    let resuming = args.first == "--audio-startup-resume"
    let resumeAt = resuming ? (args.dropFirst().first.flatMap(Double.init) ?? -1) : 0
    guard resumeAt.isFinite, resumeAt >= 0 else { throw AudioPlaybackError.unavailable }
    let query = args.dropFirst(resuming ? 2 : 1).joined(separator: " ")
    let videoID: String
    if args.first == "--audio-startup-id" {
      videoID = query
    } else {
      let results = try await HomeDiscovery(session: nil).search(query: query, filter: .songs)
      guard let song = results.first else { throw AudioPlaybackError.unavailable }
      print("Catalog: \(song.title), duration \(song.durationSeconds ?? 0)s")
      videoID = song.mediaId
    }
    let began = Date()
    let source = try await YouTubeAudio().resolve(
      videoID: videoID, preferHLSForLongTracks: args.first != "--audio-timing")
    print(source.resolutionReport)
    print("Source safety checks complete: \(String(format: "%.2f", Date().timeIntervalSince(began)))s")
    print("Source duration: \(source.duration)s; HLS: \(source.isHLS)")
    let loader = AudioRangeLoader(source: source, diagnostic: { print($0) })
    defer { withExtendedLifetime(loader) {} }
    try await loader.prepare()
    print("Initial range ready: \(String(format: "%.2f", Date().timeIntervalSince(began)))s")
    let asset = loader.asset()
    if args.first == "--audio-timing" {
      print("Asset duration: \(try await asset.load(.duration).seconds)s")
      for track in try await asset.loadTracks(withMediaType: .audio) {
        let range = try await track.load(.timeRange)
        let segments = try await track.load(.segments)
        print("Audio range: \(range.start.seconds)..<\(range.end.seconds); segments: \(segments.count)")
        for segment in segments {
          print("Segment empty: \(segment.isEmpty), target: \(segment.timeMapping.target.start.seconds)..<\(segment.timeMapping.target.end.seconds)")
        }
      }
    }
    if args.first != "--audio-timing" {
      let timing = try await AudioPlaybackTiming.prepare(asset, source: source.duration)
      print("Playback metadata ready: \(String(format: "%.2f", Date().timeIntervalSince(began)))s; \(timing.diagnostic)")
      let player = await MainActor.run {
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [])
        item.preferredForwardBufferDuration = 5
        if timing.duration > 0 { item.forwardPlaybackEndTime = CMTime(seconds: timing.duration, preferredTimescale: 600) }
        let player = AVPlayer(playerItem: item)
        if args.first == "--audio-startup-id" { player.isMuted = true }
        player.volume = 0
        if !resuming { player.playImmediately(atRate: 1) }
        return player
      }
      if resuming {
        for _ in 0..<600 {
          if await MainActor.run(body: { player.currentItem?.status == .readyToPlay }) { break }
          try await Task.sleep(for: .milliseconds(50))
        }
        let sought = await withCheckedContinuation { continuation in
          Task { @MainActor in
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600)) {
              continuation.resume(returning: $0)
            }
          }
        }
        guard sought else { throw AudioPlaybackError.unavailable }
        await MainActor.run { player.playImmediately(atRate: 1) }
      }
      var started = false
      for _ in 0..<60 {
        try await Task.sleep(for: .milliseconds(500))
        let position = await MainActor.run { player.currentTime().seconds }
        if position > resumeAt + 0.2 {
          print("Playback started after \(String(format: "%.2f", Date().timeIntervalSince(began)))s; position \(String(format: "%.2f", position))s")
          fflush(nil)
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

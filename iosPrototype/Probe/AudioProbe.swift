import AVFoundation
import Foundation
import PrototypeCore
import YouTubeSDK

func probeAudioIfRequested(_ args: [String]) async throws -> Bool {
  guard args.first == "--audio" else { return false }
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
  print("Validated native audio source (signed URL omitted)")
  let loader = AudioRangeLoader(source: source)
  let player = await MainActor.run {
    let asset = loader.asset()
    let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    player.volume = 0
    player.play()
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

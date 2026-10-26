import Foundation
import PrototypeCore
import YouTubeSDK

// Public, credential-free diagnostic. No signed URL, challenge, header or response
// body is logged. A synthetic challenge exercises today's real YouTube script.
func probeCipherIfRequested(_ args: [String]) async throws -> Bool {
  guard args.first == "--cipher-probe" else { return false }
  let videoID = args.count > 1 ? args[1] : "ZmzqqdVFw8g"
  let cipher = YouTubePlayerCipher()
  let info: YouTubePlayerCipher.PlayerInfo
  do {
    info = try await cipher.playerInfo()
    print("Cipher metadata: player \(info.id), timestamp \(info.signatureTimestamp)")
  } catch {
    print("Cipher metadata failed: \(cipherProbeFailure(error))")
    return true
  }
  let challenge = "KdrqFlzJXl9EcCwlmEy"
  let fixture: [String: Any] = [
    "videoDetails": [
      "videoId": "synthetic", "title": "Synthetic", "author": "Probe", "channelId": "probe",
      "viewCount": "0", "lengthSeconds": "120",
    ],
    "streamingData": [
      "adaptiveFormats": [
        [
          "itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 128000,
          "url": "https://x.googlevideo.com/videoplayback?n=\(challenge)",
        ]
      ]
    ],
  ]
  do {
    let video = try JSONDecoder().decode(
      YouTubeVideo.self, from: JSONSerialization.data(withJSONObject: fixture))
    let decoded = try await cipher.decipher(video: video, player: info)
    let url = decoded.streamingData?.adaptiveFormats.first?.url.flatMap(URL.init(string:))
    let n = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
      .queryItems?.first(where: { $0.name == "n" })?.value
    print("Cipher current-script WK synthetic transform: \(n != nil && n != challenge)")
  } catch {
    print("Cipher current-script WK failed: \(cipherProbeFailure(error))")
  }
  let video: YouTubeVideo
  do {
    video = try await YouTubeBrowse(session: nil).player(
      videoID: videoID, signatureTimestamp: info.signatureTimestamp)
    let streams = video.streamingData?.adaptiveFormats ?? []
    let audio = streams.filter { $0.mimeType.hasPrefix("audio/mp4") }
    print(
      "Public WEB_REMIX: formats \(streams.count), AAC \(audio.count), direct \(audio.filter { $0.url != nil }.count), cipher \(audio.filter { $0.signatureCipher != nil }.count), HLS \(video.hlsURL != nil)"
    )
  } catch {
    print("Public WEB_REMIX failed: \(cipherProbeFailure(error))")
    return true
  }
  do {
    let decoded = try await cipher.decipher(video: video, player: info)
    let candidates =
      decoded.streamingData?.adaptiveFormats.filter {
        $0.mimeType.hasPrefix("audio/mp4") && $0.url != nil
      } ?? []
    print("Public WEB_REMIX decoded AAC candidates: \(candidates.count)")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    let transport = URLSession(configuration: configuration)
    defer { transport.invalidateAndCancel() }
    for candidate in candidates {
      guard let url = candidate.url.flatMap(URL.init(string:)) else { continue }
      for offset: Int64 in [
        0, 1_048_576, max(0, (Int64(candidate.contentLength ?? "") ?? 1024) - 1024),
      ] {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("bytes=\(offset)-\(offset + 1023)", forHTTPHeaderField: "Range")
        request.setValue(ClientConfig.webRemix.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        print(
          "Public decoded AAC itag \(candidate.itag), offset \(offset): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0), bytes \(data.count)"
        )
      }
      if args.contains("--blocks"), let length = candidate.contentLength.flatMap(Int64.init) {
        var total: Int64 = 0
        for offset in stride(from: Int64(0), to: length, by: 524288) {
          let last = min(length - 1, offset + 524287)
          var request = URLRequest(url: url, timeoutInterval: 15)
          request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
          request.setValue(ClientConfig.webRemix.userAgent, forHTTPHeaderField: "User-Agent")
          let (data, response) = try await transport.data(for: request)
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          print(
            "Public decoded block itag \(candidate.itag), offset \(offset): HTTP \(status), bytes \(data.count)"
          )
          guard status == 206, data.count == last - offset + 1 else { break }
          total += Int64(data.count)
        }
        print("Public decoded complete bytes: \(total)/\(length)")
      }
    }
  } catch {
    print("Public WEB_REMIX decode/CDN failed: \(cipherProbeFailure(error))")
  }
  return true
}

private func cipherProbeFailure(_ error: Error) -> String {
  if let error = error as? PlayerCipherError { return String(describing: error) }
  if case DecodingError.keyNotFound(let key, _) = error {
    return "missing field \(key.stringValue)"
  }
  if error is DecodingError { return "response decoding" }
  if let error = error as? URLError { return "transport \(error.code.rawValue)" }
  return String(describing: type(of: error))
}

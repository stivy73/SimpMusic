import Foundation
import ExtensionFoundation
import NowPlaying
import Observation

@main
struct NoteNarrateRemotePlayer: RemoteMediaSessionExtension {
  var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
    RemoteMediaSessionExtensionConfiguration(extension: self)
  }
  func session(_ attributes: CastRemoteState) async throws -> CastLockScreenSession {
    CastLockScreenSession(attributes)
  }
}

@Observable @MainActor
final class CastLockScreenSession: RemoteMediaSessionRepresentable {
  let id: String
  var attributes: CastRemoteState
  @ObservationIgnored private var tail: Task<CastRemoteState, Error>?
  @ObservationIgnored private var serial = UUID()
  init(_ attributes: CastRemoteState) { self.attributes = attributes; id = attributes.id }
  func update(_ attributes: CastRemoteState) { self.attributes = attributes }

  var content: (any MediaContentRepresentable)? {
    MusicContent(id: attributes.trackID, songTitle: attributes.title,
      artistName: attributes.artist, albumName: "", type: .audio,
      duration: .finite(attributes.duration),
      artwork: attributes.artwork.map { url in
        Artwork(id: url.absoluteString) { _ in
          let (data, response) = try await URLSession.shared.data(from: url)
          guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8 * 1024 * 1024 else { throw CastRemoteError.invalidMessage }
          return try ArtworkRepresentation(data: data)
        }
      })
  }
  var playbackSnapshot: MediaPlaybackSnapshot? {
    let state: MediaPlaybackSnapshot.PlaybackState
    switch attributes.playback {
    case "PLAYING": state = .playing()
    case "PAUSED": state = .paused
    case "BUFFERING", "LOADING": state = .buffering
    default: state = .stopped
    }
    return MediaPlaybackSnapshot(state: state, elapsedTime: attributes.position, timestamp: attributes.timestamp)
  }
  var commands: [MediaCommand] {
    let ready = attributes.certificate.count == 32
    return [
      .play { try await self.send("PLAY") }.enabled(ready),
      .pause { try await self.send("PAUSE") }.enabled(ready),
      .seekToPosition { time in try await self.send("SEEK", value: time) }.enabled(ready && attributes.duration > 0)
    ]
  }
  var devices: [MediaDevice] {
    let capabilities: [MediaDevice.Capability] = attributes.certificate.count == 32 ? [
      .absoluteVolume(Float(attributes.volume)) { [weak self] value in
        try await self?.send("SET_VOLUME", value: Double(value))
      }
    ] : []
    return [MediaDevice(id: attributes.host, name: attributes.deviceName, type: .speaker, capabilities: capabilities)]
  }

  private func send(_ command: String, value: Double? = nil) async throws {
    let previous = tail; let token = UUID(); serial = token
    let task = Task { @MainActor [self] in
      if let previous { _ = try? await previous.value }
      let state = attributes
      let channel = CastDeviceChannel(host: state.host, port: state.port, pin: state.certificate)
      let next = try await channel.perform(command, value: value, state: state)
      guard attributes.id == state.id, attributes.trackID == state.trackID,
        attributes.timestamp <= next.timestamp else { throw CastRemoteError.changedSession }
      attributes = next
      return next
    }
    tail = task
    defer { if serial == token { tail = nil } }
    _ = try await task.value
  }
}

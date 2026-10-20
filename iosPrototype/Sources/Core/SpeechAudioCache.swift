import CryptoKit
import Foundation

/// Disposable, local-only audio cache. No keys, lyrics or titles in filenames or metadata.
public actor SpeechAudioCache {
  public static let shared = SpeechAudioCache()
  public static let maximumEntryBytes = 20 * 1024 * 1024
  private let directory: URL
  private let maximumBytes: Int

  public init(directory: URL? = nil, maximumBytes: Int = 100 * 1024 * 1024) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MeaningSpeech-v1", isDirectory: true)
    self.maximumBytes = maximumBytes
  }

  public nonisolated static func key(text: String, voice: String, style: VoiceStyle) -> String {
    // Length-prefix each field, so text and style cannot collide through separators.
    let fields = [
      "pcm16le-mono-24000-v1", GeminiService.speechModel, voice, style.instruction, text,
    ]
    let data = Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func file(_ key: String) -> URL? {
    guard key.count == 64, key.allSatisfy({ $0.isHexDigit }) else { return nil }
    return directory.appendingPathComponent(key).appendingPathExtension("pcm")
  }

  public func read(_ key: String) -> Data? {
    guard let url = file(key),
      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size > 32, size <= Self.maximumEntryBytes + 32,
      let stored = try? Data(contentsOf: url)
    else { return nil }
    let pcm = Data(stored.dropFirst(32))
    guard pcm.count.isMultiple(of: 2), Data(SHA256.hash(data: pcm)) == stored.prefix(32) else {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    return pcm
  }

  /// Called only after a complete, successful stream. Cache failure must not prevent listening.
  public func store(_ pcm: Data, key: String) {
    guard !Task.isCancelled, !pcm.isEmpty, pcm.count.isMultiple(of: 2),
      pcm.count <= Self.maximumEntryBytes, pcm.count + 32 <= maximumBytes,
      let url = file(key)
    else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var excluded = directory
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excluded.setResourceValues(values)
      var stored = Data(SHA256.hash(data: pcm))
      stored.append(pcm)
      try stored.write(to: url, options: .atomic)
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
      )
      .filter { $0.pathExtension == "pcm" }
      .compactMap { url -> (URL, Int, Date)? in
        guard
          let info = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return nil }
        return (url, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast)
      }.sorted { $0.2 < $1.2 }
      var size = files.reduce(0) { $0 + $1.1 }
      for (url, bytes, _) in files where size > maximumBytes {
        try FileManager.default.removeItem(at: url)
        size -= bytes
      }
    } catch {
      // A cache is optional; the stream is still playable.
    }
  }
}

/// Retains only one bounded recording; failed or cancelled streams never become cache entries.
public actor SpeechRecording {
  private var data = Data()
  public init() {}
  public func append(_ chunk: Data) throws {
    guard data.count + chunk.count <= SpeechAudioCache.maximumEntryBytes else {
      throw PrototypeError.invalidResponse
    }
    data.append(chunk)
  }
  public func contents() -> Data { data }
}

import AVFoundation
import Combine
import CryptoKit
import Foundation

public enum LocalFiles {
  public static func directory(_ name: String) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
      .appendingPathComponent("NoteNarrate", isDirectory: true).appendingPathComponent(
        name, isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
  }
  public static func key(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public static func write<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(value).write(to: url, options: .atomic)
  }
  public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

public struct OfflineRecord: Identifiable, Codable, Sendable {
  public enum State: String, Codable, Sendable {
    case preparing, downloading, verifying, ready, paused, failed
  }
  public var id: String { track.id }
  public let track: PlaybackTrack
  public var state: State
  public var progress: Double = 0
  public var bytes: Int64 = 0
  public var expectedBytes: Int64?
  public var expectedDuration: Double?
  public var error: String?
  public var fileName: String?
  public var added = Date()
  public init(track: PlaybackTrack) {
    self.track = track
    state = .preparing
  }
}

public enum OfflineError: LocalizedError {
  case incomplete, unsupportedStream, missingFile, storage
  public var errorDescription: String? {
    switch self {
    case .incomplete:
      "Il file è incompleto o non riproducibile. Non è stato salvato come scaricato."
    case .unsupportedStream:
      "Questo flusso è disponibile solo in streaming. Prova un’altra versione del brano."
    case .missingFile: "Il file scaricato non è più disponibile. Scarica nuovamente il brano."
    case .storage: "Spazio disponibile insufficiente per completare il download."
    }
  }
}

public enum OfflineValidation {
  public static func byteCount(
    actual: Int64, expected: Int64?, status: Int, contentRange: String? = nil
  ) throws {
    guard actual > 1024, status == 200 || status == 206 else { throw OfflineError.incomplete }
    if let expected, expected > 0, actual != expected { throw OfflineError.incomplete }
    if status == 206 {
      guard let contentRange, contentRange == "bytes 0-\(actual - 1)/\(actual)" else {
        throw OfflineError.incomplete
      }
    }
  }
  /// Walk every compressed sample, so an MP4 header claiming full duration cannot certify a truncated file.
  public static func playableFile(_ url: URL, expectedDuration: Double?) async throws -> Double {
    let asset = AVURLAsset(url: url)
    guard try await asset.load(.isPlayable) else { throw OfflineError.incomplete }
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let track = tracks.first else { throw OfflineError.incomplete }
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0 else { throw OfflineError.incomplete }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw OfflineError.incomplete }
    reader.add(output)
    guard reader.startReading() else { throw OfflineError.incomplete }
    var last = 0.0
    while let sample = output.copyNextSampleBuffer() {
      if Task.isCancelled {
        reader.cancelReading()
        throw CancellationError()
      }
      let end =
        CMSampleBufferGetPresentationTimeStamp(sample).seconds
        + CMSampleBufferGetDuration(sample).seconds
      if end.isFinite { last = max(last, end) }
    }
    guard reader.status == .completed, last >= duration - 0.25 else {
      throw OfflineError.incomplete
    }
    if let expectedDuration, expectedDuration.isFinite, expectedDuration > 0,
      abs(duration - expectedDuration) > max(1, expectedDuration * 0.02)
    {
      throw OfflineError.incomplete
    }
    return duration
  }
}

@MainActor
public final class OfflineLibrary: ObservableObject {
  @Published public private(set) var records: [OfflineRecord]
  @Published public var persistenceError: String?
  public let directory: URL
  private var manifest: URL { directory.appendingPathComponent("index.json") }
  public init(directory: URL = LocalFiles.directory("Offline")) {
    self.directory = directory
    records =
      LocalFiles.read([OfflineRecord].self, from: directory.appendingPathComponent("index.json"))
      ?? []
    // Ready always means a file of the validated size still exists.
    for index in records.indices where records[index].state == .ready {
      guard let name = records[index].fileName,
        name == URL(fileURLWithPath: name).lastPathComponent,
        let size = try? directory.appendingPathComponent(name).resourceValues(forKeys: [
          .fileSizeKey
        ]).fileSize,
        Int64(size) == records[index].bytes
      else {
        records[index].state = .failed
        records[index].error = OfflineError.missingFile.localizedDescription
        continue
      }
    }
  }
  public var ready: [OfflineRecord] { records.filter { $0.state == .ready } }
  public var totalBytes: Int64 { ready.reduce(0) { $0 + $1.bytes } }
  public func url(for id: String) -> URL? {
    guard let record = records.first(where: { $0.id == id && $0.state == .ready }),
      let name = record.fileName, name == URL(fileURLWithPath: name).lastPathComponent
    else { return nil }
    let url = directory.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }
  public func begin(_ track: PlaybackTrack) {
    if let index = records.firstIndex(where: { $0.id == track.id }) {
      if records[index].state == .ready { return }
      records[index] = OfflineRecord(track: track)
    } else {
      records.append(OfflineRecord(track: track))
    }
    persist()
  }
  public func update(
    _ id: String, state: OfflineRecord.State, progress: Double? = nil,
    expected: Int64? = nil, expectedDuration: Double? = nil, error: String? = nil
  ) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    records[index].state = state
    records[index].error = error
    if let progress, progress.isFinite { records[index].progress = min(1, max(0, progress)) }
    if let expected { records[index].expectedBytes = expected }
    if let expectedDuration, expectedDuration.isFinite, expectedDuration > 0 {
      records[index].expectedDuration = expectedDuration
    }
    if state != .downloading || progress == nil { persist() }
  }
  public func finish(
    _ id: String, temporary: URL, status: Int, contentRange: String?, maxBytes: Int64? = nil
  ) async throws {
    guard let record = records.first(where: { $0.id == id }) else { throw CancellationError() }
    update(id, state: .verifying)
    let actual = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    try OfflineValidation.byteCount(
      actual: actual, expected: record.expectedBytes, status: status, contentRange: contentRange)
    _ = try await OfflineValidation.playableFile(
      temporary, expectedDuration: record.expectedDuration ?? record.track.durationSeconds)
    try Task.checkCancellation()
    guard let index = records.firstIndex(where: { $0.id == id }), records[index].state == .verifying
    else { throw CancellationError() }
    if let maxBytes, totalBytes + actual > maxBytes { throw OfflineError.storage }
    let name = LocalFiles.key(id) + ".m4a"
    let destination = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporary, to: destination)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    var saved = destination
    try? saved.setResourceValues(excluded)
    records[index].fileName = name
    records[index].bytes = actual
    records[index].state = .ready
    records[index].progress = 1
    records[index].error = nil
    persist()
  }
  public func remove(_ id: String) throws {
    if let url = url(for: id) { try FileManager.default.removeItem(at: url) }
    records.removeAll { $0.id == id }
    persist()
  }
  public func reconcile(active: Set<String>) {
    for index in records.indices
    where [.preparing, .downloading, .verifying].contains(records[index].state)
      && !active.contains(records[index].id)
    {
      records[index].state = .failed
      records[index].error = "Download interrotto. Tocca Riprova."
    }
    persist()
  }
  private func persist() {
    do {
      try LocalFiles.write(records, to: manifest)
      persistenceError = nil
    } catch { persistenceError = "Impossibile salvare lo stato dei download." }
  }
}

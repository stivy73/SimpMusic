import Foundation
import PrototypeCore

@MainActor
func probeStreamingIfRequested(_ args: [String]) async throws -> Bool {
  guard ["--stream-key-file", "--latency-key-file"].contains(args.first ?? "") else { return false }
  guard args.count == 2 else { throw PrototypeError.missingKey }
  let lines = try String(contentsOfFile: args[1], encoding: .utf8).components(
    separatedBy: .newlines)
  guard
    let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Gemini key" }
    ), index + 1 < lines.count
  else { throw PrototypeError.missingKey }
  let key = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
  guard key.range(of: #"^AIza[A-Za-z0-9_-]{35}$"#, options: .regularExpression) != nil else {
    throw PrototypeError.missingKey
  }
  // Original diagnostic text, comparable in length to an interpretation; no song lyrics sent.
  let text =
    "La canzone racconta il ricordo di una persona amata, attraverso immagini quotidiane che acquistano un significato nuovo con il passare del tempo. Il protagonista ripensa alle parole non dette e alle occasioni in cui avrebbe potuto ascoltare meglio. La storia si muove fra il desiderio di tornare indietro e la consapevolezza che il passato non può essere cambiato. Alla fine resta una possibilità concreta: imparare a vivere il presente con maggiore attenzione.\n\nL'interpretazione suggerisce una riflessione sulla fragilità dei legami e sulla difficoltà di esprimere ciò che proviamo. La distanza non è soltanto fisica, ma anche emotiva: può nascere dal silenzio o dalla paura di mostrarsi vulnerabili. Le immagini del ricordo diventano così un invito a riconoscere il valore delle relazioni mentre le stiamo vivendo. È una lettura possibile del racconto, non una ricostruzione della vita privata dell'artista."
  if args.first == "--latency-key-file" {
    let service = GeminiService(
      session: URLSession(configuration: .ephemeral, delegate: ProbeTimings(), delegateQueue: nil))
    for optimized in [false, true] {
      let start = Date()
      let result = try await service.explain(
        key: key, model: "gemini-3.8-flash",
        title: "Ricordi (test diagnostico)", artist: "Autore di prova", lyrics: text,
        optimizeForLatency: optimized)
      print(
        "Interpretation \(optimized ? "low" : "default"): \(String(format: "%.2f", Date().timeIntervalSince(start))) seconds; chars \(result.count); in range \(Interpretation.isExpectedLength(result))"
      )
      let speechStart = Date()
      do {
        try await service.streamSpeech(key: key, text: result, voice: "Kore", style: .professional)
        { _ in
          print(
            "First PCM: \(String(format: "%.2f", Date().timeIntervalSince(speechStart))) seconds; total \(String(format: "%.2f", Date().timeIntervalSince(start))) seconds"
          )
          throw LatencyProbeFinished.firstAudio
        }
      } catch LatencyProbeFinished.firstAudio {}
    }
    return true
  }
  let start = Date()
  let measurement = StreamMeasurement(start: start)
  let recording = SpeechRecording()
  let player = PCMStreamPlayer()
  do {
    try await GeminiService().streamSpeech(
      key: key, text: text, voice: "Kore", style: .professional
    ) { chunk in
      await measurement.receive(chunk)
      try await recording.append(chunk)
      try await player.enqueue(chunk) {
        print(
          "Playback first buffer: \(String(format: "%.2f", Date().timeIntervalSince(start))) seconds"
        )
      }
    }
    let complete = Date()
    let pcm = await recording.contents()
    let duration = Double(pcm.count) / 48_000
    print(
      "Stream complete: \(String(format: "%.2f", complete.timeIntervalSince(start))) seconds; PCM duration \(String(format: "%.2f", duration)) seconds; bytes \(pcm.count)"
    )
    try await player.finish()
    print("Last buffer played: \(String(format: "%.2f", Date().timeIntervalSince(start))) seconds")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "stivy-stream-probe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = SpeechAudioCache(directory: directory)
    let cacheKey = SpeechAudioCache.key(text: text, voice: "Kore", style: .professional)
    await cache.store(pcm, key: cacheKey)
    let cacheStart = Date()
    guard let cached = await cache.read(cacheKey), cached == pcm else {
      throw PrototypeError.invalidResponse
    }
    print(
      "Disk cache hit, no HTTP: \(String(format: "%.3f", Date().timeIntervalSince(cacheStart))) seconds; checksum OK"
    )
  } catch {
    player.stop()
    throw error
  }
  return true
}

private actor StreamMeasurement {
  let start: Date
  var received = false
  init(start: Date) { self.start = start }
  func receive(_ chunk: Data) {
    if !received {
      print(
        "First network PCM: \(String(format: "%.2f", Date().timeIntervalSince(start))) seconds; bytes \(chunk.count)"
      )
      received = true
    }
  }
}

private enum LatencyProbeFinished: Error { case firstAudio }

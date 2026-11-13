import AVFoundation
import Foundation
import Security
import Combine

@MainActor
final class NarrationModel: ObservableObject {
  @Published var key = ""
  @Published var model = UserDefaults.standard.string(forKey: "meaningModel") ?? "gemini-3.8-flash"
  @Published var searchEvidence: SongSearchEvidence?
  @Published var sourceURL: URL?
  @Published var attribution: String?
  @Published var text = ""
  @Published var busy = false
  @Published var isReading = false
  @Published var error: String?
  @Published var useGeminiVoice = false
  private var revision = UUID()
  private var task: Task<Void, Never>?
  private var pcm: PCMStreamPlayer?
  private let speaker = AVSpeechSynthesizer()
  init() { key = SecretStore.read() ?? ""; useGeminiVoice = UserDefaults.standard.bool(forKey: "geminiVoice") }
  func save() throws { try SecretStore.save(key); UserDefaults.standard.set(model, forKey: "meaningModel"); UserDefaults.standard.set(useGeminiVoice, forKey: "geminiVoice") }
  func explain(id: String, title: String, artist: String) {
    stop(); error = nil; text = ""; attribution = nil; sourceURL = nil; searchEvidence = nil; busy = true
    let requestRevision = revision
    let key = key; let model = model
    task = Task { [weak self] in
      guard let self else { return }
      defer { if self.revision == requestRevision { self.busy = false } }
      do {
        let result = try await SongWebMeaning().explain(title: title, artist: artist, model: model, key: key)
        try Task.checkCancellation()
        self.searchEvidence = result.evidence
        self.attribution = result.evidence == nil ? nil : "Fonti · Google Search"
        self.text = result.text
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func clearInterpretation() {
    stop(); text = ""; error = nil; attribution = nil; sourceURL = nil; searchEvidence = nil
  }
  func read() {
    guard !text.isEmpty else { return }
    stop(); busy = true; isReading=true
    let requestRevision = revision
    let text = text; let key = key
    task = Task { [weak self] in
      guard let self else { return }; defer { if self.revision == requestRevision { self.busy = false;self.isReading=false } }
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true)
        if self.useGeminiVoice {
          let player = PCMStreamPlayer(gain: NarrationLevel.gain); self.pcm = player
          try await GeminiService().streamSpeech(key: key, text: text, voice: "Kore", style: .empathetic) { chunk in
            try await player.enqueue(chunk, onStart: {})
          }
          try await player.finish()
        } else {
          let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: "it-IT")
          self.speaker.speak(utterance)
          while self.speaker.isSpeaking { try await Task.sleep(for: .milliseconds(100)); try Task.checkCancellation() }
        }
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func stop() { revision = UUID(); task?.cancel(); task = nil; pcm?.stop(); pcm = nil; speaker.stopSpeaking(at: .immediate); busy = false;isReading=false }
}
enum SecretStore {
  static let service = "com.stivy.notenarrate.applemusic.gemini"
  static func read() -> String? {
    let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"api-key",kSecReturnData as String:true]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess, let data=result as? Data else { return nil }
    return String(data:data,encoding:.utf8)
  }
  static func save(_ value:String) throws {
    let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"api-key"]
    if value.isEmpty { SecItemDelete(query as CFDictionary); return }
    let data=Data(value.utf8)
    let updated=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
    if updated==errSecSuccess { return }
    guard updated==errSecItemNotFound else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(updated)) }
    var insert=query;insert[kSecValueData as String]=data;insert[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let result=SecItemAdd(insert as CFDictionary,nil)
    guard result==errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(result)) }
  }
}

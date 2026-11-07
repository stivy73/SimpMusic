import Combine
import Foundation
import Network

@MainActor final class AudioPreferences: ObservableObject {
  static let shared = AudioPreferences()
  @Published var wifiQuality =
    AudioQuality(rawValue: UserDefaults.standard.string(forKey: "wifiQuality") ?? "") ?? .high
  {
    didSet { UserDefaults.standard.set(wifiQuality.rawValue, forKey: "wifiQuality") }
  }
  @Published var cellularQuality =
    AudioQuality(rawValue: UserDefaults.standard.string(forKey: "cellularQuality") ?? "") ?? .normal
  {
    didSet { UserDefaults.standard.set(cellularQuality.rawValue, forKey: "cellularQuality") }
  }
  @Published var downloadQuality =
    AudioQuality(rawValue: UserDefaults.standard.string(forKey: "downloadQuality") ?? "") ?? .high
  {
    didSet { UserDefaults.standard.set(downloadQuality.rawValue, forKey: "downloadQuality") }
  }
  @Published var effects =
    LocalFiles.read(
      AudioEffects.self,
      from: LocalFiles.directory("Playback").appendingPathComponent("effects.json"))
    ?? AudioEffects()
  {
    didSet {
      if effects.valid {
        try? LocalFiles.write(
          effects, to: LocalFiles.directory("Playback").appendingPathComponent("effects.json"))
      }
    }
  }
  @Published var crossfade = UserDefaults.standard.double(forKey: "crossfadeSeconds") {
    didSet {
      let normalized = crossfade.isFinite ? min(12, max(0, crossfade)) : 0
      if crossfade != normalized {
        crossfade = normalized
        return
      }
      UserDefaults.standard.set(crossfade, forKey: "crossfadeSeconds")
    }
  }
  @Published var djMode = UserDefaults.standard.bool(forKey: "djMode") {
    didSet { UserDefaults.standard.set(djMode, forKey: "djMode") }
  }
  @Published private(set) var expensive = true
  @Published private(set) var networkRevision = UUID()
  private let monitor = NWPathMonitor()
  var currentQuality: AudioQuality { expensive ? cellularQuality : wifiQuality }
  var networkDiagnostic: String {
    let path = monitor.currentPath
    let kind = path.usesInterfaceType(.cellular) ? "cellular"
      : path.usesInterfaceType(.wifi) ? "wifi"
      : path.usesInterfaceType(.wiredEthernet) ? "ethernet" : "other"
    return "\(kind), available=\(path.status == .satisfied), expensive=\(path.isExpensive), constrained=\(path.isConstrained)"
  }
  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let value = path.isExpensive || path.isConstrained || path.usesInterfaceType(.cellular)
      Task { @MainActor [weak self] in
        self?.expensive = value
        self?.networkRevision = UUID()
      }
    }
    monitor.start(queue: DispatchQueue(label: "NoteNarrate.network-preferences"))
  }
}

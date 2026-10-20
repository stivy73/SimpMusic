import Foundation
import Security

enum SecureStore {
  private static var service: String {
    #if os(macOS)
      "NoteNarrate.macOS"
    #else
      "StivySimpMusic.iOS"
    #endif
  }
  static func read(_ name: String) -> String {
    #if DEBUG
      // Isolated macOS UI tests must not access the user's Google session or API key.
      if ProcessInfo.processInfo.arguments.contains("--test-isolated") { return "" }
    #endif
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: name,
      kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func save(_ value: String, as name: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: name,
    ]
    let data = Data(value.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let created = SecItemAdd(item as CFDictionary, nil)
      guard created == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(created))
      }
    } else if status != errSecSuccess {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
}

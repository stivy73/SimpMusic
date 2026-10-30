// Called only by AppleAPI.py, which captures the token in memory and never logs it.
import CryptoKit
import Foundation

func encoded(_ value: Data) -> String {
  value.base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
do {
  guard CommandLine.arguments.count == 4 else { exit(1) }
  let key = try P256.Signing.PrivateKey(pemRepresentation:
    String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))
  let now = Int(Date().timeIntervalSince1970)
  let header = try JSONSerialization.data(withJSONObject:
    ["alg": "ES256", "kid": CommandLine.arguments[2], "typ": "JWT"])
  let claims = try JSONSerialization.data(withJSONObject:
    ["iss": CommandLine.arguments[3], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"])
  let unsigned = encoded(header) + "." + encoded(claims)
  let signature = try key.signature(for: Data(unsigned.utf8))
  guard key.publicKey.isValidSignature(signature, for: Data(unsigned.utf8)),
    signature.rawRepresentation.count == 64 else { exit(1) }
  print(unsigned + "." + encoded(signature.rawRepresentation))
} catch {
  FileHandle.standardError.write(Data("Apple token signing failed\n".utf8))
  exit(1)
}

// Port of SimpMusic core FaradayCipherEngine / RemotePlayerConfigParser /
// ZemerCipherSolver (GPL-3.0, same license as this repository).
// The registry names functions in YouTube's own public player script. It never
// receives account cookies, video IDs, signatures or playback URLs.
import Foundation
import WebKit
import YouTubeSDK

public enum PlayerCipherError: Error {
  case invalidMetadata, invalidStream, invalidSignature, invalidN, download, script, timedOut
}

public actor YouTubePlayerCipher {
  public struct PlayerInfo: Equatable, Sendable {
    public let id: String
    public let signatureTimestamp: Int
  }
  public static let shared = YouTubePlayerCipher()
  private var cached: (PlayerInfo, CipherPlayerConfig, Date)?
  // playerInfo() can overlap during queue prefetch and foreground playback.
  // Keep the exact configuration associated with every recently returned ID;
  // the iframe endpoint can assign different current variants to two requests.
  private var configurations: [String: (PlayerInfo, CipherPlayerConfig)] = [:]
  private var configurationOrder: [String] = []
  private var cachedScript: (String, String)?
  private let download: @Sendable (URL, Int) async throws -> Data
  private let execute: @Sendable (String, [String], [String]) async throws -> CipherAnswers

  public init() {
    download = Self.fetch
    execute = { try await CipherWebWorker.run(script: $0, signatures: $1, nValues: $2) }
  }
  init(
    download: @escaping @Sendable (URL, Int) async throws -> Data,
    execute: @escaping @Sendable (String, [String], [String]) async throws -> CipherAnswers = {
      try await CipherWebWorker.run(script: $0, signatures: $1, nValues: $2)
    }
  ) {
    self.download = download
    self.execute = execute
  }

  public func invalidate() {
    cached = nil
    cachedScript = nil
    configurations.removeAll()
    configurationOrder.removeAll()
  }

  public func playerInfo() async throws -> PlayerInfo {
    if let cached, Date().timeIntervalSince(cached.2) < 1800 { return cached.0 }
    async let iframe = download(URL(string: "https://www.youtube.com/iframe_api")!, 512 * 1024)
    async let registry = download(
      URL(
        string:
          "https://raw.githubusercontent.com/maxrave-dev/simpmusic-files/main/registry/player_configs.json"
      )!, 2 * 1024 * 1024)
    let (iframeData, registryData) = try await (iframe, registry)
    guard let source = String(data: iframeData, encoding: .utf8),
      let match = source.range(of: #"player\\?/([a-f0-9]{8})\\?/"#, options: .regularExpression)
    else { throw PlayerCipherError.invalidMetadata }
    let hash =
      String(source[match]).replacingOccurrences(of: "\\", with: "")
      .split(separator: "/").dropFirst().first.map(String.init) ?? ""
    let config = try CipherPlayerConfig.parse(registryData, playerID: hash)
    let info = PlayerInfo(id: hash, signatureTimestamp: config.timestamp)
    cached = (info, config, Date())
    configurations[hash] = (info, config)
    configurationOrder.removeAll { $0 == hash }
    configurationOrder.append(hash)
    while configurationOrder.count > 4 {
      configurations.removeValue(forKey: configurationOrder.removeFirst())
    }
    return info
  }

  public func decipher(video: YouTubeVideo, player: PlayerInfo) async throws -> YouTubeVideo {
    guard let configuration = configurations[player.id], configuration.0 == player else {
      throw PlayerCipherError.invalidMetadata
    }
    guard var streaming = video.streamingData else { throw PlayerCipherError.invalidStream }
    var requests: [Int: CipherStreamRequest] = [:]
    for (index, stream) in streaming.adaptiveFormats.enumerated()
    where stream.mimeType.hasPrefix("audio/mp4") && stream.mimeType.contains("mp4a") {
      if let request = try? CipherStreamRequest(url: stream.url, cipher: stream.signatureCipher) {
        requests[index] = request
      } else {
        // An obsolete or malformed format must not hide an otherwise usable AAC
        // or HLS alternative, and its undeciphered URL must never reach playback.
        streaming.adaptiveFormats[index].url = nil
        streaming.adaptiveFormats[index].signatureCipher = nil
      }
    }
    guard !requests.isEmpty else {
      var result = video
      result.streamingData = streaming
      return result
    }
    let signatures = Array(Set(requests.values.compactMap(\.signature)))
    let nValues = Array(Set(requests.values.compactMap(\.n)))
    var answer = CipherAnswers(signatures: [:], nValues: [:])
    if !signatures.isEmpty || !nValues.isEmpty {
      let script: String
      if let cachedScript, cachedScript.0 == player.id {
        script = cachedScript.1
      } else {
        let url = URL(
          string: "https://www.youtube.com/s/player/\(player.id)/player_ias.vflset/en_GB/base.js")!
        let data = try await download(url, 8 * 1024 * 1024)
        guard let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else {
          throw PlayerCipherError.script
        }
        script = decoded
        cachedScript = (player.id, script)
      }
      let workerScript = try configuration.1.exporting(script)
      answer = try await execute(workerScript, signatures, nValues)
    }
    for (index, request) in requests {
      streaming.adaptiveFormats[index].url = try request.resolved(using: answer).absoluteString
      streaming.adaptiveFormats[index].signatureCipher = nil
    }
    var result = video
    result.streamingData = streaming
    return result
  }

  private static func fetch(_ url: URL, limit: Int) async throws -> Data {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 20
    let session = URLSession(
      configuration: config, delegate: CipherNoRedirect(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.setValue("okhttp/5.4.0", forHTTPHeaderField: "User-Agent")
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      response.expectedContentLength <= limit
    else { throw PlayerCipherError.download }
    var data = Data()
    data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
    for try await byte in bytes {
      guard data.count < limit else { throw PlayerCipherError.download }
      data.append(byte)
    }
    try Task.checkCancellation()
    return data
  }
}

private final class CipherNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) { completionHandler(nil) }
}

struct CipherPlayerConfig: Equatable, Sendable {
  let signatureExpression: String
  let nClass: String
  let timestamp: Int

  static func parse(_ data: Data, playerID: String) throws -> Self {
    guard playerID.range(of: #"^[a-f0-9]{8}$"#, options: .regularExpression) != nil,
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let schema = root["schemaVersion"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(),
      schema.doubleValue == 1,
      let players = root["players"] as? [String: [String: Any]]
    else { throw PlayerCipherError.invalidMetadata }
    var found: Self?
    for (hash, entry) in players {
      let aliases = entry["aliases"] as? [String] ?? []
      guard hash == playerID || aliases.contains(playerID) else { continue }
      guard found == nil,
        hash.range(of: #"^[a-f0-9]{8}$"#, options: .regularExpression) != nil,
        entry["aliases"] == nil || entry["aliases"] is [String],
        Set([hash] + aliases).count == aliases.count + 1,
        aliases.allSatisfy({ $0.range(of: #"^[a-f0-9]{8}$"#, options: .regularExpression) != nil }),
        let sig = entry["sig"] as? String,
        sig.range(
          of: #"^[A-Za-z_$][A-Za-z0-9_$]{0,7}\([0-9]{1,9},[0-9]{1,9},INPUT\)$"#,
          options: .regularExpression) != nil,
        let nClass = entry["nClass"] as? String,
        nClass.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]{0,7}$"#, options: .regularExpression) != nil,
        let timestamp = entry["sts"] as? NSNumber,
        CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
        timestamp.doubleValue.rounded() == timestamp.doubleValue,
        (1...100000).contains(timestamp.intValue)
      else { throw PlayerCipherError.invalidMetadata }
      found = Self(signatureExpression: sig, nClass: nClass, timestamp: timestamp.intValue)
    }
    guard let found else { throw PlayerCipherError.invalidMetadata }
    return found
  }

  func exporting(_ script: String) throws -> String {
    let trailer = "})(_yt_player);"
    guard script.components(separatedBy: trailer).count == 2 else { throw PlayerCipherError.script }
    let sig = signatureExpression.replacingOccurrences(of: "INPUT", with: "sig")
    let exports =
      ";window._cipherSigFunc=function(sig){try{return \(sig);}catch(e){return null;}};"
      + "window._nTransformFunc=function(n){try{var u=new g.\(nClass)('https://x.googlevideo.com/videoplayback?n='+encodeURIComponent(n),true);var t=u.get('n');return(t&&t!==n)?t:null;}catch(e){return null;}};"
    return "globalThis._yt_player={};\n"
      + script.replacingOccurrences(of: trailer, with: exports + trailer)
  }
}

struct CipherAnswers: Sendable {
  let signatures: [String: String]
  let nValues: [String: String]
}

struct CipherStreamRequest: Sendable {
  let url: URL
  let signature: String?
  let signatureParameter: String
  let n: String?

  init(url: String?, cipher: String?) throws {
    var address = url
    var signature: String?
    var parameter = "signature"
    if address == nil, let cipher {
      guard cipher.count <= 256 * 1024,
        cipher.range(of: #"%(?![A-Fa-f0-9]{2})"#, options: .regularExpression) == nil,
        !cipher.contains("#"), !cipher.contains(where: { $0.isWhitespace }),
        let components = URLComponents(string: "https://cipher.invalid/?" + cipher)
      else { throw PlayerCipherError.invalidStream }
      let items = components.queryItems ?? []
      guard Set(items.map(\.name)).count == items.count else {
        throw PlayerCipherError.invalidStream
      }
      address = items.first { $0.name == "url" }?.value
      signature = items.first { $0.name == "s" }?.value
      parameter = items.first { $0.name == "sp" }?.value ?? "signature"
      guard let signature, !signature.isEmpty, signature.count <= 65536,
        parameter.range(of: #"^[A-Za-z][A-Za-z0-9_]{0,31}$"#, options: .regularExpression) != nil
      else { throw PlayerCipherError.invalidStream }
    }
    guard let address, let parsed = URL(string: address), parsed.scheme == "https",
      parsed.user == nil, parsed.password == nil, parsed.port == nil || parsed.port == 443,
      let host = parsed.host, host == "googlevideo.com" || host.hasSuffix(".googlevideo.com"),
      let components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
    else { throw PlayerCipherError.invalidStream }
    let nItems = (components.queryItems ?? []).filter { $0.name == "n" }
    guard nItems.count <= 1 else { throw PlayerCipherError.invalidStream }
    if let n = nItems.first?.value {
      guard !n.isEmpty, n.count <= 65536 else { throw PlayerCipherError.invalidStream }
    }
    self.url = parsed
    self.signature = signature
    self.signatureParameter = parameter
    self.n = nItems.first?.value
  }

  func resolved(using answers: CipherAnswers) throws -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw PlayerCipherError.invalidStream
    }
    // Preserve all signed percent-encoded query bytes except the two transformed
    // fields. Reconstructing queryItems can change +, escapes or signed ordering.
    var fields = (components.percentEncodedQuery ?? "").split(
      separator: "&", omittingEmptySubsequences: false
    ).map(String.init)
    func replacement(_ key: String, _ value: String) throws -> String {
      guard !value.isEmpty, value.count <= 65536,
        value.range(of: #"^[A-Za-z0-9_./+=-]+$"#, options: .regularExpression) != nil,
        let encoded = value.addingPercentEncoding(
          withAllowedCharacters: CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))
      else { throw PlayerCipherError.invalidStream }
      return key + "=" + encoded
    }
    if let signature {
      guard let solved = answers.signatures[signature] else {
        throw PlayerCipherError.invalidStream
      }
      fields.removeAll {
        $0.split(separator: "=", maxSplits: 1).first?.removingPercentEncoding == signatureParameter
      }
      do { fields.append(try replacement(signatureParameter, solved)) } catch {
        throw PlayerCipherError.invalidSignature
      }
    }
    if let n {
      guard let solved = answers.nValues[n], solved != n else {
        throw PlayerCipherError.invalidStream
      }
      let updated: String
      do { updated = try replacement("n", solved) } catch { throw PlayerCipherError.invalidN }
      fields = fields.map { field in
        field.split(separator: "=", maxSplits: 1).first?.removingPercentEncoding == "n"
          ? updated : field
      }
    }
    components.percentEncodedQuery = fields.joined(separator: "&")
    guard let result = components.url else { throw PlayerCipherError.invalidStream }
    return result
  }
}

/// Run the public player in a disposable WebKit content process, not the audio
/// process. No account session, native bridge or networking is exposed. Public
/// JavaScriptCore has no execution limit API; a Task timeout cannot stop it.
@MainActor
final class CipherWebWorker: NSObject, WKNavigationDelegate {
  private var webView: WKWebView?
  private var completion: CheckedContinuation<CipherAnswers, Error>?
  private var deadline: Task<Void, Never>?
  private let script: String
  private let signatures: [String]
  private let nValues: [String]
  private var started = false
  private let timeoutSeconds: Double

  private init(script: String, signatures: [String], nValues: [String], timeoutSeconds: Double) {
    self.script = script
    self.signatures = signatures
    self.nValues = nValues
    self.timeoutSeconds = timeoutSeconds
  }

  static func run(
    script: String, signatures: [String], nValues: [String], timeoutSeconds: Double = 10
  ) async throws
    -> CipherAnswers
  {
    let worker = CipherWebWorker(
      script: script, signatures: signatures, nValues: nValues, timeoutSeconds: timeoutSeconds)
    return try await worker.execute()
  }

  private func execute() async throws -> CipherAnswers {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        completion = continuation
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        webView = view
        view.navigationDelegate = self
        let timeoutSeconds = self.timeoutSeconds
        deadline = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
          self?.finish(.failure(PlayerCipherError.timedOut))
        }
        view.loadHTMLString(
          """
          <!doctype html><html><head><meta http-equiv="Content-Security-Policy"
          content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'; img-src 'none'; media-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"></head><body></body></html>
          """, baseURL: nil)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(
      !started && navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !started, self.webView === webView, completion != nil else { return }
    started = true
    webView.evaluateJavaScript(
      script + "\n;void 0;",
      completionHandler: { [weak self] _, error in
        guard let self, self.completion != nil else { return }
        guard error == nil else {
          self.finish(.failure(PlayerCipherError.script))
          return
        }
        guard let view = self.webView else { return }
        view.callAsyncJavaScript(
          """
          const sig = {}, n = {};
          for (const value of signatures) {
            const solved = window._cipherSigFunc(value);
            if (typeof solved !== 'string' || !solved || solved.length > 65536) throw new Error('cipher');
            sig[value] = solved;
          }
          for (const value of nValues) {
            const solved = window._nTransformFunc(value);
            if (typeof solved !== 'string' || !solved || solved === value || solved.length > 65536) throw new Error('cipher');
            n[value] = solved;
          }
          return {signatures:sig,nValues:n};
          """, arguments: ["signatures": self.signatures, "nValues": self.nValues],
          in: nil, in: .page
        ) { [weak self] result in
          guard let self, self.completion != nil else { return }
          guard case .success(let raw) = result, let object = raw as? [String: Any],
            let sig = object["signatures"] as? [String: String],
            let n = object["nValues"] as? [String: String],
            Set(sig.keys) == Set(self.signatures), Set(n.keys) == Set(self.nValues)
          else {
            self.finish(.failure(PlayerCipherError.script))
            return
          }
          self.finish(.success(CipherAnswers(signatures: sig, nValues: n)))
        }
      })
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failure(PlayerCipherError.script))
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(.failure(PlayerCipherError.script))
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) { finish(.failure(PlayerCipherError.script)) }

  private func finish(_ result: Result<CipherAnswers, Error>) {
    guard let completion else { return }
    self.completion = nil
    deadline?.cancel()
    deadline = nil
    webView?.navigationDelegate = nil
    webView?.stopLoading()
    webView = nil
    completion.resume(with: result)
  }
}

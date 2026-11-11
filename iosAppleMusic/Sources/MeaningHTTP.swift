// Adapted from ShareNarrate bounded, cookie-free content transport. See INTERPRETATION.md.
import Foundation
import CoreFoundation

enum MeaningContentError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

struct MeaningHTTPResponse {
    let data: Data
    let response: HTTPURLResponse
    var text: String {
        var charset = response.textEncodingName
        if charset == nil {
            let prefix = String(decoding: data.prefix(8192), as: UTF8.self)
            if let pattern = try? NSRegularExpression(pattern: "<meta[^>]+charset\\s*=\\s*['\"]?([A-Za-z0-9._-]+)", options: .caseInsensitive),
               let match = pattern.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)), let range = Range(match.range(at: 1), in: prefix) {
                charset = String(prefix[range])
            }
        }
        if let charset = charset {
            let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if encoding != kCFStringEncodingInvalidId,
               let decoded = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) {
                return decoded
            }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Ephemeral, cookie-free requests with a hard bound while receiving bytes.
/// Google credentials are accepted only for the Google API host and never follow redirects.
enum MeaningHTTP {
    static func request(_ url: URL, method: String = "GET", body: Data? = nil,
                        headers: [String: String] = [:], maxBytes: Int = 3 * 1024 * 1024,
                        timeout: TimeInterval = 15, allowedHosts: Set<String>? = nil,
                        followExternalRedirects: Bool = false) async throws -> MeaningHTTPResponse {
        let hosts = followExternalRedirects ? nil : (allowedHosts ?? Set([url.host?.lowercased() ?? ""]))
        guard safe(url, hosts: hosts) else { throw MeaningContentError.message("Il collegamento non è sicuro o non è supportato.") }
        if headers.keys.contains(where: { $0.lowercased() == "x-goog-api-key" }),
           hosts != Set(["generativelanguage.googleapis.com"]) {
            throw MeaningContentError.message("Destinazione Google non valida.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("NoteNarrateMusic/0.1 (song meaning)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html;q=0.9,text/plain;q=0.8", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if body != nil { request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        let receiver = BoundedMeaningRequest(maxBytes: maxBytes, hosts: hosts,
                                            canRedirect: method == "GET" && headers["x-goog-api-key"] == nil,
                                            timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { receiver.start(request, continuation: $0) }
        }, onCancel: { receiver.cancel() })
    }

    static func safe(_ url: URL, hosts: Set<String>? = nil) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil &&
            (url.port == nil || url.port == 443) && (hosts == nil || hosts!.contains(url.host!.lowercased()))
    }

    static func json(_ url: URL, method: String = "GET", body: [String: Any]? = nil,
                     headers: [String: String] = [:], maxBytes: Int = 3 * 1024 * 1024,
                     timeout: TimeInterval = 15) async throws -> Any {
        let result = try await request(url, method: method, body: try body.map { try JSONSerialization.data(withJSONObject: $0) },
                                       headers: headers, maxBytes: maxBytes, timeout: timeout)
        guard (200...299).contains(result.response.statusCode) else {
            throw MeaningContentError.message("Il servizio non è disponibile (HTTP \(result.response.statusCode)). Riprova.")
        }
        return try JSONSerialization.jsonObject(with: result.data)
    }
}

private final class BoundedMeaningRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<MeaningHTTPResponse, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var bytes = Data()
    private var response: HTTPURLResponse?
    private var cancellationRequested = false
    private var finished = false
    private var redirects = 0
    private let maxBytes: Int
    private let hosts: Set<String>?
    private let canRedirect: Bool
    private let timeout: TimeInterval

    init(maxBytes: Int, hosts: Set<String>?, canRedirect: Bool, timeout: TimeInterval) {
        self.maxBytes = maxBytes; self.hosts = hosts; self.canRedirect = canRedirect; self.timeout = timeout
    }

    func start(_ request: URLRequest, continuation: CheckedContinuation<MeaningHTTPResponse, Error>) {
        lock.lock()
        if cancellationRequested { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock(); cancellationRequested = true; let task = task; lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<MeaningHTTPResponse, Error>) {
        lock.lock()
        guard !finished, let continuation = continuation else { lock.unlock(); return }
        finished = true; self.continuation = nil
        let session = session; self.session = nil; self.task = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.failure(MeaningContentError.message("La risposta della pagina non è valida."))); return
        }
        if response.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel); finish(.failure(MeaningContentError.message("Il contenuto supera il limite consentito. Condividi una selezione."))); return
        }
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= maxBytes else {
            dataTask.cancel(); finish(.failure(MeaningContentError.message("Il contenuto supera il limite consentito. Condividi una selezione."))); return
        }
        bytes.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard canRedirect, redirects <= 5, let url = request.url, MeaningHTTP.safe(url, hosts: hosts) else {
            completionHandler(nil)
            finish(.failure(MeaningContentError.message("Il collegamento contiene un reindirizzamento non supportato.")))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(MeaningContentError.message("Non riesco a recuperare il contenuto. Controlla la connessione e riprova.")))
            }
        } else if let response = response { finish(.success(MeaningHTTPResponse(data: bytes, response: response))) }
        else { finish(.failure(MeaningContentError.message("La risposta del servizio è incompleta."))) }
    }
}

extension String {
    func contentReplacing(_ pattern: String, with replacement: String = "", options: NSRegularExpression.Options = []) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return self }
        return expression.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: replacement)
    }
    func contentMatches(_ pattern: String, options: NSRegularExpression.Options = []) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return expression.firstMatch(in: self, range: NSRange(startIndex..., in: self)) != nil
    }
    var contentTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

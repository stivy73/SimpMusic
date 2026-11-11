import Foundation

struct LicensedLyricsDocument: Codable, Sendable {
  let appleMusicID: String
  let text: String
  let provider: String
  let copyright: String
  let sourceURL: URL
  let expiresAt: Date
  let permittedUses: [String]
  func validate(for id: String, now: Date = .now) throws {
    guard appleMusicID == id, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
      text.utf8.count <= 100_000, !provider.isEmpty, !copyright.isEmpty,
      sourceURL.scheme == "https", sourceURL.host != nil, expiresAt > now,
      permittedUses.contains("aiInterpretation") else { throw LyricsServiceError.notPermitted }
  }
}
enum LyricsServiceError: LocalizedError {
  case notConfigured, notPermitted, unavailable
  var errorDescription: String? {
    switch self {
    case .notConfigured: "Il servizio di testi con licenza non è ancora attivo. La narrazione sarà disponibile dopo l’attivazione del fornitore."
    case .notPermitted: "Il fornitore non autorizza questo testo per l’interpretazione AI, oppure l’autorizzazione è scaduta."
    case .unavailable: "Il servizio di testi non ha restituito una risposta utilizzabile. Riprova."
    }
  }
}
struct LicensedLyricsService: Sendable {
  let endpoint: URL?
  init(endpoint: URL? = (Bundle.main.object(forInfoDictionaryKey:"LicensedLyricsEndpoint") as? String).flatMap(URL.init(string:))) { self.endpoint=endpoint }
  func lyrics(id:String,title:String,artist:String) async throws -> LicensedLyricsDocument {
    guard let endpoint, endpoint.scheme == "https", endpoint.host != nil else { throw LyricsServiceError.notConfigured }
    var request=URLRequest(url:endpoint,timeoutInterval:25);request.httpMethod="POST"
    request.setValue("application/json",forHTTPHeaderField:"Content-Type")
    request.httpBody=try JSONSerialization.data(withJSONObject:["appleMusicID":id,"title":title,"artist":artist])
    let config=URLSessionConfiguration.ephemeral;config.httpShouldSetCookies=false
    let session=URLSession(configuration:config,delegate:LyricsRedirectPolicy(),delegateQueue:nil);defer { session.invalidateAndCancel() }
    let(data,response)=try await session.data(for:request)
    guard let http=response as? HTTPURLResponse,http.statusCode==200,data.count<=200_000,
      http.url?.scheme=="https",http.url?.host==endpoint.host else { throw LyricsServiceError.unavailable }
    let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
    let document=try decoder.decode(LicensedLyricsDocument.self,from:data)
    try document.validate(for:id);return document
  }
}

// Do not forward song metadata to a different endpoint through a redirect.
private final class LyricsRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

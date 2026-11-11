import SwiftUI
import WebKit

// Source presentation adapted from ShareNarrate. Google HTML is kept unchanged.
struct SongSearchSourcesView: View {
  let evidence: SongSearchEvidence
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Fonti · Google Search").font(.caption.bold())
      ForEach(Array(evidence.sources.enumerated()), id: \.offset) { index, source in
        VStack(alignment: .leading, spacing: 3) {
          Text(source.passage).font(.caption).textSelection(.enabled)
          Link("[\(index + 1)] \(source.title)", destination: source.url).font(.caption)
        }
      }
      SearchSuggestionsView(html: evidence.suggestionsHTML).frame(height: 120)
    }
  }
}

/// Google's supplied Search Suggestions are displayed unchanged; scripts are disabled.
private struct SearchSuggestionsView: UIViewRepresentable {
  let html: String
  @Environment(\.openURL) private var openURL
  func makeCoordinator() -> Coordinator { Coordinator(open: { openURL($0) }) }
  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = context.coordinator
    view.isOpaque = false
    view.backgroundColor = .clear
    view.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
    return view
  }
  func updateUIView(_ view: WKWebView, context: Context) {
    if context.coordinator.html != html {
      context.coordinator.html = html
      view.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
    }
  }
  final class Coordinator: NSObject, WKNavigationDelegate {
    var html = ""
    let open: (URL) -> Void
    init(open: @escaping (URL) -> Void) { self.open = open }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      if navigationAction.navigationType == .linkActivated {
        if let url = navigationAction.request.url, url.scheme == "https" { open(url) }
        decisionHandler(.cancel)
      } else { decisionHandler(.allow) }
    }
  }
}

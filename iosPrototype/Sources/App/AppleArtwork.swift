#if os(iOS)
  import UIKit

  /// Shared by system Now Playing and the visible CarPlay page. No whole-library prefetch.
  @MainActor
  final class AppleArtworkStore {
    static let shared = AppleArtworkStore()
    private let cache = NSCache<NSURL, UIImage>()
    private var requests: [URL: Task<UIImage?, Never>] = [:]
    private init() {
      cache.totalCostLimit = 32 * 1024 * 1024
      cache.countLimit = 128
    }
    func image(primary: URL?, videoID: String? = nil) async -> UIImage? {
      for url in ArtworkSource.candidates(primary: primary, videoID: videoID) {
        if Task.isCancelled { return nil }
        if let image = cache.object(forKey: url as NSURL) { return image }
        while requests[url] == nil && requests.count >= 4 {
          try? await Task.sleep(for: .milliseconds(30))
          if Task.isCancelled { return nil }
        }
        if let request = requests[url] {
          if let image = await request.value { return image }
          continue
        }
        let request = Task<UIImage?, Never> {
          var request = URLRequest(url: url, timeoutInterval: 12)
          request.cachePolicy = .returnCacheDataElseLoad
          guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            data.count <= 8 * 1024 * 1024, let source = UIImage(data: data),
            let image = source.preparingThumbnail(of: CGSize(width: 600, height: 600))
          else { return nil }
          return image.withRenderingMode(.alwaysOriginal)
        }
        requests[url] = request
        let image = await request.value
        requests[url] = nil
        if let image {
          cache.setObject(
            image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
          return Task.isCancelled ? nil : image
        }
      }
      return nil
    }
  }
#endif

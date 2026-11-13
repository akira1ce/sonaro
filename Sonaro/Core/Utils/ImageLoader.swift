import Foundation
import ImageIO

/// Loads and caches remote images (album/playlist covers).
///
/// Two layers: decoded `NSImage`s in a process-wide `NSCache` so a row scrolling
/// back into view paints its cover on the first frame, and the raw bytes in a
/// disk-backed `URLCache` so covers survive cold launch without a re-download.
/// Downloads are decoded and downsampled off the main thread to the size the URL
/// asks for (`?param=NyN`), so a 48 pt row never holds a 600 px bitmap.
/// Concurrent requests for the same URL share a single download.
actor ImageLoader {
    static let shared = ImageLoader()

    private static let memory: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 64 << 20
        return cache
    }()

    private let urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
    private let session: URLSession
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = urlCache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: cfg)
    }

    /// Synchronous peek used by `CachedImage` when a view is rebuilt.
    static func cached(_ url: URL) -> PlatformImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    /// Disk bytes currently occupied by cached cover data.
    func cacheUsage() -> Int { urlCache.currentDiskUsage }

    /// Drops every cached cover. Images already on screen are unaffected; new
    /// covers are downloaded again on demand.
    func clearCache() {
        Self.memory.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }

    func image(for url: URL) async -> PlatformImage? {
        if let cached = Self.cached(url) { return cached }
        if let task = inFlight[url] { return await task.value }

        let session = self.session
        let maxPixelSize = Self.maxPixelSize(for: url)
        let task = Task.detached(priority: .utility) { () -> PlatformImage? in
            guard let (data, _) = try? await session.data(from: url),
                  let (image, cost) = Self.downsample(data, maxPixelSize: maxPixelSize)
            else { return nil }
            Self.memory.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    /// The CDN honours `param=NyN`, so decode straight to that size instead of
    /// full resolution and let the display shrink it.
    private static func maxPixelSize(for url: URL) -> Int {
        let requested = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "param" }?
            .value?
            .split(separator: "y")
            .first
            .flatMap { Int($0) }
        return min(max(requested ?? 600, 64), 1200)
    }

    private static func downsample(_ data: Data, maxPixelSize: Int) -> (PlatformImage, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = PlatformImage(cgImage: cgImage,
                                  size: CGSize(width: cgImage.width, height: cgImage.height))
        return (image, cgImage.width * cgImage.height * 4)
    }
}

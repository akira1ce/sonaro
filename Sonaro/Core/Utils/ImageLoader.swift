import Foundation

/// Loads and caches remote images (album/playlist covers). The bytes live in a
/// disk-backed `URLCache` so covers survive re-scroll and cold launch without a
/// re-download. Concurrent requests for the same URL share a single download.
/// Used by `CachedImage` and the player's lock-screen artwork, so a cover is
/// fetched at most once across the whole UI.
actor ImageLoader {
    static let shared = ImageLoader()

    private let urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
    private let session: URLSession
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = urlCache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: cfg)
    }

    /// Disk bytes currently occupied by cached cover data.
    func cacheUsage() -> Int { urlCache.currentDiskUsage }

    /// Drops every cached cover. Images already on screen are unaffected; new
    /// covers are downloaded again on demand.
    func clearCache() {
        urlCache.removeAllCachedResponses()
    }

    func image(for url: URL) async -> PlatformImage? {
        if let task = inFlight[url] { return await task.value }

        let session = self.session
        let task = Task.detached(priority: .utility) { () -> PlatformImage? in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return PlatformImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }
}

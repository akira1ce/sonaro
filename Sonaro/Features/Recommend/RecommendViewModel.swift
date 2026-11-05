import Foundation

@MainActor
final class RecommendViewModel: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var topPlaylists: [Playlist] = []
    @Published private(set) var qualityPlaylists: [Playlist] = []
    @Published private(set) var hotArtists: [Artist] = []
    @Published private(set) var isLoading = false
    @Published var error: String?
    private var hasLoaded = false

    /// Loads once on first appear; use `reload()` for pull-to-refresh.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        error = nil
        do {
            async let daily = MusicService.dailyPlaylists()
            async let top = MusicService.toplistPlaylists()
            async let quality = MusicService.highQualityPlaylists()
            async let artists = MusicService.hotArtists()
            (playlists, topPlaylists, qualityPlaylists, hotArtists) =
                try await (daily, top, quality, artists)
            hasLoaded = true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "加载失败，请稍后重试"
        }
        isLoading = false
    }
}

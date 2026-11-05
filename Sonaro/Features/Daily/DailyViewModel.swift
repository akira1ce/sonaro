import Foundation

@MainActor
final class DailyViewModel: ObservableObject {
    @Published private(set) var songs: [Song] = []
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
            songs = try await MusicService.dailySongs()
            hasLoaded = true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "加载失败，请稍后重试"
        }
        isLoading = false
    }
}

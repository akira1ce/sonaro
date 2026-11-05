import Foundation

/// Global store of the user's liked songs. Like `AuthManager` / `PlayerManager`,
/// it's a shared `@MainActor ObservableObject` created in `SonaroApp` — features
/// read `isLiked` and call `toggle`, they never hit the network themselves.
@MainActor
final class LikeManager: ObservableObject {

    typealias LikeUpdater = @Sendable (_ id: Int, _ like: Bool) async throws -> Bool

    /// IDs of songs in the user's "我喜欢的音乐" list.
    @Published private(set) var likedIDs: Set<Int> = []
    @Published private(set) var updatingIDs: Set<Int> = []

    private let updateLike: LikeUpdater
    private var sessionGeneration = 0

    init(updateLike: @escaping LikeUpdater = { id, like in
        try await MusicService.setLiked(id: id, like: like)
    }) {
        self.updateLike = updateLike
    }

    func isLiked(_ songID: Int) -> Bool { likedIDs.contains(songID) }
    func isUpdating(_ songID: Int) -> Bool { updatingIDs.contains(songID) }

    /// Reloads the liked-song IDs for the signed-in user. Reads the uid from the
    /// cached profile (available on cold launch), so callers don't thread it in.
    func refresh() async {
        guard let uid = SessionStore.shared.cachedProfile?.userId, uid != 0 else { return }
        let generation = sessionGeneration
        if let ids = try? await MusicService.likedSongIDs(uid: uid) {
            guard sessionGeneration == generation else { return }
            likedIDs = Set(ids)
        }
    }

    /// Optimistically flips the liked state, then confirms with the backend and
    /// reverts if the request fails — the heart never lies about a persisted change.
    func toggle(_ song: Song) {
        let id = song.id
        guard updatingIDs.insert(id).inserted else { return }
        let generation = sessionGeneration
        let wasLiked = likedIDs.contains(id)
        if wasLiked { likedIDs.remove(id) } else { likedIDs.insert(id) }

        Task {
            let ok = (try? await updateLike(id, !wasLiked)) ?? false
            guard sessionGeneration == generation else { return }
            if !ok {
                if wasLiked { likedIDs.insert(id) } else { likedIDs.remove(id) }
            }
            updatingIDs.remove(id)
        }
    }

    func clear() {
        sessionGeneration += 1
        likedIDs = []
        updatingIDs = []
    }

    #if DEBUG
    /// Marks the seeded demo song (`id == -1`) liked for screenshots.
    func seedDemo() { likedIDs = [-1] }
    #endif
}

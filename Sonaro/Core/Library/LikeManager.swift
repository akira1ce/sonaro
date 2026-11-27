import Foundation

/// Global store of the user's liked songs. Like `AuthManager` / `PlayerManager`,
/// it's a shared `@MainActor ObservableObject` created in `SonaroApp` — features
/// read `isLiked` and call `toggle`, they never hit the network themselves.
@MainActor
final class LikeManager: ObservableObject {

    typealias LikeLoader = @Sendable (_ uid: Int) async throws -> [Int]
    typealias LikeUpdater = @Sendable (_ id: Int, _ like: Bool) async throws -> Bool

    /// IDs of songs in the user's "我喜欢的音乐" list.
    @Published private(set) var likedIDs: Set<Int> = []
    @Published private(set) var updatingIDs: Set<Int> = []

    private let loadLikes: LikeLoader
    private var userID: Int?
    private let updateLike: LikeUpdater
    private var sessionGeneration = 0

    init(loadLikes: @escaping LikeLoader = { try await MusicService.likedSongIDs(uid: $0) },
         updateLike: @escaping LikeUpdater = { id, like in
        try await MusicService.setLiked(id: id, like: like)
    }) {
        self.loadLikes = loadLikes
        self.updateLike = updateLike
    }

    func isLiked(_ songID: Int) -> Bool { likedIDs.contains(songID) }
    func isUpdating(_ songID: Int) -> Bool { updatingIDs.contains(songID) }

    /// A new account starts empty, even if its first request fails.
    func refresh(uid: Int) async {
        guard uid > 0, !Task.isCancelled else { return }
        if userID != uid {
            clear()
            userID = uid
        }
        let generation = sessionGeneration
        if let ids = try? await loadLikes(uid) {
            guard !Task.isCancelled, sessionGeneration == generation else { return }
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
            guard sessionGeneration == generation else { return }
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
        userID = nil
        likedIDs = []
        updatingIDs = []
    }

    #if DEBUG
    /// Marks the seeded demo song (`id == -1`) liked for screenshots.
    func seedDemo() { likedIDs = [-1] }
    #endif
}

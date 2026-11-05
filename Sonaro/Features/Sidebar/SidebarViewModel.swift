import Foundation

extension Notification.Name {
    /// Posted after subscribing / unsubscribing a playlist so the sidebar's
    /// 收藏 list can reload.
    static let playlistSubscriptionsChanged = Notification.Name("playlistSubscriptionsChanged")
}

/// Loads the two lists the sidebar needs from `/user/playlist`: the auto-generated
/// liked-music playlist (specialType 5) and the favorited playlists.
@MainActor
final class SidebarViewModel: ObservableObject {
    @Published private(set) var likedPlaylist: Playlist?
    @Published private(set) var favorites: [Playlist] = []
    @Published private(set) var error: String?

    private var loadedUID: Int?

    func load(uid: Int, force: Bool = false) async {
        guard force || loadedUID != uid else { return }
        do {
            let all = try await MusicService.userPlaylists(uid: uid)
            likedPlaylist = all.first { $0.specialType == 5 }
            favorites = all.filter { $0.subscribed && $0.specialType != 5 }
            loadedUID = uid
            error = nil
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "加载失败"
        }
    }
}

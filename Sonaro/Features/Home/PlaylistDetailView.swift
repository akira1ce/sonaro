import SwiftUI

/// Playlist contents: cover + metadata header, then a track list. Reused by Home
/// (daily playlists) and Library (favorited playlists).
struct PlaylistDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    let playlist: Playlist

    /// The `/playlist/detail` shape, which carries creator / description / update
    /// time that list cards don't. Falls back to the card data until it loads.
    @State private var detail: Playlist?
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var appeared = false
    @State private var isSubscribed = false
    @State private var isSubscribing = false

    private var info: Playlist { detail ?? playlist }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 12)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: appeared)

                if let error {
                    InfoState(icon: "wifi.exclamationmark", title: "加载失败", message: error,
                              actionTitle: "重试", action: { Task { await load() } })
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else {
                    trackList
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 12)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.08),
                            value: appeared
                        )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(AppBackground())
        .navigationTitle(playlist.name)
        .task(id: playlist.id) { await load() }
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        DetailHeader(
            artworkURL: info.coverURL(600),
            title: info.name,
            creator: info.creator,
            stats: statsText,
            description: info.subtitle
        ) {
            actions
        }
    }

    private var statsText: String {
        var parts: [String] = []
        // Prefer the playlist's own count: the track endpoint caps at 300.
        let count = info.trackCount > 0 ? info.trackCount : songs.count
        if count > 0 { parts.append("\(count) 首") }
        if info.playCount > 0 { parts.append("\(Format.playCount(info.playCount)) 次播放") }
        if info.updateTime > 0 { parts.append("更新于 \(Format.date(info.updateTime))") }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                player.play(songs, startAt: 0)
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.playAction)
            .disabled(songs.isEmpty)

            if !isOwnPlaylist {
                Button {
                    toggleSubscription()
                } label: {
                    Label(isSubscribed ? "已收藏" : "收藏",
                          systemImage: isSubscribed ? "checkmark" : "plus")
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSubscribing)
            }
        }
    }

    /// Subscribing to your own playlist is a no-op on the backend, so don't offer
    /// it. The auto-generated liked-music playlist can expose no creator, hence
    /// the `specialType` check too.
    private var isOwnPlaylist: Bool {
        if info.specialType == 5 { return true }
        guard let uid = auth.profile?.userId, uid != 0 else { return false }
        return info.creator?.userId == uid
    }

    // MARK: Tracks

    @ViewBuilder
    private var trackList: some View {
        if isLoading, songs.isEmpty {
            skeletonList
        } else if songs.isEmpty {
            InfoState(icon: "music.note.list", title: "这个歌单还没有歌曲")
                .frame(maxWidth: .infinity)
        } else {
            // Lazy so a 300-track playlist only keeps the visible rows alive —
            // a plain VStack would instantiate (and re-layout) every row on scroll.
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let isCurrent = player.currentSong?.id == song.id
                    SongRow(
                        song: song,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && player.isPlaying,
                        showsAlbum: true,
                        showsHoverActions: true,
                        onPlay: { player.play(songs, startAt: index) }
                    )
                    if song.id != songs.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                SongRowPlaceholder()
                Divider().padding(.leading, 60)
            }
        }
    }

    // MARK: Actions

    private func toggleSubscription() {
        let target = !isSubscribed
        isSubscribed = target
        isSubscribing = true
        Task {
            let ok = (try? await MusicService.setPlaylistSubscribed(
                id: playlist.id, subscribed: target)) ?? false
            if ok {
                NotificationCenter.default.post(name: .playlistSubscriptionsChanged, object: nil)
            } else {
                isSubscribed = !target
            }
            isSubscribing = false
        }
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        error = nil
        isSubscribed = playlist.subscribed

        async let detailResult = MusicService.playlistDetail(id: playlist.id)
        async let tracksResult = MusicService.playlistTracks(id: playlist.id)

        if let loaded = try? await detailResult {
            detail = loaded
            isSubscribed = loaded.subscribed
        }
        do {
            songs = try await tracksResult
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "加载失败"
        }
        isLoading = false
    }
}

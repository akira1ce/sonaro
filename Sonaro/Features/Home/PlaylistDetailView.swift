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
    /// Tracks fetched so far; the next page's `offset`.
    @State private var loadedOffset = 0
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var loadMoreFailed = false
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var isPreparingPlayAll = false

    private static let pageSize = 200

    private var info: Playlist { detail ?? playlist }

    var body: some View {
        ScrollViewReader { proxy in
            page
                .overlay(alignment: .bottomTrailing) {
                    if player.currentSong != nil, !songs.isEmpty {
                        locateCurrentButton(proxy: proxy)
                    }
                }
        }
        .navigationTitle(playlist.name)
        .task(id: playlist.id) { await load() }
        .onAppear { appeared = true }
    }

    private var page: some View {
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
    }

    // MARK: Locate current track

    private func locateCurrentButton(proxy: ScrollViewProxy) -> some View {
        Button {
            revealCurrent(proxy: proxy)
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .help("定位到正在播放")
        .padding(20)
    }

    /// Pages until the current track is in the list, then scrolls to it. Following
    /// the queue may not belong to this playlist; then the button does nothing.
    private func revealCurrent(proxy: ScrollViewProxy) {
        guard let currentID = player.currentSong?.id else { return }
        Task {
            while !songs.contains(where: { $0.id == currentID }), canLoadMore {
                let before = loadedOffset
                await loadMore()
                if loadedOffset == before { break }
            }
            guard songs.contains(where: { $0.id == currentID }) else { return }
            if reduceMotion {
                proxy.scrollTo(currentID, anchor: .center)
            } else {
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(currentID, anchor: .center)
                }
            }
        }
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
        // The header count is the playlist's own; the list pages towards it.
        let count = info.trackCount > 0 ? info.trackCount : songs.count
        if count > 0 { parts.append("\(count) 首") }
        if info.playCount > 0 { parts.append("\(Format.playCount(info.playCount)) 次播放") }
        if info.updateTime > 0 { parts.append("更新于 \(Format.date(info.updateTime))") }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                playAll()
            } label: {
                if isPreparingPlayAll {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("播放全部", systemImage: "play.fill")
                        .padding(.horizontal, 6)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.playAction)
            .disabled(songs.isEmpty || isPreparingPlayAll)

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
            // Lazy + paged: only visible rows are built, and the next page is
            // fetched when the last loaded row appears, so an 800-track playlist
            // never downloads or instantiates all of it up front.
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let isCurrent = player.currentSong?.id == song.id
                    SongRow(
                        song: song,
                        isCurrent: isCurrent,
                        onPlay: { player.play(songs, startAt: index) }
                    )
                    .onAppear {
                        if song.id == songs.last?.id {
                            Task { await loadMore() }
                        }
                    }

                    if song.id != songs.last?.id {
                        Divider().padding(.leading, 68)
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                } else if loadMoreFailed {
                    Button("加载失败，点击重试") {
                        Task { await loadMore() }
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
            }
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                SongRowPlaceholder()
                Divider().padding(.leading, 68)
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
        loadMoreTask?.cancel()
        loadMoreTask = nil
        songs = []
        loadedOffset = 0
        canLoadMore = true
        isLoadingMore = false
        loadMoreFailed = false

        async let detailResult = MusicService.playlistDetail(id: playlist.id)

        if let loaded = try? await detailResult {
            detail = loaded
            isSubscribed = loaded.subscribed
        }
        do {
            let page = try await MusicService.playlistTracks(
                id: playlist.id, limit: Self.pageSize, offset: 0)
            songs = page
            loadedOffset = page.count
            canLoadMore = page.count == Self.pageSize
            loadMoreFailed = false
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "加载失败"
        }
        isLoading = false
    }

    // MARK: Pagination

    /// Appends the next page; joins an in-flight page instead of fetching twice.
    private func loadMore() async {
        if let inFlight = loadMoreTask {
            await inFlight.value
            return
        }
        guard error == nil, !isLoading, canLoadMore else { return }

        let playlistID = playlist.id
        let task = Task { await fetchNextPage(playlistID: playlistID) }
        loadMoreTask = task
        await task.value
        loadMoreTask = nil
    }

    private func fetchNextPage(playlistID: Int) async {
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }

        do {
            let page = try await MusicService.playlistTracks(
                id: playlistID, limit: Self.pageSize, offset: loadedOffset)
            guard playlistID == playlist.id else { return }
            let known = Set(songs.map(\.id))
            songs.append(contentsOf: page.filter { !known.contains($0.id) })
            loadedOffset += page.count
            canLoadMore = page.count == Self.pageSize
                && (info.trackCount <= 0 || loadedOffset < info.trackCount)
        } catch {
            guard playlistID == playlist.id else { return }
            loadMoreFailed = true
        }
    }

    /// 播放全部 needs the full queue, so finish paging before starting.
    private func playAll() {
        guard !songs.isEmpty, !isPreparingPlayAll else { return }
        isPreparingPlayAll = true
        Task {
            while canLoadMore {
                let before = loadedOffset
                await loadMore()
                if loadedOffset == before { break }
            }
            isPreparingPlayAll = false
            player.play(songs, startAt: 0)
        }
    }
}

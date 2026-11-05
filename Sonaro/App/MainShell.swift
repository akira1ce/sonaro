import SwiftUI
import Combine

/// Top-level navigation. macOS uses a sidebar split view with the docked mini
/// player and inline Now Playing.
struct MainShell: View {
    @State private var selection: SidebarItem = .recommend
    @State private var showNowPlaying = false
    /// Live frame of the split view's detail column, in `shellSpace`. The dock and
    /// Now Playing live at window level but must line up with the main area, so
    /// they need its real geometry — the sidebar is resizable and collapsible.
    @State private var detailFrame: CGRect = .zero
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var likes: LikeManager
    @EnvironmentObject private var player: PlayerManager
    @StateObject private var sidebar = SidebarViewModel()
    @State private var showLogoutConfirm = false

    /// Fraction of the main area's width the dock spans.
    private let dockWidthFraction: CGFloat = 0.8

    var body: some View {
        sidebarLayout
            // Both the dock and Now Playing sit at window level, deliberately
            // *outside* NavigationSplitView.
            //
            // The reason: on macOS a destination pushed onto a NavigationStack
            // renders above the layers of its own ancestors in the detail column.
            // Anything parked in that column gets covered by the playlist detail
            // page — which is exactly why every earlier dock variant vanished
            // there, and why Now Playing appeared to do nothing until you
            // navigated back. Out here nothing in the navigation hierarchy is an
            // ancestor, so nothing it does can cover, clip, or drop these.
            .overlay(alignment: .bottomLeading) { dock }
            .overlay { nowPlayingLayer }
            .coordinateSpace(.named(Self.shellSpace))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showNowPlaying)
            .task(id: auth.profile?.userId) {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SONARO_UINP"] == "1" { showNowPlaying = true }
                #endif
                await likes.refresh()
                guard let uid = auth.profile?.userId else { return }
                await sidebar.load(uid: uid)
            }
            .onReceive(NotificationCenter.default.publisher(for: .playlistSubscriptionsChanged)) { _ in
                guard let uid = auth.profile?.userId else { return }
                Task { await sidebar.load(uid: uid, force: true) }
            }
            .onKeyPress(.space) {
                player.togglePlayPause()
                return .handled
            }
    }

    // MARK: Window-level layers

    private static let shellSpace = "shell"

    /// The floating mini player: centered on the main area, 80% of its width.
    /// Positioned by hand from `detailFrame` rather than by an alignment guide,
    /// because it has to ignore the sidebar's width without being a child of the
    /// column that knows it.
    @ViewBuilder
    private var dock: some View {
        if !showNowPlaying, detailFrame.width > 0 {
            MiniPlayerView { showNowPlaying = true }
                .frame(width: detailFrame.width * dockWidthFraction)
                .offset(x: detailFrame.minX + detailFrame.width * (1 - dockWidthFraction) / 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Now Playing covers the whole window, sidebar included — it's a takeover,
    /// so it has to outrank every navigation layer beneath it.
    @ViewBuilder
    private var nowPlayingLayer: some View {
        if showNowPlaying {
            NowPlayingView(onClose: { showNowPlaying = false })
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: macOS sidebar

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Label("推荐", systemImage: "sparkles")
                    .tag(SidebarItem.recommend)
                Label("搜索", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)

                Section("我的") {
                    SidebarMenuItem(title: "我喜欢的音乐", icon: "heart.fill",
                                    isSelected: selection == .liked)
                        .tag(SidebarItem.liked)
                    SidebarMenuItem(title: "每日推荐", icon: "calendar",
                                    isSelected: selection == .daily)
                        .tag(SidebarItem.daily)
                    SidebarMenuItem(title: "最近播放", icon: "clock.fill",
                                    isSelected: selection == .recent)
                        .tag(SidebarItem.recent)
                }

                Section("收藏的歌单") {
                    ForEach(sidebar.favorites) { playlist in
                        SidebarPlaylistRow(playlist: playlist)
                            .tag(SidebarItem.playlist(playlist.id))
                    }
                    if sidebar.favorites.isEmpty {
                        Text(sidebar.error ?? "暂无收藏歌单")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Sonaro")
            .frame(minWidth: 210)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    userMenu
                        .padding(.vertical, 6)
                }
            }
        } detail: {
            NavigationStack {
                screen(for: selection)
                    .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
                    .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
            }
                // Report the main area's geometry up to the window-level layers.
                // They can't ask the split view how wide the sidebar is, so the
                // column measures itself instead.
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.shellSpace))
                } action: { frame in
                    detailFrame = frame
                }
        }
        // Buttons keep the stable system accent.
        .tint(Theme.accent)
        .confirmationDialog("确定要退出登录吗？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await auth.logout() } }
            Button("取消", role: .cancel) {}
        }
    }

    /// Avatar + nickname pinned to the sidebar bottom. Only the trailing icon opens
    /// the menu; settings and logout live there, so neither is a tab.
    private var userMenu: some View {
        HStack(spacing: 10) {
            Avatar(url: auth.profile?.avatarURL(96), size: 32)
                .fixedSize()

            Text(auth.profile?.nickname ?? "未登录")
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Menu {
                Button {
                    selection = .settings
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                Divider()
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("账号")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { selection }, set: { if let value = $0 { selection = value } })
    }

    @ViewBuilder
    private func screen(for item: SidebarItem) -> some View {
        switch item {
        case .recommend:
            RecommendView()
        case .search:
            SearchView()
        case .liked:
            if let playlist = sidebar.likedPlaylist {
                PlaylistDetailView(playlist: playlist)
                    .id(playlist.id)
            } else {
                sidebarLoading
            }
        case .daily:
            DailyView()
        case .recent:
            RecentPlayedView()
        case .playlist(let id):
            if let playlist = sidebar.favorites.first(where: { $0.id == id }) {
                PlaylistDetailView(playlist: playlist)
                    .id(playlist.id)
            } else {
                InfoState(icon: "music.note.list", title: "歌单已不在收藏中")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var sidebarLoading: some View {
        if let error = sidebar.error {
            InfoState(icon: "wifi.exclamationmark", title: "加载失败", message: error,
                      actionTitle: "重试", action: {
                          guard let uid = auth.profile?.userId else { return }
                          Task { await sidebar.load(uid: uid, force: true) }
                      })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum SidebarItem: Hashable {
    case recommend, search, liked, daily, recent, settings
    case playlist(Int)
}

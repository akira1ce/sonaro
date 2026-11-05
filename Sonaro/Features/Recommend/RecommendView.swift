import SwiftUI

/// 推荐: the landing page. Shows daily recommended playlists, playlists from
/// the charts, editor-picked high-quality playlists, and hot artists.
struct RecommendView: View {
    @StateObject private var vm = RecommendViewModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// Shelf column width, measured to fill the loading skeletons.
    @State private var shelvesWidth: CGFloat = 0

    private var hasContent: Bool {
        !vm.playlists.isEmpty || !vm.topPlaylists.isEmpty
            || !vm.qualityPlaylists.isEmpty || !vm.hotArtists.isEmpty
    }

    var body: some View {
        ScrollView {
            if let error = vm.error, !hasContent {
                InfoState(icon: "wifi.exclamationmark", title: "加载失败", message: error,
                          actionTitle: "重试", action: { Task { await vm.reload() } })
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if !vm.isLoading, !hasContent {
                InfoState(icon: "music.note.list", title: "暂无推荐",
                          message: "稍后再来看看，或检查服务器设置")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                shelves
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 12)
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.05),
                        value: appeared
                    )
            }
        }
        .background(AppBackground())
        .navigationTitle("推荐")
        .refreshable { await vm.reload() }
        .task { await vm.loadIfNeeded() }
        .onAppear { appeared = true }
    }

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 24) {
            shelf(title: "每日推荐歌单", subtitle: "根据你的口味挑选",
                  playlists: vm.playlists, showsSubtitle: true)
            shelf(title: "排行榜歌单", subtitle: "实时热度",
                  playlists: vm.topPlaylists, showsSubtitle: false)
            shelf(title: "精品歌单", subtitle: "编辑精选",
                  playlists: vm.qualityPlaylists, showsSubtitle: true)
            artistShelf
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            shelvesWidth = width
        }
    }

    /// Enough skeletons to cover the visible shelf width (36 = shelf + inner padding).
    private var playlistPlaceholderCount: Int {
        guard shelvesWidth > 0 else { return 4 }
        return max(4, Int(ceil((shelvesWidth - 36 + 14) / (168 + 14))))
    }

    private var artistPlaceholderCount: Int {
        guard shelvesWidth > 0 else { return 5 }
        return max(5, Int(ceil((shelvesWidth - 36 + 16) / (120 + 16))))
    }

    /// A shelf is hidden once loaded empty; while loading it shows placeholders.
    @ViewBuilder
    private func shelf(title: String, subtitle: String,
                       playlists: [Playlist], showsSubtitle: Bool) -> some View {
        if !playlists.isEmpty || vm.isLoading {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, subtitle: subtitle)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        if playlists.isEmpty {
                            ForEach(0..<playlistPlaceholderCount, id: \.self) { _ in
                                PlaylistCardPlaceholder()
                            }
                        } else {
                            ForEach(playlists) { playlist in
                                NavigationLink(value: playlist) {
                                    PlaylistCard(playlist: playlist, width: 168,
                                                 showsSubtitle: showsSubtitle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var artistShelf: some View {
        if !vm.hotArtists.isEmpty || vm.isLoading {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "热门歌手", subtitle: "大家都在听")
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        if vm.hotArtists.isEmpty {
                            ForEach(0..<artistPlaceholderCount, id: \.self) { _ in
                                ArtistCardPlaceholder()
                            }
                        } else {
                            ForEach(vm.hotArtists) { artist in
                                NavigationLink(value: artist) {
                                    ArtistCard(artist: artist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Redacted-style placeholder while playlists load.
private struct PlaylistCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Color.appFill)
                .frame(width: 168, height: 168)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.appFill)
                .frame(width: 110, height: 12)
        }
        .redacted(reason: .placeholder)
        .skeletonPulse()
    }
}

/// Redacted-style placeholder while artists load.
private struct ArtistCardPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color.appFill)
                .frame(width: 120, height: 120)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.appFill)
                .frame(width: 70, height: 12)
        }
        .redacted(reason: .placeholder)
        .skeletonPulse()
    }
}

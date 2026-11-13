import SwiftUI

/// 最近播放: the user's play history from `/user/record`, filterable by window.
struct RecentPlayedView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var player: PlayerManager

    @State private var range: RecentPlayRange = .week
    @State private var records: [PlayRecord] = []
    @State private var isLoading = true
    @State private var error: String?

    private var songs: [Song] { records.map(\.song) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                resultsHeader
                content
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(AppBackground())
        .navigationTitle("最近播放")
        .refreshable { await load() }
        .task(id: range) { await load() }
    }

    private var resultsHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            SectionHeader(
                title: "播放记录",
                subtitle: records.isEmpty ? nil : "\(records.count) 首"
            )

            Picker("时间范围", selection: $range) {
                ForEach(RecentPlayRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading, records.isEmpty {
            skeletonList
        } else if let error, records.isEmpty {
            InfoState(icon: "wifi.exclamationmark", title: "加载失败", message: error,
                      actionTitle: "重试", action: { Task { await load() } })
                .frame(maxWidth: .infinity)
        } else if records.isEmpty {
            InfoState(icon: "clock", title: "暂无播放记录",
                      message: range == .week ? "最近一周还没有播放记录" : "听过的歌曲会出现在这里")
                .frame(maxWidth: .infinity)
        } else {
            songList
        }
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                let isCurrent = player.currentSong?.id == song.id
                SongRow(
                    song: song,
                    isCurrent: isCurrent,
                    onPlay: { player.play(songs, startAt: index) }
                )
                if song.id != songs.last?.id {
                    Divider().padding(.leading, 68)
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

    private func load() async {
        guard let uid = auth.profile?.userId else { return }
        isLoading = true
        error = nil
        do {
            let loaded = try await MusicService.recentPlayed(uid: uid, range: range)
            guard !Task.isCancelled else { return }
            records = loaded
        } catch {
            guard !Task.isCancelled else { return }
            self.error = (error as? APIError)?.errorDescription ?? "加载失败"
        }
        isLoading = false
    }
}

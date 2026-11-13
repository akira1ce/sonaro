import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var fontManager: FontManager
    @StateObject private var viewModel = SearchViewModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .background(AppBackground())
        .navigationTitle("搜索")
        .searchable(text: $viewModel.query, prompt: "歌曲、歌手或专辑")
        .onChange(of: viewModel.query) { _, _ in
            viewModel.scheduleSearch()
        }
        .onSubmit(of: .search) {
            Task { await viewModel.searchNow() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.normalizedQuery.isEmpty {
            InfoState(
                icon: "magnifyingglass",
                title: "搜索音乐",
                message: "查找歌曲、歌手或专辑"
            )
            .padding(.top, 64)
        } else if let error = viewModel.error, viewModel.songs.isEmpty {
            InfoState(
                icon: "wifi.exclamationmark",
                title: "搜索失败",
                message: error,
                actionTitle: "重试",
                action: { Task { await viewModel.retry() } }
            )
            .padding(.top, 48)
        } else if viewModel.hasSearched, viewModel.songs.isEmpty, !viewModel.isLoading {
            InfoState(
                icon: "music.note",
                title: "没有找到相关歌曲",
                message: "试试其他歌曲、歌手或专辑名称"
            )
            .padding(.top, 48)
        } else {
            results
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            resultsHeader

            if viewModel.isLoading, viewModel.songs.isEmpty {
                skeletonList
            } else {
                songList
            }
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.05),
            value: appeared
        )
        .onAppear { appeared = true }
    }

    private var resultsHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            SectionHeader(
                title: "搜索结果",
                subtitle: viewModel.songs.isEmpty ? nil : "找到 \(viewModel.total) 首歌曲"
            )

            Button {
                player.play(viewModel.songs, startAt: 0)
            } label: {
                Label("播放全部", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .disabled(viewModel.songs.isEmpty)
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                SongRowPlaceholder()
                Divider().padding(.leading, 68)
            }
        }
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(viewModel.songs.enumerated()), id: \.element.id) { index, song in
                let isCurrent = player.currentSong?.id == song.id
                SongRow(
                    song: song,
                    isCurrent: isCurrent,
                    onPlay: { player.play(viewModel.songs, startAt: index) }
                )
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(current: song) }
                }

                if song.id != viewModel.songs.last?.id {
                    Divider().padding(.leading, 68)
                }
            }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 52)
            } else if let error = viewModel.error {
                VStack(spacing: 8) {
                    Text(error)
                        .font(fontManager.font(.footnote))
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        Task { await viewModel.retry() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 72)
            }
        }
    }
}

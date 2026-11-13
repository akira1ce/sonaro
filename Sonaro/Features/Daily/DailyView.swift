import SwiftUI

/// 每日推荐: the daily recommended songs, presented with the same header layout
/// as a playlist page.
struct DailyView: View {
    @EnvironmentObject private var player: PlayerManager
    @StateObject private var vm = DailyViewModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 12)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: appeared)

                if let error = vm.error, vm.songs.isEmpty {
                    InfoState(icon: "wifi.exclamationmark", title: "加载失败", message: error,
                              actionTitle: "重试", action: { Task { await vm.reload() } })
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else if vm.isLoading, vm.songs.isEmpty {
                    skeletonList
                } else if vm.songs.isEmpty {
                    InfoState(icon: "music.note", title: "暂无推荐",
                              message: "稍后再来看看，或检查服务器设置")
                        .frame(maxWidth: .infinity)
                } else {
                    songList
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
        .navigationTitle("每日推荐")
        .refreshable { await vm.reload() }
        .task { await vm.loadIfNeeded() }
        .onAppear { appeared = true }
    }

    private var header: some View {
        DetailHeader(
            artworkURL: vm.songs.first?.coverURL(600),
            title: "每日推荐",
            stats: vm.songs.isEmpty ? "" : "\(vm.songs.count) 首",
            description: "根据你的音乐口味生成，每天更新"
        ) {
            Button {
                player.play(vm.songs, startAt: 0)
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.playAction)
            .disabled(vm.songs.isEmpty)
        }
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(vm.songs.enumerated()), id: \.element.id) { index, song in
                let isCurrent = player.currentSong?.id == song.id
                SongRow(
                    song: song,
                    isCurrent: isCurrent,
                    onPlay: { player.play(vm.songs, startAt: index) }
                )
                if song.id != vm.songs.last?.id {
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
}

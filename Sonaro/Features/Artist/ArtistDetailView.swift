import SwiftUI

/// Artist contents: circular portrait + metadata header, then the artist's hot songs.
struct ArtistDetailView: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let artist: Artist

    /// The `/artists` profile, which carries the bio that list cards omit.
    @State private var detail: Artist?
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var appeared = false

    private var info: Artist { detail ?? artist }

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
        .navigationTitle(artist.name)
        .task(id: artist.id) { await load() }
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        DetailHeader(
            artworkURL: info.coverURL(600),
            title: info.name,
            stats: statsText,
            description: info.briefDesc,
            artworkCorner: 92
        ) {
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
        }
    }

    private var statsText: String {
        var parts: [String] = []
        if !info.alias.isEmpty { parts.append(info.alias.joined(separator: " / ")) }
        if info.musicSize > 0 { parts.append("\(info.musicSize) 首歌曲") }
        if info.albumSize > 0 { parts.append("\(info.albumSize) 张专辑") }
        return parts.joined(separator: " · ")
    }

    // MARK: Tracks

    @ViewBuilder
    private var trackList: some View {
        if isLoading, songs.isEmpty {
            skeletonList
        } else if songs.isEmpty {
            InfoState(icon: "music.note", title: "暂无歌曲")
                .frame(maxWidth: .infinity)
        } else {
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
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                SongRowPlaceholder()
                Divider().padding(.leading, 68)
            }
        }
    }

    // MARK: Load

    private func load() async {
        isLoading = true
        error = nil
        do {
            let page = try await MusicService.artistPage(id: artist.id)
            detail = page.artist
            songs = page.songs
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "加载失败"
        }
        isLoading = false
    }
}

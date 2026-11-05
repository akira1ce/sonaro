import SwiftUI

/// A single song line used across Home, playlists and the library — Apple Music style:
/// leading artwork (or an animated equalizer when it's the current track), title/artist,
/// and a trailing accessory. Double-clicking plays; artist names open their page.
struct SongRow: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var likes: LikeManager
    @EnvironmentObject private var fontManager: FontManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let song: Song
    var isCurrent: Bool = false
    var isPlaying: Bool = false
    var showArtwork: Bool = true
    /// Appends the album name to the artist line ("艺人 · 专辑").
    var showsAlbum: Bool = false
    /// Reveals a play button + like heart on hover (Home only).
    var showsHoverActions: Bool = false
    /// Fires on row double-click. When nil the row is a passive label; when set,
    /// the row handles the double-click itself.
    var onPlay: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Group {
            if let onPlay {
                row
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: onPlay)
            } else {
                row
                    .contentShape(Rectangle())
            }
        }
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }
        }
        .padding(.vertical, 4)
    }

    private var row: some View {
        HStack(spacing: 12) {
            if showArtwork {
                Artwork(url: song.coverURL(120), corner: 8)
                    .frame(width: 48, height: 48)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.black.opacity(0.35))
                            NowPlayingBars(animating: isPlaying)
                                .frame(width: 16, height: 14)
                                .foregroundStyle(.white)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(fontManager.font(.body, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Theme.accent : Color.primary)
                    .lineLimit(1)
                subtitle
                    .font(fontManager.font(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            if song.artists.isEmpty {
                Text("未知艺人")
            } else {
                ForEach(Array(song.artists.enumerated()), id: \.offset) { index, artist in
                    if index > 0 { Text("/") }
                    NavigationLink(value: artist) {
                        Text(artist.name)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showsAlbum, !song.albumName.isEmpty {
                Text("· \(song.albumName)")
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if showsHoverActions, isHovering {
            HStack(spacing: 2) {
                playButton
                likeButton
            }
            .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
        } else {
            Text(Format.timeMs(song.durationMs))
                .font(fontManager.font(.footnote))
                .foregroundStyle(.tertiary)
                .transition(.opacity)
        }
    }

    private var playButton: some View {
        Button {
            onPlay?()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(PressableScale())
        .help("播放")
    }

    private var likeButton: some View {
        let liked = likes.isLiked(song.id)
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { likes.toggle(song) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(liked ? Color.red : Color.secondary)
                .symbolEffect(.bounce, value: liked)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PressableScale())
        .help(liked ? "取消喜欢" : "喜欢")
        .disabled(likes.isUpdating(song.id))
    }
}

/// Three little bars that "bounce" to signal the currently playing track.
struct NowPlayingBars: View {
    var animating: Bool
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(0.4)
            bar(1.0)
            bar(0.6)
        }
        .onAppear { phase = animating }
        .onChange(of: animating) { _, newValue in phase = newValue }
    }

    private func bar(_ scale: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .frame(width: 3)
            .scaleEffect(y: phase ? scale : 0.25, anchor: .bottom)
            .animation(
                animating
                    ? .easeInOut(duration: 0.5).repeatForever().delay(Double(scale) * 0.15)
                    : .default,
                value: phase
            )
    }
}

/// Redacted-style song line shown while a track list loads.
struct SongRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.appFill)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appFill)
                    .frame(width: 180, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.appFill)
                    .frame(width: 120, height: 10)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .skeletonPulse()
    }
}

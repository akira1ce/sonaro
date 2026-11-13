import SwiftUI

/// A single song line used across Home, playlists and the library — Apple Music style:
/// leading artwork, title/artist, and a trailing heart + duration. The current
/// track is marked by its accent-coloured title. Double-clicking plays; artist
/// names open their page.
struct SongRow: View {
    @EnvironmentObject private var likes: LikeManager
    @EnvironmentObject private var fontManager: FontManager

    let song: Song
    var isCurrent: Bool = false
    /// Fires on row double-click and on the artwork's play button. When nil the
    /// row is a passive label.
    var onPlay: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            artwork
            titles
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay?() }
        .onHover { isHovering = $0 }
    }

    // MARK: Leading

    private var artwork: some View {
        Artwork(url: song.coverURL(120), corner: 8)
            .frame(width: 48, height: 48)
            .overlay {
                if !isCurrent {
                    playButton
                }
            }
    }

    /// Always mounted so hovering never inserts/removes views or re-lays out the row.
    private var playButton: some View {
        Button { onPlay?() } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.4))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .help("播放")
    }

    // MARK: Text

    private var titles: some View {
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

            if !song.albumName.isEmpty {
                Text("· \(song.albumName)")
            }
        }
    }

    // MARK: Trailing

    private var trailing: some View {
        let liked = likes.isLiked(song.id)
        return HStack(spacing: 6) {
            heartButton(liked: liked)
                .opacity(liked || isHovering ? 1 : 0)
                .allowsHitTesting(liked || isHovering)
            Text(Format.timeMs(song.durationMs))
                .font(fontManager.font(.footnote))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    /// Kept in the layout at all times; only its opacity changes on hover, so a
    /// liked song stays visible and the duration never shifts.
    private func heartButton(liked: Bool) -> some View {
        Button {
            likes.toggle(song)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .skeletonPulse()
    }
}

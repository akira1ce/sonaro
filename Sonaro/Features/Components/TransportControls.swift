import SwiftUI

/// Shared playback controls used by both the mini player and Now Playing.
/// Includes play/pause, previous, next, and like buttons with consistent sizing.
struct TransportControls: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var likes: LikeManager
    @Environment(\.colorScheme) private var colorScheme

    var modeButtonOnLeading: Bool = false

    // Sizing: .compact for mini player, .full for Now Playing
    enum Size {
        case compact
        case full
    }

    var size: Size = .full

    private var iconSize: CGFloat {
        size == .full ? 28 : 17
    }

    private var playIconSize: CGFloat {
        size == .full ? 50 : 21
    }

    private var playFrame: CGFloat {
        size == .full ? 72 : 44
    }

    private var buttonFrame: CGFloat {
        size == .full ? 44 : 32
    }

    private var controlColor: Color {
        if size == .full {
            return colorScheme == .dark ? .white : .black
        } else {
            return .primary
        }
    }

    private var secondaryControlColor: Color {
        if size == .full {
            return controlColor.opacity(0.55)
        } else {
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: size == .full ? 0 : 6) {
            if modeButtonOnLeading {
                modeButton
            }

            if size == .full { Spacer(minLength: 0) }

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize))
                    .frame(width: buttonFrame, height: buttonFrame)
            }
            .buttonStyle(.plain)

            if size == .full { Spacer(minLength: 0) }

            Button { player.togglePlayPause() } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView()
                            .tint(controlColor)
                            .controlSize(size == .full ? .large : .regular)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: playIconSize))
                    }
                }
                .frame(width: playFrame, height: playFrame)
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading)

            if size == .full { Spacer(minLength: 0) }

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: iconSize))
                    .frame(width: buttonFrame, height: buttonFrame)
            }
            .buttonStyle(.plain)
            .disabled(!player.canGoNext)

            if size == .full { Spacer(minLength: 0) }

            likeButton
        }
        .foregroundStyle(controlColor)
        .frame(maxWidth: size == .full ? .infinity : nil)
    }

    // MARK: Mode

    private var modeButton: some View {
        Button { player.cyclePlaybackMode() } label: {
            Image(systemName: player.playbackMode.iconName)
                .font(.system(size: iconSize <= 20 ? 20 : 22))
                .foregroundStyle(player.playbackMode == .sequential
                    ? secondaryControlColor
                    : Theme.accent)
                .frame(width: buttonFrame, height: buttonFrame)
        }
        .buttonStyle(.plain)
    }

    // MARK: Like

    private var likeButton: some View {
        let song = player.currentSong
        let liked = song.map { likes.isLiked($0.id) } ?? false
        let isUpdating = song.map { likes.isUpdating($0.id) } ?? false
        return Button {
            if let song { likes.toggle(song) }
        } label: {
            ZStack {
                if isUpdating {
                    ProgressView().tint(controlColor)
                } else {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: iconSize))
                        .foregroundStyle(liked ? Theme.accent : controlColor.opacity(0.85))
                }
            }
            .frame(width: buttonFrame, height: buttonFrame)
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
    }
}

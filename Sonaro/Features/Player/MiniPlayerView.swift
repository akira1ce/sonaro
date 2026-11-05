import SwiftUI

/// The docked mini player, shown above the window bottom.
/// Tapping anywhere but the controls opens Now Playing.
struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var fontManager: FontManager
    var onTap: () -> Void

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                Artwork(url: song.coverURL(120), corner: 8)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(fontManager.font(.subheadline, weight: .semibold))
                        .lineLimit(1)
                    if let error = player.errorMessage {
                        Text(error)
                            .font(fontManager.font(.caption))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .help(error)
                    } else {
                        Text(song.artistText)
                            .font(fontManager.font(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TransportControls(modeButtonOnLeading: true, size: .compact)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .clipShape(Capsule())
            // Soft drop shadow so the capsule reads as floating above the window.
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

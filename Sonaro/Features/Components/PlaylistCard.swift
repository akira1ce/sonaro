import SwiftUI

/// A square playlist tile with a play-count badge, used in the Home carousel
/// and the Library grid. On Home it also surfaces the personalized `copywriter`
/// recommendation; the play count appears on hover.
struct PlaylistCard: View {
    @EnvironmentObject private var fontManager: FontManager
    
    let playlist: Playlist
    var width: CGFloat = 150
    /// Shows the recommendation / description line (Home's daily shelf).
    var showsSubtitle: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(url: playlist.coverURL(Int(width * 2)), corner: Theme.cardCorner)
                .frame(width: width, height: width)
                .overlay(alignment: .topTrailing) {
                    if isHovering, playlist.playCount > 0 {
                        Label(Format.playCount(playlist.playCount), systemImage: "play.fill")
                            .font(fontManager.customFont(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(6)
                            .transition(.opacity)
                    }
                }
                .scaleEffect(isHovering && !reduceMotion ? 1.02 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.18),
                    value: isHovering
                )

            Text(playlist.name)
                .font(fontManager.font(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: showsSubtitle)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)

            if showsSubtitle, let subtitle = playlist.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(fontManager.font(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
            }
        }
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
            }
        }
    }
}

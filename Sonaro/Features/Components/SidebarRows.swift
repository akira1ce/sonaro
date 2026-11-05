import SwiftUI

/// A sidebar row with a tinted SF Symbol, used by the 我的 shortcuts.
struct SidebarMenuItem: View {
    let title: String
    let icon: String
    /// The accent highlight would swallow the red icon, so switch to white.
    var isSelected: Bool = false
    var tint: Color = Theme.playAction

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .white : tint)
        }
    }
}

/// A compact sidebar row for a favorited playlist: small cover + one-line name.
struct SidebarPlaylistRow: View {
    @EnvironmentObject private var fontManager: FontManager

    let playlist: Playlist

    var body: some View {
        HStack(spacing: 8) {
            Artwork(url: playlist.coverURL(48), corner: 4)
                .frame(width: 22, height: 22)

            Text(playlist.name)
                .font(fontManager.font(.body))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

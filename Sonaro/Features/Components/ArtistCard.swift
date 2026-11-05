import SwiftUI

/// A circular artist portrait with the name underneath.
struct ArtistCard: View {
    @EnvironmentObject private var fontManager: FontManager

    let artist: Artist
    var width: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            Avatar(url: artist.coverURL(Int(width * 2)), size: width)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

            Text(artist.name)
                .font(fontManager.font(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: width)
        }
    }
}

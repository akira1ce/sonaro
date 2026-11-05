import SwiftUI

/// Square album/playlist artwork with a graceful placeholder and rounded corners.
struct Artwork: View {
    let url: URL?
    var corner: CGFloat = Theme.tileCorner

    var body: some View {
        Rectangle()
            .fill(Color.appFill)
            .overlay {
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Circular avatar.
struct Avatar: View {
    let url: URL?
    var size: CGFloat = 40

    var body: some View {
        CachedImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

import SwiftUI

/// Drop-in replacement for `AsyncImage` backed by `ImageLoader` (disk cache,
/// cross-UI dedup). Mirrors `AsyncImage`'s content/placeholder closures:
/// `content` renders the loaded image, `placeholder` shows until it arrives or
/// if loading fails. Reloads when `url` changes and clears the stale image so
/// reused cells never flash the previous cover.
struct CachedImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var image: PlatformImage?

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(platformImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await ImageLoader.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

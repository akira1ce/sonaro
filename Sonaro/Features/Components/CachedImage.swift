import SwiftUI

/// Drop-in replacement for `AsyncImage` backed by `ImageLoader` (decoded memory
/// cache + disk cache, cross-UI dedup). Mirrors `AsyncImage`'s content/placeholder
/// closures: `content` renders the loaded image, `placeholder` shows until it
/// arrives or if loading fails. Seeds from the memory cache so a row rebuilt
/// while scrolling paints its cover immediately instead of flashing the
/// placeholder.
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
        _image = State(initialValue: url.flatMap(ImageLoader.cached))
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
            guard let url else {
                image = nil
                return
            }
            if let cached = ImageLoader.cached(url) {
                image = cached
                return
            }
            image = nil
            let loaded = await ImageLoader.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

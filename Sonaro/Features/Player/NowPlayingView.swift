import SwiftUI

/// Full-screen Now Playing, styled after Apple Music.
/// Mac: side-by-side — cover + controls on the left, lyrics on the right.
/// Narrow / short windows drop the cover and give the space to lyrics + controls.
struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var fontManager: FontManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isCompact = false

    /// When set (macOS embedded-in-window mode), dismissal calls this instead of
    /// the environment `dismiss` (which only works for sheets / full-screen covers).
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                if let song = player.currentSong {
                    pager(song)
                } else {
                    Spacer()
                    InfoState(icon: "music.note", title: "暂无正在播放")
                        .foregroundStyle(textColor)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { updateLayout(for: $0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { collapseButton }
    }

    /// The side-by-side split needs roughly 760pt of width and 560pt of height
    /// before the cover column and lyrics both become cramped. The wider exit
    /// thresholds add hysteresis so dragging across the breakpoint doesn't flicker.
    private func updateLayout(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if size.width < 760 || size.height < 560 {
            isCompact = true
        } else if size.width > 800, size.height > 600 {
            isCompact = false
        }
    }

    // MARK: Collapse

    /// The visible way out, top-left. It also carries the Esc shortcut: a
    /// `.cancelAction` keyboardShortcut is window-scoped, so it fires no matter
    /// what holds focus, whereas `onKeyPress` would only see the key while this
    /// view itself is focused (focus usually sits in the sidebar list).
    @ViewBuilder
    private var collapseButton: some View {
        if onClose != nil {
            Button { performDismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundStyle(controlColor.opacity(0.85))
                    .padding(10)
                    .background(controlColor.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("收起")
            .padding(.leading, 20)
            .padding(.top, 16)
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        backdropColor
            .ignoresSafeArea()
    }

    private var backdropColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var controlColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var header: some View {
        Text("正在播放")
            .font(fontManager.font(.subheadline, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
    }

    // MARK: Layouts

    @ViewBuilder
    private func pager(_ song: Song) -> some View {
        if isCompact {
            compactLayout(song)
        } else {
            wideLayout(song)
        }
    }

    // MARK: Compact layout (narrow / short windows) — lyrics + controls, no cover

    private func compactLayout(_ song: Song) -> some View {
        VStack(spacing: 0) {
            trackInfo(song)
                .padding(.horizontal, 40)
                .padding(.top, 12)

            lyricsPage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            scrubber
                .padding(.horizontal, 40)
                .padding(.top, 8)

            controls
                .padding(.horizontal, 40)
                .padding(.top, 12)
                .padding(.bottom, 28)
        }
    }

    // MARK: Wide layout (iPad / Mac) — cover + controls left, lyrics right

    private func wideLayout(_ song: Song) -> some View {
        HStack(spacing: 48) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Artwork(url: song.coverURL(600), corner: 18)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 420)   // fills the column, capped so full-screen isn't huge
                    .scaleEffect(player.isPlaying ? 1.0 : 0.84)
                    .shadow(color: Color.primary.opacity(0.3), radius: 24, y: 12)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)

                Spacer(minLength: 24)

                trackInfo(song)
                    .padding(.bottom, 14)

                scrubber
                    .padding(.bottom, 18)

                controls

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            lyricsPage
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 34)
    }

    private func trackInfo(_ song: Song) -> some View {
        VStack(spacing: 4) {
            Text(song.name)
                .font(fontManager.customFont(size: 22, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Text(song.artistText)
                .font(fontManager.font(.headline))
                .foregroundStyle(textColor.opacity(0.7))
                .lineLimit(1)
            if let error = player.errorMessage {
                Text(error)
                    .font(fontManager.font(.caption))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Transport controls — mode · previous · play/pause · next · like

    private var controls: some View {
        TransportControls(modeButtonOnLeading: true, size: .full)
            .foregroundStyle(controlColor)
    }

    // MARK: Lyrics page

    private var lyricsPage: some View {
        LyricsPage(textColor: textColor, fadeColor: backdropColor)
    }

    // MARK: Scrubber

    private var scrubber: some View {
        PlaybackScrubber(textColor: textColor, controlColor: controlColor)
    }

    // MARK: Dismiss

    /// Embedded (macOS in-window) mode routes through `onClose`; sheet / cover
    /// mode falls back to the environment `dismiss`.
    private func performDismiss() {
        if let onClose { onClose() } else { dismiss() }
    }
}

private struct PlaybackScrubber: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var playbackProgress: PlaybackProgress
    @EnvironmentObject private var fontManager: FontManager
    @State private var sliderValue: Double = 0
    @State private var isScrubbing = false
    
    let textColor: Color
    let controlColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $sliderValue, in: 0...max(playbackProgress.duration, 1)) { editing in
                isScrubbing = editing
                if !editing { player.seek(to: sliderValue) }
            }
            .tint(Theme.accent)

            HStack {
                Text(Format.time(sliderValue))
                Spacer()
                Text("-" + Format.time(max(0, playbackProgress.duration - sliderValue)))
            }
            .font(fontManager.customFont(size: 11))
            .foregroundStyle(textColor.opacity(0.6))
        }
        .onAppear { sliderValue = playbackProgress.currentTime }
        .onChange(of: playbackProgress.currentTime) { _, newValue in
            if !isScrubbing { sliderValue = newValue }
        }
    }
}

private struct LyricsPage: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var lyricPlayback: LyricPlaybackState
    @EnvironmentObject private var fontManager: FontManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    let textColor: Color
    /// The window backdrop, used to fade lyrics out at the scroll edges.
    let fadeColor: Color

    /// True while the user is scrolling the lyrics themselves. Auto-follow is
    /// suspended (and re-armed shortly after they stop) so a line change never
    /// yanks the view away mid-read.
    @State private var isUserBrowsing = false
    @State private var returnTask: Task<Void, Never>?
    /// Bumped when auto-follow needs to re-center on the current line.
    @State private var scrollRequestID = 0
    /// The first re-center after the page opens jumps straight to the playing
    /// line instead of animating down from the top.
    @State private var didInitialScroll = false

    private static let browseReturnDelay: Duration = .seconds(2.5)

    var body: some View {
        GeometryReader { geo in
            // Scale the lyric type with the available width so Mac/iPad windows
            // don't render iPhone-sized text; clamped to a sane range.
            let fontSize = min(max(geo.size.width * 0.062, 20), 34)
            Group {
                if player.lyrics.isEmpty {
                    VStack {
                        Spacer()
                        InfoState(icon: "text.quote", title: "暂无歌词").foregroundStyle(textColor)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            // Lyrics are bounded (a few hundred lines at most), so a
                            // plain VStack beats LazyVStack: nothing gets created
                            // mid-animation while the view scrolls.
                            VStack(alignment: .leading, spacing: fontSize * 1.1) {
                                ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { index, line in
                                    let isCurrent = index == lyricPlayback.currentIndex
                                    
                                    Text(line.text)
                                        .font(fontManager.customFont(size: fontSize * fontManager.size.scale, weight: .semibold))
                                        .foregroundStyle(textColor)
                                        .opacity(isCurrent ? 1.0 : 0.45)
                                        .animation(
                                            reduceMotion ? nil : .easeInOut(duration: 0.3),
                                            value: isCurrent
                                        )
                                        .scaleEffect(isCurrent ? 1.01 : 0.99, anchor: .leading)
                                        .animation(
                                            reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78),
                                            value: isCurrent
                                        )
                                        .id(index)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onTapGesture {
                                            isUserBrowsing = false
                                            player.seek(to: line.time)
                                        }
                                }
                            }
                            .padding(.vertical, 60)
                            .padding(.horizontal, 32)
                        }
                        .onScrollPhaseChange { _, newPhase in
                            handleScrollPhase(newPhase)
                        }
                        .onChange(of: lyricPlayback.currentIndex, initial: true) { _, newValue in
                            guard !isUserBrowsing, newValue != nil else { return }
                            scrollToCurrentLine(using: proxy, animated: didInitialScroll)
                            didInitialScroll = true
                        }
                        .onChange(of: scrollRequestID) { _, _ in
                            scrollToCurrentLine(using: proxy)
                        }
                        .onChange(of: player.lyrics) { _, _ in
                            isUserBrowsing = false
                            returnTask?.cancel()
                        }
                    }
                    .overlay(alignment: .top) {
                        edgeFade(.top, height: min(max(geo.size.height * 0.08, 40), 72))
                    }
                    .overlay(alignment: .bottom) {
                        edgeFade(.bottom, height: min(max(geo.size.height * 0.08, 40), 72))
                    }
                    .padding(.bottom, 34)
                }
            }
        }
        .onDisappear { returnTask?.cancel() }
    }

    private func handleScrollPhase(_ phase: ScrollPhase) {
        switch phase {
        case .tracking, .interacting, .decelerating:
            isUserBrowsing = true
            returnTask?.cancel()
        case .idle:
            scheduleReturnToCurrentLine()
        case .animating:
            break
        }
    }

    /// Once the user stops scrolling, snap back to the playing line after a
    /// short pause so they can read where they stopped.
    private func scheduleReturnToCurrentLine() {
        guard isUserBrowsing else { return }
        returnTask?.cancel()
        returnTask = Task { @MainActor in
            try? await Task.sleep(for: Self.browseReturnDelay)
            guard !Task.isCancelled else { return }
            isUserBrowsing = false
            if player.isPlaying { scrollRequestID &+= 1 }
        }
    }

    private func scrollToCurrentLine(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard let index = lyricPlayback.currentIndex else { return }
        if reduceMotion || !animated {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }
    /// Fades lyrics into the backdrop at the top/bottom scroll edges.
    private func edgeFade(_ edge: VerticalEdge, height: CGFloat) -> some View {
        LinearGradient(
            colors: [fadeColor, fadeColor.opacity(0)],
            startPoint: edge == .top ? .top : .bottom,
            endPoint: edge == .top ? .bottom : .top
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

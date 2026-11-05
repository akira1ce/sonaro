import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

/// High-frequency progress is isolated so list screens observing PlayerManager
/// are not invalidated four times per second during playback.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    var fraction: Double {
        duration > 0 ? min(1, currentTime / duration) : 0
    }

    func setCurrentTime(_ value: Double) { currentTime = value }
    func setDuration(_ value: Double) { duration = value }
}

@MainActor
final class LyricPlaybackState: ObservableObject {
    @Published private(set) var currentIndex: Int?

    func setCurrentIndex(_ value: Int?) { currentIndex = value }
}

// MARK: - PlayerManager

/// Central audio engine: holds the queue, drives an `AVPlayer`, mirrors playback
/// to the system Now Playing / lock screen, and keeps lyrics in sync.
@MainActor
final class PlayerManager: ObservableObject {

    typealias SongURLLoader = @Sendable (_ id: Int, _ level: String) async throws -> URL

    // Queue
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int = 0

    // Playback order — how the queue advances (cycled by the Now Playing button).
    @Published var playbackMode: PlaybackMode = .sequential

    // Playback
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // Lyrics (published so views observing PlayerManager can react to new tracks)
    @Published private(set) var lyrics: [LyricLine] = []

    // Volume (app-level)
    @Published var volume: Double = 1.0 {
        didSet { player.volume = Float(volume) }
    }

    /// High-frequency progress is isolated so list screens observing PlayerManager
    /// are not invalidated four times per second during playback.
    let playbackProgress = PlaybackProgress()
    let lyricPlayback = LyricPlaybackState()

    var currentTime: Double { playbackProgress.currentTime }
    var duration: Double { playbackProgress.duration }

    var currentSong: Song? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }
    var hasNext: Bool { currentIndex < queue.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 }
    /// Whether the next-track control should be enabled. Loop / shuffle always
    /// have a next track (they wrap / randomize); sequential & repeat-one don't.
    var canGoNext: Bool {
        switch playbackMode {
        case .loop, .shuffle: return !queue.isEmpty
        case .sequential, .repeatOne: return hasNext
        }
    }
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var artwork: MPMediaItemArtwork?
    private var loadToken = UUID()
    private var loadTask: Task<Void, Never>?
    private var pendingSeekToken: UUID?
    private var shuffleHistory: [Int] = []
    private let songURLLoader: SongURLLoader
    private let nowPlaying: NowPlayingController
    private var lyricSync = LyricSynchronizer()

    private var preferredLevel: String {
        UserDefaults.standard.string(forKey: "player.quality") ?? "standard"
    }

    init(songURLLoader: @escaping SongURLLoader = { id, level in
        try await MusicService.songURL(id: id, level: level)
    }) {
        self.songURLLoader = songURLLoader
        self.nowPlaying = NowPlayingController()
        wireNowPlayingCallbacks()
        addPeriodicObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                // A replaced item can still deliver its end notification late;
                // only the item still in the player may advance the queue.
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.handleTrackEnd()
            }
        }
    }

    private func wireNowPlayingCallbacks() {
        nowPlaying.onPlay = { [weak self] in self?.resumeFromRemote() }
        nowPlaying.onPause = { [weak self] in self?.pauseFromRemote() }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.next() }
        nowPlaying.onPrevious = { [weak self] in self?.previous() }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
    }

    // MARK: - Public controls

    func play(_ songs: [Song], startAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = max(0, min(index, songs.count - 1))
        shuffleHistory.removeAll()
        startCurrentLoad(autoPlay: true)
    }

    /// Plays a single song, replacing the queue.
    func play(_ song: Song) { play([song], startAt: 0) }

    func togglePlayPause() {
        guard !isLoading else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            refreshNowPlaying()
        } else if player.currentItem == nil || player.currentItem?.status == .failed {
            startCurrentLoad(autoPlay: true)
        } else {
            resume()
        }
    }

    /// Resumes playback. When the queue has played through in a non-looping mode
    /// the final item is left parked at its end, where a bare `play()` won't
    /// restart it — rewind to the top first so the play button always works.
    func resume() {
        if Self.shouldRestartFromEnd(currentTime: currentTime, duration: duration) {
            seek(to: 0)
        }
        player.play()
        isPlaying = true
        refreshNowPlaying()
    }

    /// Whether a resume should rewind to the start first: true when the current
    /// item is parked at (or past) its end. Pure (`nonisolated`) so it's
    /// unit-testable without an `AVPlayer` or the main actor.
    nonisolated static func shouldRestartFromEnd(currentTime: Double, duration: Double) -> Bool {
        duration > 0 && currentTime >= duration - 0.5
    }

    /// User-initiated skip forward. Shuffle jumps randomly, loop wraps, and
    /// sequential / repeat-one advance and stop at the end of the queue (manual
    /// skip in repeat-one still moves on, mirroring Apple Music).
    func next() {
        switch playbackMode {
        case .shuffle: advanceShuffle()
        case .loop: advanceToNext(wrap: true)
        case .sequential, .repeatOne: advanceToNext(wrap: false)
        }
    }

    func previous() {
        // Mirror Apple Music: restart the track if we're past 3s.
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        switch playbackMode {
        case .shuffle:
            if let prev = shuffleHistory.popLast() {
                currentIndex = prev
                startCurrentLoad(autoPlay: true)
            } else {
                seek(to: 0)
            }
        case .loop:
            currentIndex = hasPrevious ? currentIndex - 1 : queue.count - 1
            startCurrentLoad(autoPlay: true)
        case .sequential, .repeatOne:
            if hasPrevious {
                currentIndex -= 1
                startCurrentLoad(autoPlay: true)
            } else {
                seek(to: 0)
            }
        }
    }

    /// Cycles the playback mode: 顺序 → 单曲循环 → 随机 → 列表循环 → 顺序.
    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
        if playbackMode != .shuffle { shuffleHistory.removeAll() }
    }

    // MARK: - Advancing

    /// Auto-advance when a track finishes on its own — respects the mode
    /// (repeat-one replays; sequential stops at the end of the queue).
    private func handleTrackEnd() {
        guard !isLoading else { return }
        switch playbackMode {
        case .repeatOne:
            seek(to: 0)
            player.play()
            isPlaying = true
            refreshNowPlaying()
        case .shuffle:
            advanceShuffle()
        case .loop:
            advanceToNext(wrap: true)
        case .sequential:
            advanceToNext(wrap: false)
        }
    }

    /// Moves to the next queue index. `wrap` returns to the start at the end;
    /// otherwise playback stops at the end of the queue.
    private func advanceToNext(wrap: Bool) {
        guard !queue.isEmpty else { return }
        if hasNext {
            currentIndex += 1
        } else if wrap {
            currentIndex = 0
        } else {
            player.pause()
            isPlaying = false
            refreshNowPlaying()
            return
        }
        startCurrentLoad(autoPlay: true)
    }

    /// Jumps to a random track (≠ current), remembering where we came from so
    /// `previous()` can retrace the shuffle path.
    private func advanceShuffle() {
        guard !queue.isEmpty else { return }
        guard queue.count > 1 else {
            seek(to: 0)
            player.play()
            isPlaying = true
            refreshNowPlaying()
            return
        }
        shuffleHistory.append(currentIndex)
        var idx = currentIndex
        while idx == currentIndex { idx = Int.random(in: 0..<queue.count) }
        currentIndex = idx
        startCurrentLoad(autoPlay: true)
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        let token = UUID()
        pendingSeekToken = token
        playbackProgress.setCurrentTime(clamped)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.pendingSeekToken == token else { return }
                self.pendingSeekToken = nil
                guard finished else { return }
                self.playbackProgress.setCurrentTime(clamped)
                self.updateCurrentLyric()
            }
        }
        refreshNowPlaying()
    }

    /// A periodic callback can still carry the old player time while a new item
    /// is loading or an asynchronous seek is settling.
    nonisolated static func shouldPublishPeriodicProgress(
        isLoading: Bool,
        hasPendingSeek: Bool
    ) -> Bool {
        !isLoading && !hasPendingSeek
    }

    // MARK: - Loading

    /// Cancels the previous URL request and captures this selection synchronously.
    /// Every async continuation also checks `token`, so only the latest selection
    /// can replace the player item or publish an error.
    private func startCurrentLoad(autoPlay: Bool) {
        guard let song = currentSong else { return }
        loadTask?.cancel()
        statusObservation?.invalidate()

        let token = UUID()
        loadToken = token
        pendingSeekToken = nil
        isLoading = true
        errorMessage = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        playbackProgress.setCurrentTime(0)
        playbackProgress.setDuration(Double(song.durationMs) / 1000)
        lyrics = []
        lyricSync.lyrics = []
        lyricPlayback.setCurrentIndex(nil)
        artwork = nil
        refreshNowPlaying()

        let level = preferredLevel
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(song: song, level: level, token: token, autoPlay: autoPlay)
        }
    }

    private func load(song: Song, level: String, token: UUID, autoPlay: Bool) async {
        do {
            let url = try await songURLLoader(song.id, level)
            guard !Task.isCancelled, loadToken == token else { return }
            let item = AVPlayerItem(url: url)
            observe(item, token: token, autoPlay: autoPlay)
            player.replaceCurrentItem(with: item)
            player.volume = Float(volume)
            if autoPlay {
                player.play()
                isPlaying = true
            }
            refreshNowPlaying()
        } catch {
            guard loadToken == token else { return }
            isLoading = false
            errorMessage = (error as? APIError)?.errorDescription ?? "播放失败"
            isPlaying = false
            return
        }

        // Fetch lyrics + artwork without blocking playback.
        Task { await loadLyrics(for: song, token: token) }
        Task { await loadArtwork(for: song, token: token) }
    }

    private func observe(_ item: AVPlayerItem, token: UUID, autoPlay: Bool) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, self.loadToken == token else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.playbackProgress.setDuration(d) }
                    self.refreshNowPlaying()
                    // AVPlayer can drop a play() issued before the item was ready.
                    if autoPlay, self.isPlaying, item === self.player.currentItem {
                        self.player.play()
                        self.verifyPlaybackStarted(token: token)
                    }
                case .failed:
                    self.isLoading = false
                    self.errorMessage = "无法加载音频"
                    self.isPlaying = false
                default:
                    break
                }
            }
        }
    }

    /// One delayed check that recovers a silently dropped `play()`. Genuine
    /// buffering reports `.waitingToPlayAtSpecifiedRate`, not `.paused`.
    private func verifyPlaybackStarted(token: UUID) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.loadToken == token, self.isPlaying,
                  self.player.timeControlStatus == .paused else { return }
            self.player.play()
        }
    }

    private func loadLyrics(for song: Song, token: UUID) async {
        let lines = (try? await MusicService.lyrics(id: song.id)) ?? []
        guard loadToken == token else { return }
        lyrics = lines
        lyricSync.lyrics = lines
    }

    private func loadArtwork(for song: Song, token: UUID) async {
        guard let url = song.coverURL(600) else { return }
        guard let image = await ImageLoader.shared.image(for: url) else { return }
        guard loadToken == token else { return }
        let size = image.size
        artwork = MPMediaItemArtwork(boundsSize: size) { _ in image }
        refreshNowPlaying()
    }

    // MARK: - Time & lyric sync

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard Self.shouldPublishPeriodicProgress(
                    isLoading: self.isLoading,
                    hasPendingSeek: self.pendingSeekToken != nil
                ) else { return }
                let t = time.seconds
                if t.isFinite { self.playbackProgress.setCurrentTime(t) }
                self.updateCurrentLyric()
            }
        }
    }

    private func updateCurrentLyric() {
        let index = lyricSync.currentIndex(for: currentTime)
        if lyricPlayback.currentIndex != index {
            lyricPlayback.setCurrentIndex(index)
        }
    }

    // MARK: - System integration (delegates to NowPlayingController)

    func resumeFromRemote() {
        guard !isPlaying else { return }
        resume()
    }

    func pauseFromRemote() {
        guard isPlaying else { return }
        player.pause(); isPlaying = false; refreshNowPlaying()
    }

    private func refreshNowPlaying() {
        nowPlaying.refresh(
            song: currentSong,
            isPlaying: isPlaying,
            duration: duration,
            currentTime: currentTime,
            artwork: artwork
        )
    }

    deinit {
        loadTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    #if DEBUG
    /// Seeds a fake now-playing state for UI screenshots (no network / AVPlayer).
    func seedDemo() {
        loadTask?.cancel()
        loadToken = UUID()
        isLoading = false
        let demo = Song(
            id: -1,
            name: "Bittersweet (feat. Luke Chiang)",
            artists: [Artist(id: 1, name: "Sarah Kang"), Artist(id: 2, name: "Luke Chiang")],
            album: Album(id: 1, name: "Bittersweet", picUrl: "https://picsum.photos/id/1062/600"),
            durationMs: 200_000)
        queue = [demo]
        currentIndex = 0
        playbackProgress.setDuration(200)
        playbackProgress.setCurrentTime(74)
        isPlaying = true
        lyrics = [
            LyricLine(time: 0, text: "The city lights are bittersweet tonight"),
            LyricLine(time: 8, text: "I keep replaying everything we said"),
            LyricLine(time: 16, text: "Don't make me fall in love again"),
            LyricLine(time: 24, text: "Every heartbeat sounds just like your name"),
            LyricLine(time: 32, text: "I'll hold this moment while it lasts"),
            LyricLine(time: 40, text: "And let the melody carry me home"),
        ]
        lyricSync.lyrics = lyrics
        lyricPlayback.setCurrentIndex(2)
    }
    #endif
}

// MARK: - Playback mode

/// Queue playback order, cycled by the Now Playing mode button.
enum PlaybackMode: CaseIterable {
    case sequential   // 顺序播放 — play through, stop at the end
    case repeatOne    // 单曲循环 — replay the current track
    case shuffle      // 随机播放
    case loop         // 列表循环 — wrap to the start at the end

    /// SF Symbol shown on the mode button.
    var iconName: String {
        switch self {
        case .sequential: return "list.bullet"
        case .repeatOne:  return "repeat.1"
        case .shuffle:    return "shuffle"
        case .loop:       return "repeat"
        }
    }

    /// The next mode in the cycle.
    var next: PlaybackMode {
        switch self {
        case .sequential: return .repeatOne
        case .repeatOne:  return .shuffle
        case .shuffle:    return .loop
        case .loop:       return .sequential
        }
    }
}

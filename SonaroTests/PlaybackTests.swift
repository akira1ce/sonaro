import XCTest
@testable import Sonaro

/// Playback-mode cycling and the end-of-queue resume decision — the pure logic
/// behind the transport controls.
final class PlaybackTests: XCTestCase {

    private actor CallCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    private actor FirstLoadGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var started = false

        func wait() async {
            started = true
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func song(_ id: Int) -> Song {
        Song(id: id, name: "Song \(id)", artists: [], album: nil, durationMs: 1_000)
    }

    // MARK: PlaybackMode.next

    func testModeCyclesInOrderAndWraps() {
        XCTAssertEqual(PlaybackMode.sequential.next, .repeatOne)
        XCTAssertEqual(PlaybackMode.repeatOne.next, .shuffle)
        XCTAssertEqual(PlaybackMode.shuffle.next, .loop)
        XCTAssertEqual(PlaybackMode.loop.next, .sequential)
    }

    func testFourNextsReturnToStart() {
        var mode = PlaybackMode.sequential
        for _ in 0..<PlaybackMode.allCases.count { mode = mode.next }
        XCTAssertEqual(mode, .sequential)
    }

    func testEveryModeHasAnIcon() {
        for mode in PlaybackMode.allCases {
            XCTAssertFalse(mode.iconName.isEmpty)
        }
    }

    // MARK: shouldRestartFromEnd — the fix for the dead play button at queue end

    func testResumeRestartsWhenParkedAtEnd() {
        // Track played through: currentTime sits at (or just under) duration.
        XCTAssertTrue(PlayerManager.shouldRestartFromEnd(currentTime: 200, duration: 200))
        XCTAssertTrue(PlayerManager.shouldRestartFromEnd(currentTime: 199.6, duration: 200))
        XCTAssertTrue(PlayerManager.shouldRestartFromEnd(currentTime: 201, duration: 200))
    }

    func testResumeDoesNotRestartMidTrack() {
        XCTAssertFalse(PlayerManager.shouldRestartFromEnd(currentTime: 0, duration: 200))
        XCTAssertFalse(PlayerManager.shouldRestartFromEnd(currentTime: 100, duration: 200))
        XCTAssertFalse(PlayerManager.shouldRestartFromEnd(currentTime: 199, duration: 200))
    }

    func testResumeIgnoresUnknownDuration() {
        // Before an item is ready its duration is 0 — never treat that as "ended".
        XCTAssertFalse(PlayerManager.shouldRestartFromEnd(currentTime: 0, duration: 0))
        XCTAssertFalse(PlayerManager.shouldRestartFromEnd(currentTime: 5, duration: 0))
    }

    // MARK: Periodic progress gating

    func testPeriodicProgressPublishesDuringStablePlayback() {
        XCTAssertTrue(PlayerManager.shouldPublishPeriodicProgress(
            isLoading: false,
            hasPendingSeek: false
        ))
    }

    func testPeriodicProgressIsSuppressedDuringTrackLoadAndSeek() {
        XCTAssertFalse(PlayerManager.shouldPublishPeriodicProgress(
            isLoading: true,
            hasPendingSeek: false
        ))
        XCTAssertFalse(PlayerManager.shouldPublishPeriodicProgress(
            isLoading: false,
            hasPendingSeek: true
        ))
    }

    @MainActor
    func testStartingTrackLoadStopsCurrentPlaybackImmediately() async {
        let loadGate = FirstLoadGate()
        let player = PlayerManager { _, _ in
            await loadGate.wait()
            throw APIError.http(503, message: nil)
        }

        player.seedDemo()
        XCTAssertTrue(player.isPlaying)

        player.play([song(1), song(2)], startAt: 0)

        XCTAssertTrue(player.isLoading)
        XCTAssertFalse(player.isPlaying)

        while !(await loadGate.started) { await Task.yield() }
        await loadGate.release()
    }

    // MARK: Latest track load wins

    @MainActor
    func testNextTrackCancelsPreviousLoadAndIgnoresItsLateFailure() async {
        let firstLoad = FirstLoadGate()
        let player = PlayerManager { id, _ in
            if id == 1 {
                await firstLoad.wait()
                throw APIError.http(401, message: nil)
            }
            throw APIError.http(503, message: nil)
        }
        let songs = [song(1), song(2)]

        player.play(songs, startAt: 0)
        XCTAssertTrue(player.isLoading)

        while !(await firstLoad.started) { await Task.yield() }
        player.playbackProgress.setCurrentTime(0.75)
        player.next()
        XCTAssertEqual(player.currentSong?.id, 2)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 1)

        while player.isLoading { await Task.yield() }
        XCTAssertEqual(player.errorMessage, "服务器返回错误（HTTP 503）")

        await firstLoad.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(player.currentSong?.id, 2)
        XCTAssertEqual(player.errorMessage, "服务器返回错误（HTTP 503）")
    }

    @MainActor
    func testLikeUpdateBlocksRepeatedToggleUntilRequestCompletes() async {
        let calls = CallCounter()
        let likes = LikeManager { _, _ in
            await calls.increment()
            await Task.yield()
            return true
        }
        let target = song(1)

        likes.toggle(target)
        likes.toggle(target)
        XCTAssertTrue(likes.isLiked(target.id))
        XCTAssertTrue(likes.isUpdating(target.id))

        while likes.isUpdating(target.id) { await Task.yield() }
        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(likes.isLiked(target.id))
    }

    @MainActor
    func testClearingLikesIgnoresAnEarlierRequestsLateFailure() async {
        let request = FirstLoadGate()
        let likes = LikeManager { _, _ in
            await request.wait()
            return false
        }
        let target = song(1)

        likes.toggle(target)
        while !(await request.started) { await Task.yield() }
        likes.clear()

        await request.release()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(likes.likedIDs.isEmpty)
        XCTAssertFalse(likes.isUpdating(target.id))
    }

    // MARK: Retry after a failed load

    @MainActor
    func testPlayButtonRetriesAfterFailedURLLoad() async {
        let calls = CallCounter()
        let player = PlayerManager { _, _ in
            await calls.increment()
            throw APIError.noPlayableURL
        }

        player.play([song(1)], startAt: 0)
        while player.isLoading { await Task.yield() }
        let firstAttempts = await calls.value
        XCTAssertEqual(firstAttempts, 1)
        XCTAssertEqual(player.errorMessage, APIError.noPlayableURL.errorDescription)
        XCTAssertFalse(player.isPlaying)

        // The queue entry is selected but has no player item — the play button
        // must retry the load instead of trying to resume a missing item.
        player.togglePlayPause()
        while player.isLoading { await Task.yield() }
        let secondAttempts = await calls.value
        XCTAssertEqual(secondAttempts, 2)
    }
}

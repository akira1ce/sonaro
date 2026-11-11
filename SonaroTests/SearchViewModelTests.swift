import XCTest
@testable import Sonaro

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testSearchNowTrimsKeywordAndPublishesResults() async {
        var receivedKeyword: String?
        let expected = song(id: 1, name: "晴天")
        let viewModel = SearchViewModel { keyword, _, _ in
            receivedKeyword = keyword
            return SongSearchPage(songs: [expected], total: 12)
        }
        viewModel.query = "  周杰伦\n"

        await viewModel.searchNow()

        XCTAssertEqual(receivedKeyword, "周杰伦")
        XCTAssertEqual(viewModel.songs, [expected])
        XCTAssertEqual(viewModel.total, 12)
        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testEmptyQueryDoesNotCallSearch() async {
        var callCount = 0
        let viewModel = SearchViewModel { _, _, _ in
            callCount += 1
            return SongSearchPage(songs: [], total: 0)
        }
        viewModel.query = " \n "

        await viewModel.searchNow()

        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(viewModel.songs.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testPaginationAppendsUniqueSongsAndStopsAtTotal() async {
        let first = song(id: 1, name: "第一首")
        let second = song(id: 2, name: "第二首")
        let third = song(id: 3, name: "第三首")
        var receivedOffsets: [Int] = []
        let viewModel = SearchViewModel(pageSize: 2) { _, _, offset in
            receivedOffsets.append(offset)
            if offset == 0 {
                return SongSearchPage(songs: [first, second], total: 3)
            }
            return SongSearchPage(songs: [second, third], total: 3)
        }
        viewModel.query = "测试"

        await viewModel.searchNow()
        await viewModel.loadMoreIfNeeded(current: second)

        XCTAssertEqual(receivedOffsets, [0, 2])
        XCTAssertEqual(viewModel.songs, [first, second, third])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testRapidTypingSearchesOnlyTheLatestKeyword() async {
        let searched = expectation(description: "Latest keyword searched")
        var keywords: [String] = []
        let viewModel = SearchViewModel(debounceDuration: .milliseconds(20)) { keyword, _, _ in
            keywords.append(keyword)
            searched.fulfill()
            return SongSearchPage(songs: [], total: 0)
        }

        for keyword in ["周", "周杰", "周杰伦"] {
            viewModel.query = keyword
            viewModel.scheduleSearch()
        }
        XCTAssertTrue(keywords.isEmpty)

        await fulfillment(of: [searched], timeout: 1)
        XCTAssertEqual(keywords, ["周杰伦"])
    }

    func testConcurrentPaginationDoesNotRequestTheSamePageTwice() async {
        let started = expectation(description: "Next page started")
        var response: CheckedContinuation<SongSearchPage, Never>?
        var offsets: [Int] = []
        let firstPage = [song(id: 1, name: "第一首"), song(id: 2, name: "第二首")]
        let nextPage = [song(id: 3, name: "第三首"), song(id: 4, name: "第四首")]
        let viewModel = SearchViewModel(pageSize: 2) { _, _, offset in
            offsets.append(offset)
            if offset == 0 { return SongSearchPage(songs: firstPage, total: 4) }
            if response == nil {
                return await withCheckedContinuation {
                    response = $0
                    started.fulfill()
                }
            }
            return SongSearchPage(songs: nextPage, total: 4)
        }
        viewModel.query = "测试"
        await viewModel.searchNow()

        let first = Task { await viewModel.loadMoreIfNeeded(current: firstPage[1]) }
        let second = Task { await viewModel.loadMoreIfNeeded(current: firstPage[1]) }
        await fulfillment(of: [started], timeout: 1)
        response?.resume(returning: SongSearchPage(songs: nextPage, total: 4))
        await first.value
        await second.value

        XCTAssertEqual(offsets, [0, 2])
        XCTAssertEqual(viewModel.songs, firstPage + nextPage)
    }

    func testSubmittingAfterDebouncedResultsDoesNotSearchAgain() async {
        let searched = expectation(description: "Debounced search finished")
        var callCount = 0
        let expected = song(id: 1, name: "晴天")
        let viewModel = SearchViewModel(debounceDuration: .milliseconds(20)) { _, _, _ in
            callCount += 1
            if callCount == 1 { searched.fulfill() }
            return SongSearchPage(songs: [expected], total: 1)
        }
        viewModel.query = "周杰伦"
        viewModel.scheduleSearch()
        await fulfillment(of: [searched], timeout: 1)
        while viewModel.isLoading { await Task.yield() }

        await viewModel.searchNow()

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(viewModel.songs, [expected])
    }

    func testRepeatedSubmissionsDoNotDuplicateAnInFlightSearch() async {
        let started = expectation(description: "Search started")
        var response: CheckedContinuation<SongSearchPage, Never>?
        var callCount = 0
        let expected = song(id: 1, name: "晴天")
        let viewModel = SearchViewModel { _, _, _ in
            callCount += 1
            if callCount == 1 {
                return await withCheckedContinuation {
                    response = $0
                    started.fulfill()
                }
            }
            return SongSearchPage(songs: [], total: 0)
        }
        viewModel.query = "周杰伦"
        let first = Task { await viewModel.searchNow() }
        await fulfillment(of: [started], timeout: 1)

        await viewModel.searchNow()
        XCTAssertEqual(callCount, 1)
        response?.resume(returning: SongSearchPage(songs: [expected], total: 1))
        await first.value
        XCTAssertEqual(viewModel.songs, [expected])
    }

    func testChangingKeywordCancelsTheSubmittedRequest() async {
        let started = expectation(description: "Old request started")
        let cancelled = expectation(description: "Old request cancelled")
        let searched = expectation(description: "New keyword searched")
        let expected = song(id: 1, name: "新结果")
        let viewModel = SearchViewModel(debounceDuration: .milliseconds(20)) { keyword, _, _ in
            if keyword == "旧关键词" {
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    cancelled.fulfill()
                    throw error
                }
                return SongSearchPage(songs: [], total: 0)
            }
            searched.fulfill()
            return SongSearchPage(songs: [expected], total: 1)
        }
        viewModel.query = "旧关键词"
        let first = Task { await viewModel.searchNow() }
        await fulfillment(of: [started], timeout: 1)

        viewModel.query = "新关键词"
        viewModel.scheduleSearch()
        await fulfillment(of: [cancelled, searched], timeout: 1)
        first.cancel()
        await first.value
        while viewModel.isLoading { await Task.yield() }

        XCTAssertEqual(viewModel.songs, [expected])
        XCTAssertNil(viewModel.error)
    }

    func testWhitespaceOnlyChangesKeepResultsAndPagination() async {
        var callCount = 0
        let expected = song(id: 1, name: "晴天")
        let viewModel = SearchViewModel { _, _, _ in
            callCount += 1
            return SongSearchPage(songs: [expected], total: 2)
        }
        viewModel.query = "周杰伦"
        await viewModel.searchNow()

        viewModel.query = "  周杰伦\n"
        viewModel.scheduleSearch()

        XCTAssertEqual(viewModel.songs, [expected])
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(callCount, 1)
        viewModel.query = ""
        viewModel.scheduleSearch()
    }

    private func song(id: Int, name: String) -> Song {
        Song(id: id, name: name, artists: [Artist(id: id, name: "歌手")], album: nil, durationMs: 180_000)
    }
}

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

    private func song(id: Int, name: String) -> Song {
        Song(id: id, name: name, artists: [Artist(id: id, name: "歌手")], album: nil, durationMs: 180_000)
    }
}

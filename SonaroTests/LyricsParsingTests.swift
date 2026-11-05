import XCTest
@testable import Sonaro

/// LRC parsing — the one genuinely non-trivial parser in the app.
final class LyricsParsingTests: XCTestCase {

    func testEmptyInputYieldsNoLines() {
        XCTAssertTrue(MusicService.parseLRC("").isEmpty)
    }

    func testBasicTimestampedLines() {
        let lrc = """
        [00:00.00]First line
        [00:05.50]Second line
        [01:00.00]Third line
        """
        let lines = MusicService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[0].time, 0, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 5.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 60, accuracy: 0.001)
    }

    func testTwoAndThreeDigitFractionsAreScaledByDigitCount() {
        // .5 as two digits (50/100) and three digits (500/1000) both mean 0.5s.
        let lines = MusicService.parseLRC("[00:10.50]a\n[00:20.500]b")
        XCTAssertEqual(lines[0].time, 10.5, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 20.5, accuracy: 0.001)
    }

    func testColonFractionSeparatorIsAccepted() {
        // Some LRC files use [mm:ss:xx] instead of a dot.
        let lines = MusicService.parseLRC("[00:03:25]hi")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 3.25, accuracy: 0.001)
    }

    func testMultipleTimestampsOnOneLineExpandToMultipleLines() {
        let lines = MusicService.parseLRC("[00:01.00][00:05.00]repeated hook")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(\.text), ["repeated hook", "repeated hook"])
        XCTAssertEqual(lines[0].time, 1, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 5, accuracy: 0.001)
    }

    func testMetadataOnlyAndEmptyLinesAreDropped() {
        let lrc = """
        [ti:Song Title]
        [ar:Artist]
        [00:02.00]
        [00:04.00]real words
        """
        let lines = MusicService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "real words")
    }

    func testOutputIsSortedByTime() {
        let lines = MusicService.parseLRC("[00:30.00]late\n[00:05.00]early")
        XCTAssertEqual(lines.map(\.text), ["early", "late"])
    }
}

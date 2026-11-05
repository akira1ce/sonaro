import XCTest
@testable import Sonaro

/// Display formatting used across the player and lists.
final class FormatTests: XCTestCase {

    func testTimeFormatsAsMinutesSeconds() {
        XCTAssertEqual(Format.time(0), "0:00")
        XCTAssertEqual(Format.time(9), "0:09")
        XCTAssertEqual(Format.time(65), "1:05")
        XCTAssertEqual(Format.time(600), "10:00")
    }

    func testTimeGuardsAgainstNonFiniteAndNegative() {
        XCTAssertEqual(Format.time(-5), "0:00")
        XCTAssertEqual(Format.time(.nan), "0:00")
        XCTAssertEqual(Format.time(.infinity), "0:00")
    }

    func testTimeMsConvertsMilliseconds() {
        XCTAssertEqual(Format.timeMs(65_000), "1:05")
        XCTAssertEqual(Format.timeMs(0), "0:00")
    }

    func testPlayCountUsesChineseCompactUnits() {
        XCTAssertEqual(Format.playCount(999), "999")
        XCTAssertEqual(Format.playCount(10_000), "1万")
        XCTAssertEqual(Format.playCount(123_456), "12万")
        XCTAssertEqual(Format.playCount(100_000_000), "1.0亿")
        XCTAssertEqual(Format.playCount(123_456_789), "1.2亿")
    }
}

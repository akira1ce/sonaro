import XCTest
@testable import Sonaro

/// URL helpers for Netease's http image CDN.
final class StringHelpersTests: XCTestCase {

    func testHttpsUpgradeRewritesHttpPrefixOnly() {
        XCTAssertEqual("http://x.com/a.jpg".httpsUpgraded, "https://x.com/a.jpg")
        XCTAssertEqual("https://x.com/a.jpg".httpsUpgraded, "https://x.com/a.jpg")
        // Only the leading scheme is touched, not an http substring in the path.
        XCTAssertEqual("https://x.com/http://y".httpsUpgraded, "https://x.com/http://y")
    }

    func testSizedImageURLUpgradesSchemeAndAppendsParam() {
        let url = "http://p.music/cover.jpg".sizedImageURL(300)
        XCTAssertEqual(url?.absoluteString, "https://p.music/cover.jpg?param=300y300")
    }

    func testSizedImageURLUsesRequestedSide() {
        XCTAssertEqual("https://p/c.jpg".sizedImageURL(120)?.absoluteString,
                       "https://p/c.jpg?param=120y120")
    }
}

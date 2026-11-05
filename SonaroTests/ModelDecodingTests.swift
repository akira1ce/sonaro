import XCTest
@testable import Sonaro

/// The models decode two different backend shapes (new `ar`/`al`/`dt` vs legacy
/// `artists`/`album`/`duration`) and must tolerate missing fields without
/// throwing away the whole object.
final class ModelDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: Song

    func testSongDecodesNewShape() throws {
        let song = try decode(Song.self, """
        {"id":1,"name":"A","ar":[{"id":10,"name":"Artist"}],
         "al":{"id":5,"name":"Album","picUrl":"http://x/y.jpg"},"dt":180000}
        """)
        XCTAssertEqual(song.id, 1)
        XCTAssertEqual(song.artists.map(\.name), ["Artist"])
        XCTAssertEqual(song.album?.name, "Album")
        XCTAssertEqual(song.durationMs, 180_000)
    }

    func testSongDecodesLegacyShape() throws {
        let song = try decode(Song.self, """
        {"id":2,"name":"B","artists":[{"id":11,"name":"L"}],
         "album":{"id":6,"name":"Alb","picUrl":null},"duration":200000}
        """)
        XCTAssertEqual(song.artists.map(\.name), ["L"])
        XCTAssertEqual(song.album?.name, "Alb")
        XCTAssertEqual(song.durationMs, 200_000)
    }

    func testSongToleratesMissingFields() throws {
        let song = try decode(Song.self, #"{"id":3}"#)
        XCTAssertEqual(song.name, "")
        XCTAssertTrue(song.artists.isEmpty)
        XCTAssertNil(song.album)
        XCTAssertEqual(song.durationMs, 0)
        XCTAssertEqual(song.artistText, "未知艺人")
    }

    func testSongArtistTextJoinsMultipleArtists() throws {
        let song = try decode(Song.self, """
        {"id":4,"name":"C","ar":[{"id":1,"name":"X"},{"id":2,"name":"Y"}],"dt":1000}
        """)
        XCTAssertEqual(song.artistText, "X / Y")
    }

    // MARK: Playlist

    func testPlaylistDecodesRecommendCardShape() throws {
        let pl = try decode(Playlist.self, """
        {"id":1,"name":"P","picUrl":"u","copywriter":"c","trackCount":5,"playcount":10000}
        """)
        XCTAssertEqual(pl.coverURLString, "u")
        XCTAssertEqual(pl.subtitle, "c")
        XCTAssertEqual(pl.trackCount, 5)
        XCTAssertEqual(pl.playCount, 10_000)
        XCTAssertFalse(pl.subscribed)
    }

    func testPlaylistDecodesDetailShape() throws {
        let pl = try decode(Playlist.self, """
        {"id":2,"name":"Q","coverImgUrl":"v","description":"d","playCount":20000,"subscribed":true}
        """)
        XCTAssertEqual(pl.coverURLString, "v")
        XCTAssertEqual(pl.subtitle, "d")
        XCTAssertEqual(pl.playCount, 20_000)
        XCTAssertTrue(pl.subscribed)
    }

    // MARK: Profile

    func testProfileToleratesMissingNicknameAndAvatar() throws {
        let profile = try decode(Profile.self, #"{"userId":5}"#)
        XCTAssertEqual(profile.userId, 5)
        XCTAssertEqual(profile.nickname, "")
        XCTAssertNil(profile.avatarUrl)
    }

    func testProfileRoundTripsThroughCodable() throws {
        let original = Profile(userId: 7, nickname: "Demo", avatarUrl: "http://a/b.png")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(restored, original)
    }
}

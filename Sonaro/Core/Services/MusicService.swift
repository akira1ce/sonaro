import Foundation

/// High-level music data access. Each method maps to one NetEase endpoint and
/// returns clean domain models.
enum MusicService {

    // MARK: 搜索单曲

    private struct SearchSongsResponse: Decodable {
        struct ResultBlock: Decodable {
            let songs: [Song]?
            let songCount: Int?
        }

        let result: ResultBlock?
    }

    static func searchSongs(keywords: String, limit: Int = 30, offset: Int = 0) async throws -> SongSearchPage {
        let normalized = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return SongSearchPage(songs: [], total: 0) }

        let resp: SearchSongsResponse = try await APIClient.shared.get(
            "/api/cloudsearch/pc",
            query: [
                "s": normalized,
                "type": 1,
                "limit": limit,
                "offset": offset,
            ],
            authenticated: false
        )
        let songs = resp.result?.songs ?? []
        return SongSearchPage(songs: songs, total: max(resp.result?.songCount ?? songs.count, songs.count))
    }

    // MARK: 每日推荐歌单

    private struct RecommendResourceResponse: Decodable { let recommend: [Playlist]? }

    static func dailyPlaylists() async throws -> [Playlist] {
        let resp: RecommendResourceResponse = try await APIClient.shared.get("/api/v1/discovery/recommend/resource")
        return resp.recommend ?? []
    }

    // MARK: 排行榜歌单

    private struct ToplistResponse: Decodable { let list: [Playlist]? }

    static func toplistPlaylists(limit: Int = 8) async throws -> [Playlist] {
        let resp: ToplistResponse = try await APIClient.shared.get("/api/toplist")
        return Array((resp.list ?? []).prefix(limit))
    }

    // MARK: 精品歌单

    private struct HighQualityPlaylistsResponse: Decodable { let playlists: [Playlist]? }

    static func highQualityPlaylists(limit: Int = 8) async throws -> [Playlist] {
        let resp: HighQualityPlaylistsResponse = try await APIClient.shared.get(
            "/api/playlist/highquality/list", query: ["limit": limit, "cat": "全部", "lasttime": 0, "total": true])
        return resp.playlists ?? []
    }

    // MARK: 热门歌手

    private struct HotArtistsResponse: Decodable { let artists: [Artist]? }

    static func hotArtists(limit: Int = 12) async throws -> [Artist] {
        let resp: HotArtistsResponse = try await APIClient.shared.get(
            "/api/artist/top", query: ["limit": limit, "offset": 0, "total": true])
        return resp.artists ?? []
    }

    // MARK: 歌手详情与热门歌曲

    private struct ArtistPageResponse: Decodable {
        let artist: Artist
        let hotSongs: [Song]?
    }

    static func artistPage(id: Int) async throws -> ArtistPage {
        let resp: ArtistPageResponse = try await APIClient.shared.get(
            "/api/v1/artist/\(id)")
        return ArtistPage(artist: resp.artist, songs: resp.hotSongs ?? [])
    }

    // MARK: 每日推荐歌曲

    private struct RecommendSongsResponse: Decodable {
        struct DataBlock: Decodable { let dailySongs: [Song]? }
        let data: DataBlock?
    }

    static func dailySongs() async throws -> [Song] {
        let resp: RecommendSongsResponse = try await APIClient.shared.get("/api/v3/discovery/recommend/songs")
        return resp.data?.dailySongs ?? []
    }

    // MARK: 播放地址

    struct SongURLResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let url: String?
            let isPreview: Bool

            enum CodingKeys: String, CodingKey { case id, url, freeTrialInfo }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(Int.self, forKey: .id)
                url = try c.decodeIfPresent(String.self, forKey: .url)
                if try !c.contains(.freeTrialInfo) || c.decodeNil(forKey: .freeTrialInfo) {
                    isPreview = false
                } else {
                    isPreview = (try? c.decode(String.self, forKey: .freeTrialInfo)) != "null"
                }
            }
        }
        let data: [Item]?
    }

    /// - Parameter level: standard | higher | exhigh | lossless | hires ...
    static func songURL(id: Int, level: String = "standard") async throws -> URL {
        try Task.checkCancellation()
        let resp: SongURLResponse = try await APIClient.shared.get(
            "/api/song/enhance/player/url/v1", query: ["ids": "[\(id)]", "level": level, "encodeType": "flac"])
        guard let item = resp.data?.first(where: { $0.id == id }), !item.isPreview,
              let raw = item.url, let url = URL(string: raw.httpsUpgraded),
              url.scheme == "https", url.host != nil else {
            throw APIError.noPlayableURL
        }
        return url
    }

    // MARK: 歌词

    private struct LyricResponse: Decodable {
        struct LRC: Decodable { let lyric: String? }
        let lrc: LRC?
    }

    static func lyrics(id: Int) async throws -> [LyricLine] {
        if let cached = await LyricsCache.shared.lyrics(id: id) { return cached }
        let resp: LyricResponse = try await APIClient.shared.get("/api/song/lyric", query: ["id": id, "lv": -1, "tv": -1, "rv": -1, "kv": -1])
        return await LyricsCache.shared.store(id: id, raw: resp.lrc?.lyric ?? "")
    }

    // MARK: 歌单内歌曲

    private struct PlaylistTracksResponse: Decodable { let songs: [Song]? }
    private struct PlaylistIDsResponse: Decodable {
        struct Detail: Decodable {
            struct Track: Decodable { let id: Int }
            let trackIds: [Track]
        }
        let playlist: Detail?
    }

    struct PlaylistTrackPage {
        let songs: [Song]
        let nextOffset: Int
        let hasMore: Bool

        init(ids: [Int], songs: [Int: Song], offset: Int, total: Int) {
            self.songs = ids.compactMap { songs[$0] }
            nextOffset = offset + ids.count
            hasMore = nextOffset < total
        }
    }

    static func playlistTracks(id: Int, limit: Int = 200, offset: Int = 0) async throws -> PlaylistTrackPage {
        guard limit > 0, offset >= 0 else { throw APIError.api(code: 400, message: "歌单分页参数无效") }
        let detail: PlaylistIDsResponse = try await APIClient.shared.get(
            "/api/v6/playlist/detail", query: ["id": id, "n": 0, "s": 0])
        guard let playlist = detail.playlist else { throw APIError.api(code: 404, message: "歌单不存在或无访问权限") }
        let ids = Array(playlist.trackIds.dropFirst(offset).prefix(limit).map(\.id))
        var songs: [Int: Song] = [:]
        for start in stride(from: 0, to: ids.count, by: 500) {
            let batch = Array(ids.dropFirst(start).prefix(500))
            let encoded = try JSONSerialization.data(withJSONObject: batch.map { ["id": $0] })
            let response: PlaylistTracksResponse = try await APIClient.shared.get(
                "/api/v3/song/detail", query: ["c": String(decoding: encoded, as: UTF8.self)])
            for song in response.songs ?? [] { songs[song.id] = song }
        }
        return PlaylistTrackPage(ids: ids, songs: songs, offset: offset, total: playlist.trackIds.count)
    }

    // MARK: 歌单详情

    private struct PlaylistDetailResponse: Decodable { let playlist: Playlist? }

    static func playlistDetail(id: Int) async throws -> Playlist? {
        let resp: PlaylistDetailResponse = try await APIClient.shared.get(
            "/api/v6/playlist/detail", query: ["id": id, "n": 0, "s": 0])
        return resp.playlist
    }

    // MARK: 用户歌单（含收藏）

    private struct UserPlaylistResponse: Decodable { let playlist: [Playlist]? }

    static func userPlaylists(uid: Int) async throws -> [Playlist] {
        let resp: UserPlaylistResponse = try await APIClient.shared.get(
            "/api/user/playlist", query: ["uid": uid, "limit": 100, "offset": 0, "includeVideo": false])
        return resp.playlist ?? []
    }

    // MARK: 播放记录

    private struct UserRecordResponse: Decodable {
        struct Item: Decodable {
            let song: Song?
            let playCount: Int?
        }
        let allData: [Item]?
        let weekData: [Item]?
    }

    /// Recently played songs for `uid`, newest first. NetEase returns the
    /// window named by `type`, so only that array is populated.
    static func recentPlayed(
        uid: Int,
        range: RecentPlayRange = .week,
        limit: Int = 100
    ) async throws -> [PlayRecord] {
        let resp: UserRecordResponse = try await APIClient.shared.get(
            "/api/v1/play/record", query: ["uid": uid, "type": range == .week ? 1 : 0])
        let items = range == .week ? resp.weekData : resp.allData
        return (items ?? []).prefix(limit).compactMap { item in
            item.song.map { PlayRecord(song: $0, playCount: item.playCount ?? 0) }
        }
    }

    // MARK: 喜欢音乐列表

    private struct LikeListResponse: Decodable { let ids: [Int]? }

    /// The user's liked-song IDs.
    static func likedSongIDs(uid: Int) async throws -> [Int] {
        let resp: LikeListResponse = try await APIClient.shared.get(
            "/api/song/like/get", query: ["uid": uid])
        return resp.ids ?? []
    }

    // MARK: 喜欢 / 取消喜欢音乐

    private struct LikeActionResponse: Decodable { let code: Int }

    /// Likes (`like: true`) or unlikes a song. Returns whether NetEase
    /// reported success (`code == 200`).
    @discardableResult
    static func setLiked(id: Int, like: Bool) async throws -> Bool {
        let resp: LikeActionResponse = try await APIClient.shared.get(
            "/api/radio/like", query: ["trackId": id, "like": like, "alg": "itembased", "time": 3])
        return resp.code == 200
    }

    // MARK: 收藏 / 取消收藏歌单

    @discardableResult
    static func setPlaylistSubscribed(id: Int, subscribed: Bool) async throws -> Bool {
        let resp: LikeActionResponse = try await APIClient.shared.get(
            "/api/playlist/\(subscribed ? "subscribe" : "unsubscribe")", query: ["id": id])
        return resp.code == 200
    }

    // MARK: - LRC parsing (delegates to LyricParser)

    @available(*, deprecated, message: "Use LyricParser.parse(_:) directly")
    static func parseLRC(_ raw: String) -> [LyricLine] {
        LyricParser.parse(raw)
    }
}

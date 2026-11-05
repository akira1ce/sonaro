import Foundation

/// High-level music data access. Each method maps to one backend endpoint and
/// returns clean domain models.
enum MusicService {

    // MARK: 搜索单曲  (GET /cloudsearch)

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
            "/cloudsearch",
            query: [
                "keywords": normalized,
                "type": "1",
                "limit": String(limit),
                "offset": String(offset),
            ],
            authenticated: false
        )
        let songs = resp.result?.songs ?? []
        return SongSearchPage(songs: songs, total: max(resp.result?.songCount ?? songs.count, songs.count))
    }

    // MARK: 每日推荐歌单  (GET /recommend/resource)

    private struct RecommendResourceResponse: Decodable { let recommend: [Playlist]? }

    static func dailyPlaylists() async throws -> [Playlist] {
        let resp: RecommendResourceResponse = try await APIClient.shared.get("/recommend/resource")
        return resp.recommend ?? []
    }

    // MARK: 排行榜歌单  (GET /toplist)

    private struct ToplistResponse: Decodable { let list: [Playlist]? }

    static func toplistPlaylists(limit: Int = 8) async throws -> [Playlist] {
        let resp: ToplistResponse = try await APIClient.shared.get("/toplist")
        return Array((resp.list ?? []).prefix(limit))
    }

    // MARK: 精品歌单  (GET /top/playlist/highquality)

    private struct HighQualityPlaylistsResponse: Decodable { let playlists: [Playlist]? }

    static func highQualityPlaylists(limit: Int = 8) async throws -> [Playlist] {
        let resp: HighQualityPlaylistsResponse = try await APIClient.shared.get(
            "/top/playlist/highquality", query: ["limit": String(limit)])
        return resp.playlists ?? []
    }

    // MARK: 热门歌手  (GET /top/artists)

    private struct HotArtistsResponse: Decodable { let artists: [Artist]? }

    static func hotArtists(limit: Int = 12) async throws -> [Artist] {
        let resp: HotArtistsResponse = try await APIClient.shared.get(
            "/top/artists", query: ["limit": String(limit), "offset": "0"])
        return resp.artists ?? []
    }

    // MARK: 歌手详情与热门歌曲  (GET /artists)

    private struct ArtistPageResponse: Decodable {
        let artist: Artist
        let hotSongs: [Song]?
    }

    static func artistPage(id: Int) async throws -> ArtistPage {
        let resp: ArtistPageResponse = try await APIClient.shared.get(
            "/artists", query: ["id": String(id)])
        return ArtistPage(artist: resp.artist, songs: resp.hotSongs ?? [])
    }

    // MARK: 每日推荐歌曲  (GET /recommend/songs)

    private struct RecommendSongsResponse: Decodable {
        struct DataBlock: Decodable { let dailySongs: [Song]? }
        let data: DataBlock?
    }

    static func dailySongs() async throws -> [Song] {
        let resp: RecommendSongsResponse = try await APIClient.shared.get("/recommend/songs")
        return resp.data?.dailySongs ?? []
    }

    // MARK: 播放地址  (GET /song/url/v1)

    private struct SongURLResponse: Decodable {
        struct Item: Decodable { let id: Int; let url: String? }
        let data: [Item]?
    }

    /// - Parameter level: standard | higher | exhigh | lossless | hires ...
    static func songURL(id: Int, level: String = "standard") async throws -> URL {
        // Upstream risk control intermittently answers HTTP 400 ("network
        // environment risk") for one request, then succeeds — absorb the flake.
        var attempt = 0
        while true {
            do {
                try Task.checkCancellation()
                let resp: SongURLResponse = try await APIClient.shared.get(
                    "/song/url/v1", query: ["id": String(id), "level": level])
                guard let raw = resp.data?.first(where: { $0.id == id })?.url ?? resp.data?.first?.url,
                      !raw.isEmpty, let url = URL(string: raw.httpsUpgraded) else {
                    throw APIError.noPlayableURL
                }
                return url
            } catch APIError.http(400, _) where attempt < 2 {
                attempt += 1
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
    }

    // MARK: 歌词  (GET /lyric)

    private struct LyricResponse: Decodable {
        struct LRC: Decodable { let lyric: String? }
        let lrc: LRC?
    }

    static func lyrics(id: Int) async throws -> [LyricLine] {
        if let cached = await LyricsCache.shared.lyrics(id: id) { return cached }
        let resp: LyricResponse = try await APIClient.shared.get("/lyric", query: ["id": String(id)])
        return await LyricsCache.shared.store(id: id, raw: resp.lrc?.lyric ?? "")
    }

    // MARK: 歌单内歌曲  (GET /playlist/track/all)

    private struct PlaylistTracksResponse: Decodable { let songs: [Song]? }

    static func playlistTracks(id: Int, limit: Int = 300) async throws -> [Song] {
        let resp: PlaylistTracksResponse = try await APIClient.shared.get(
            "/playlist/track/all", query: ["id": String(id), "limit": String(limit)])
        return resp.songs ?? []
    }

    // MARK: 歌单详情  (GET /playlist/detail)

    private struct PlaylistDetailResponse: Decodable { let playlist: Playlist? }

    static func playlistDetail(id: Int) async throws -> Playlist? {
        let resp: PlaylistDetailResponse = try await APIClient.shared.get(
            "/playlist/detail", query: ["id": String(id)])
        return resp.playlist
    }

    // MARK: 用户歌单（含收藏）  (GET /user/playlist)

    private struct UserPlaylistResponse: Decodable { let playlist: [Playlist]? }

    static func userPlaylists(uid: Int) async throws -> [Playlist] {
        let resp: UserPlaylistResponse = try await APIClient.shared.get(
            "/user/playlist", query: ["uid": String(uid), "limit": "100"])
        return resp.playlist ?? []
    }

    // MARK: 播放记录  (GET /user/record)

    private struct UserRecordResponse: Decodable {
        struct Item: Decodable {
            let song: Song?
            let playCount: Int?
        }
        let allData: [Item]?
        let weekData: [Item]?
    }

    /// Recently played songs for `uid`, newest first. The backend returns the
    /// window named by `type`, so only that array is populated.
    static func recentPlayed(
        uid: Int,
        range: RecentPlayRange = .week,
        limit: Int = 100
    ) async throws -> [PlayRecord] {
        let resp: UserRecordResponse = try await APIClient.shared.get(
            "/user/record", query: ["uid": String(uid), "type": range.type])
        let items = range == .week ? resp.weekData : resp.allData
        return (items ?? []).prefix(limit).compactMap { item in
            item.song.map { PlayRecord(song: $0, playCount: item.playCount ?? 0) }
        }
    }

    // MARK: 喜欢音乐列表  (GET /likelist)

    private struct LikeListResponse: Decodable { let ids: [Int]? }

    /// The user's liked-song IDs. `freshness` bypasses the backend cache so a
    /// just-liked song shows up immediately.
    static func likedSongIDs(uid: Int) async throws -> [Int] {
        let resp: LikeListResponse = try await APIClient.shared.get(
            "/likelist", query: ["uid": String(uid)], freshness: true)
        return resp.ids ?? []
    }

    // MARK: 喜欢 / 取消喜欢音乐  (GET /like)

    private struct LikeActionResponse: Decodable { let code: Int }

    /// Likes (`like: true`) or unlikes a song. Returns whether the backend
    /// reported success (`code == 200`).
    @discardableResult
    static func setLiked(id: Int, like: Bool) async throws -> Bool {
        let resp: LikeActionResponse = try await APIClient.shared.get(
            "/like", query: ["id": String(id), "like": like ? "true" : "false"], freshness: true)
        return resp.code == 200
    }

    // MARK: 收藏 / 取消收藏歌单  (GET /playlist/subscribe)

    @discardableResult
    static func setPlaylistSubscribed(id: Int, subscribed: Bool) async throws -> Bool {
        let resp: LikeActionResponse = try await APIClient.shared.get(
            "/playlist/subscribe", query: ["id": String(id), "t": subscribed ? "1" : "2"],
            freshness: true)
        return resp.code == 200
    }

    // MARK: - LRC parsing (delegates to LyricParser)

    @available(*, deprecated, message: "Use LyricParser.parse(_:) directly")
    static func parseLRC(_ raw: String) -> [LyricLine] {
        LyricParser.parse(raw)
    }
}

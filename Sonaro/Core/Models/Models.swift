import Foundation

// MARK: - Artist

/// Decodes both the slim artist embedded in songs and the richer objects from
/// `/top/artists` and `/artists` (portrait, aliases, counts).
struct Artist: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let picUrl: String?
    let img1v1Url: String?
    let alias: [String]
    let albumSize: Int
    let musicSize: Int
    let briefDesc: String

    enum CodingKeys: String, CodingKey {
        case id, name, picUrl, img1v1Url, alias, albumSize, musicSize, briefDesc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = try? c.decodeIfPresent(String.self, forKey: .picUrl)
        img1v1Url = try? c.decodeIfPresent(String.self, forKey: .img1v1Url)
        alias = (try? c.decode([String].self, forKey: .alias)) ?? []
        albumSize = (try? c.decode(Int.self, forKey: .albumSize)) ?? 0
        musicSize = (try? c.decode(Int.self, forKey: .musicSize)) ?? 0
        briefDesc = (try? c.decodeIfPresent(String.self, forKey: .briefDesc)) ?? ""
    }

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        picUrl = nil
        img1v1Url = nil
        alias = []
        albumSize = 0
        musicSize = 0
        briefDesc = ""
    }

    func coverURL(_ side: Int = 200) -> URL? {
        (picUrl ?? img1v1Url)?.sizedImageURL(side)
    }
}

/// `/artists` returns the artist profile together with its hot songs.
struct ArtistPage {
    let artist: Artist
    let songs: [Song]
}

// MARK: - Album

struct Album: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let picUrl: String?

    enum CodingKeys: String, CodingKey { case id, name, picUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = try? c.decodeIfPresent(String.self, forKey: .picUrl)
    }

    init(id: Int, name: String, picUrl: String?) {
        self.id = id; self.name = name; self.picUrl = picUrl
    }
}

// MARK: - Song

/// Decodes both the "new" API shape (`ar` / `al` / `dt`) used by recommendations
/// and playlist tracks, and the "legacy" shape (`artists` / `album` / `duration`).
struct Song: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let artists: [Artist]
    let album: Album?
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case ar, al, dt
        case artists, album, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""

        if let ar = try? c.decode([Artist].self, forKey: .ar) {
            artists = ar
        } else if let a = try? c.decode([Artist].self, forKey: .artists) {
            artists = a
        } else {
            artists = []
        }

        if let al = try? c.decode(Album.self, forKey: .al) {
            album = al
        } else if let a = try? c.decode(Album.self, forKey: .album) {
            album = a
        } else {
            album = nil
        }

        if let dt = try? c.decode(Int.self, forKey: .dt) {
            durationMs = dt
        } else if let d = try? c.decode(Int.self, forKey: .duration) {
            durationMs = d
        } else {
            durationMs = 0
        }
    }

    init(id: Int, name: String, artists: [Artist], album: Album?, durationMs: Int) {
        self.id = id; self.name = name; self.artists = artists
        self.album = album; self.durationMs = durationMs
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(artists, forKey: .artists)
        try c.encodeIfPresent(album, forKey: .album)
        try c.encode(durationMs, forKey: .duration)
    }

    var artistText: String {
        artists.isEmpty ? "未知艺人" : artists.map(\.name).joined(separator: " / ")
    }

    var albumName: String { album?.name ?? "" }
    var coverURLString: String? { album?.picUrl }
    func coverURL(_ side: Int = 300) -> URL? { album?.picUrl?.sizedImageURL(side) }
}

struct SongSearchPage: Equatable {
    let songs: [Song]
    let total: Int
}

// MARK: - Playlist

/// Handles both `/recommend/resource` cards (`picUrl` / `copywriter` / `playcount`)
/// and `/playlist/detail` (`coverImgUrl` / `description` / `playCount`).
struct Playlist: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let coverURLString: String?
    let subtitle: String?
    let trackCount: Int
    let playCount: Int
    let subscribed: Bool
    let creator: Profile?
    /// Epoch milliseconds; 0 when the endpoint doesn't report it.
    let updateTime: Int
    /// `5` marks the auto-generated "我喜欢的音乐" playlist.
    let specialType: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case picUrl, coverImgUrl
        case copywriter, description
        case trackCount
        case playCount, playcount
        case subscribed
        case creator, updateTime, trackUpdateTime
        case specialType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        coverURLString = (try? c.decodeIfPresent(String.self, forKey: .picUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .coverImgUrl)) ?? nil
        subtitle = (try? c.decodeIfPresent(String.self, forKey: .copywriter))
            ?? (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
        trackCount = (try? c.decode(Int.self, forKey: .trackCount)) ?? 0
        playCount = (try? c.decode(Int.self, forKey: .playCount))
            ?? (try? c.decode(Int.self, forKey: .playcount)) ?? 0
        subscribed = (try? c.decode(Bool.self, forKey: .subscribed)) ?? false
        creator = try? c.decodeIfPresent(Profile.self, forKey: .creator)
        updateTime = (try? c.decode(Int.self, forKey: .updateTime))
            ?? (try? c.decode(Int.self, forKey: .trackUpdateTime)) ?? 0
        specialType = (try? c.decode(Int.self, forKey: .specialType)) ?? 0
    }

    func coverURL(_ side: Int = 400) -> URL? { coverURLString?.sizedImageURL(side) }
}

// MARK: - Play record

/// The window `/user/record` is queried for.
enum RecentPlayRange: String, CaseIterable, Identifiable {
    case week, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "最近一周"
        case .all: return "所有时间"
        }
    }

    /// `type`: 1 returns weekData, 0 returns allData.
    var type: String {
        switch self {
        case .week: return "1"
        case .all: return "0"
        }
    }
}

/// One entry from `/user/record`: a played song plus how many times it was played.
struct PlayRecord: Identifiable, Decodable, Hashable {
    let song: Song
    let playCount: Int

    var id: Int { song.id }
}

// MARK: - Profile

struct Profile: Codable, Hashable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey { case userId, nickname, avatarUrl }

    /// Tolerant decoding: a missing/null `nickname` or `avatarUrl` must not nuke the
    /// whole profile (some endpoints return a slimmer object than others).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
    }

    init(userId: Int, nickname: String, avatarUrl: String?) {
        self.userId = userId; self.nickname = nickname; self.avatarUrl = avatarUrl
    }

    func avatarURL(_ side: Int = 120) -> URL? { avatarUrl?.sizedImageURL(side) }
}

// MARK: - Lyrics

struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let text: String
}

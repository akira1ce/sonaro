import Foundation

/// Persistent cache of parsed lyrics. Lyrics for a given song id never change,
/// so entries live forever: an in-memory map serves the session, backed by one
/// small `.lrc` file per song id on disk so a replayed (or relaunched) song
/// never re-hits the network. Empty results are cached too — a song with no
/// lyrics shouldn't be requested again.
actor LyricsCache {
    static let shared = LyricsCache()

    private var memory: [Int: [LyricLine]] = [:]
    private let dir: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ id: Int) -> URL { dir.appendingPathComponent("\(id).lrc") }

    /// Cached lyrics for `id`, or `nil` if never fetched. Reads memory first,
    /// then the on-disk LRC (parsing on the way in and promoting to memory).
    func lyrics(id: Int) -> [LyricLine]? {
        if let hit = memory[id] { return hit }
        guard let raw = try? String(contentsOf: file(id), encoding: .utf8) else { return nil }
        let lines = LyricParser.parse(raw)
        memory[id] = lines
        return lines
    }

    /// Stores the raw LRC for `id` (parsed into memory, persisted to disk) and
    /// returns the parsed lines so callers don't parse twice.
    @discardableResult
    func store(id: Int, raw: String) -> [LyricLine] {
        let lines = LyricParser.parse(raw)
        memory[id] = lines
        try? raw.write(to: file(id), atomically: true, encoding: .utf8)
        return lines
    }

    /// Disk bytes currently occupied by cached LRC files.
    func diskUsage() -> Int {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Array(keys)) else { return 0 }
        return files.reduce(0) { total, file in
            let values = try? file.resourceValues(forKeys: keys)
            return total + (values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
    }

    /// Drops memory and disk entries. The directory itself stays so new lyrics
    /// can be written without recreating it.
    func clear() {
        memory.removeAll()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}

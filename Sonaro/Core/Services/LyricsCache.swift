import Foundation

/// Parsed lyrics reused during this app session; nothing is read or written on disk.
actor LyricsCache {
    static let shared = LyricsCache()
    private var memory: [Int: [LyricLine]] = [:]

    func lyrics(id: Int) -> [LyricLine]? { memory[id] }

    @discardableResult
    func store(id: Int, raw: String) -> [LyricLine] {
        let lines = LyricParser.parse(raw)
        memory[id] = lines
        return lines
    }

    func clear() { memory.removeAll() }
}

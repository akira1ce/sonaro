import Foundation

/// Pure LRC (LyRiCs) parser. Extracts timestamped lines from raw `.lrc` text.
/// No dependencies on networking or app state — just string → [LyricLine].
enum LyricParser {

    /// Parses `[mm:ss.xx]text` lines (multiple timestamps per line supported),
    /// dropping metadata-only lines, sorted by time.
    static func parse(_ raw: String) -> [LyricLine] {
        guard !raw.isEmpty else { return [] }
        var lines: [LyricLine] = []
        let pattern = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")

        for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let rowStr = String(row)
            guard let regex = pattern else { continue }
            let ns = rowStr as NSString
            let matches = regex.matches(in: rowStr, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let fracStr = ns.substring(with: m.range(at: 3))
                    frac = (Double(fracStr) ?? 0) / pow(10, Double(fracStr.count))
                }
                lines.append(LyricLine(time: min * 60 + sec + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

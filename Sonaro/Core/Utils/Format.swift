import Foundation

/// Formatting helpers shared across the player and lists.
enum Format {
    /// Seconds -> `m:ss`.
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Milliseconds -> `m:ss`.
    static func timeMs(_ ms: Int) -> String { time(Double(ms) / 1000) }

    /// Chinese-style compact play counts (万 / 亿).
    static func playCount(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 1e8) }
        if n >= 10_000 { return String(format: "%.0f万", Double(n) / 1e4) }
        return "\(n)"
    }

    /// Epoch milliseconds -> `yyyy-MM-dd`.
    static func date(_ ms: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}

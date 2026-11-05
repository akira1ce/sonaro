import Foundation

/// Handles lyric index lookup from the current playback time. Extracted from
/// PlayerManager to keep lyric logic independent and testable.
struct LyricSynchronizer {
    /// Current lyrics being tracked.
    var lyrics: [LyricLine] = []

    /// Returns the index of the lyric line that should be highlighted for the
    /// given playback time, or nil if lyrics are empty.
    func currentIndex(for time: Double) -> Int? {
        guard !lyrics.isEmpty else { return nil }

        let targetTime = time + 0.2
        var lowerBound = 0
        var upperBound = lyrics.count
        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if lyrics[midpoint].time <= targetTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        return max(0, lowerBound - 1)
    }
}

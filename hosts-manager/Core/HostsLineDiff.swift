import Foundation

nonisolated struct HostsLineDiff: Equatable {
    let removed: [String]
    let added: [String]

    var isEmpty: Bool {
        removed.isEmpty && added.isEmpty
    }

    /// Hosts-file ordering is not semantically significant. A frequency-based
    /// diff avoids the quadratic memory use of a full LCS for large files.
    static func compare(before: String, after: String) -> HostsLineDiff {
        let beforeLines = before.components(separatedBy: "\n")
        let afterLines = after.components(separatedBy: "\n")
        var unmatchedAfter = lineCounts(afterLines)
        var removed: [String] = []
        for line in beforeLines {
            if let count = unmatchedAfter[line], count > 0 {
                unmatchedAfter[line] = count - 1
            } else {
                removed.append(line)
            }
        }

        var unmatchedBefore = lineCounts(beforeLines)
        var added: [String] = []
        for line in afterLines {
            if let count = unmatchedBefore[line], count > 0 {
                unmatchedBefore[line] = count - 1
            } else {
                added.append(line)
            }
        }
        return HostsLineDiff(removed: removed, added: added)
    }

    private static func lineCounts(_ lines: [String]) -> [String: Int] {
        lines.reduce(into: [:]) { counts, line in
            counts[line, default: 0] += 1
        }
    }
}

import Foundation

nonisolated enum HostsSourceEditing {
    /// Toggles comments per line. Mixed selections are treated as uncommented,
    /// so no uncommented line can lose its first character.
    static func toggledComment(in block: String) -> String {
        let lines = block.components(separatedBy: "\n")
        let nonEmptyLines = lines.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let shouldComment = nonEmptyLines.contains {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }
        return lines.map { line in
            if shouldComment {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("#") ? line : comment(line)
            }
            return uncomment(line)
        }.joined(separator: "\n")
    }

    private static func comment(_ line: String) -> String {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
        let indentation = line.prefix { $0 == " " || $0 == "\t" }
        let content = line.dropFirst(indentation.count)
        return String(indentation) + "# " + content
    }

    private static func uncomment(_ line: String) -> String {
        let indentation = line.prefix { $0 == " " || $0 == "\t" }
        var content = line.dropFirst(indentation.count)
        guard content.hasPrefix("#") else { return line }
        content = content.dropFirst()
        if content.hasPrefix(" ") {
            content = content.dropFirst()
        }
        return String(indentation) + content
    }
}

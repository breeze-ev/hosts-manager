import Darwin
import Foundation

enum HostsValueValidator {
    nonisolated private static let maximumContentBytes = 1_048_576

    nonisolated static func normalizedIP(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if isValidIPv4(value) {
            return value
        }

        let parts = value.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard isValidIPv6(String(parts[0])) else { return nil }

        if parts.count == 2 {
            let zone = String(parts[1])
            guard !zone.isEmpty, zone.count <= 64 else { return nil }
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            guard zone.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        }
        return value
    }

    nonisolated static func isValidHostname(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 1024, value == input else { return false }
        guard !value.contains("#") else { return false }
        guard !value.contains("\0") else { return false }
        return !value.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) ||
                CharacterSet.controlCharacters.contains($0) ||
                $0 == "/" || $0 == "\\"
        }
    }

    nonisolated static func isValidDescription(_ input: String) -> Bool {
        !input.unicodeScalars.contains {
            $0 == "\n" || $0 == "\r" || $0 == "\0" ||
                CharacterSet.controlCharacters.contains($0)
        }
    }

    nonisolated static func validate(content: String) -> String? {
        guard let data = content.data(using: .utf8) else {
            return "Hosts content is not valid UTF-8."
        }
        guard data.count <= maximumContentBytes else {
            return "Hosts content exceeds the 1 MiB safety limit."
        }
        guard !content.contains("\0") else {
            return "Hosts content contains a null byte."
        }

        for (index, rawLine) in content.components(separatedBy: "\n").enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let ip = fields.first, normalizedIP(ip) != nil else {
                return "Line \(index + 1) contains an invalid IP address."
            }
            let hostnames = fields.dropFirst()
            guard !hostnames.isEmpty else {
                return "Line \(index + 1) does not contain a hostname."
            }
            guard hostnames.allSatisfy(isValidHostname) else {
                return "Line \(index + 1) contains an invalid hostname."
            }
        }
        return nil
    }

    nonisolated private static func isValidIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString {
            inet_pton(AF_INET, $0, &address) == 1
        }
    }

    nonisolated private static func isValidIPv6(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString {
            inet_pton(AF_INET6, $0, &address) == 1
        }
    }
}

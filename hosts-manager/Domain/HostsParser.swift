import Foundation

// MARK: - Parser

nonisolated enum HostsParser {
    static let systemIps: Set<String> = ["127.0.0.1", "::1", "255.255.255.255", "fe80::1%lo0", "0.0.0.0"]
    static let systemNames: Set<String> = ["localhost", "broadcasthost"]
    static let systemDefaults: [ParsedHostEntry] = [
        ParsedHostEntry(ip: "127.0.0.1", hostnames: ["localhost"], desc: "localhost", isSystem: true),
        ParsedHostEntry(ip: "::1", hostnames: ["localhost"], desc: "localhost ipv6", isSystem: true),
        ParsedHostEntry(ip: "255.255.255.255", hostnames: ["broadcasthost"], desc: "broadcast", isSystem: true)
    ]

    /// Parse the raw contents of a hosts file into structured entries.
    static func parse(_ text: String) -> [ParsedHostEntry] {
        var result: [ParsedHostEntry] = []
        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            var enabled = true
            var desc = ""
            if line.hasPrefix("#") {
                enabled = false
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if let hash = line.firstIndex(of: "#") {
                let comment = String(line[line.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
                desc = comment
                line = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("#") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let rawIP = parts.first,
                  let ip = HostsValueValidator.normalizedIP(rawIP) else { continue }
            let hosts = Array(parts.dropFirst()).filter { !$0.isEmpty }
            guard !hosts.isEmpty,
                  hosts.allSatisfy(HostsValueValidator.isValidHostname) else { continue }

            // Only genuinely reserved hostnames are system entries; an arbitrary
            // IP such as 127.0.0.1 must not lock user-defined lines (e.g. blockers).
            let isSystem = hosts.contains(where: { systemNames.contains($0.lowercased()) })
            result.append(ParsedHostEntry(ip: ip, hostnames: hosts, desc: desc, isEnabled: enabled, isSystem: isSystem))
        }
        return result
    }

    /// Serialize entries back to hosts-file text.
    static func serialize(_ entries: [ParsedHostEntry]) -> String {
        entries.map { entry -> String in
            let line = line(for: entry)
            return entry.isEnabled ? line : "# " + line
        }.joined(separator: "\n")
    }

    /// Merge managed entries with external entries that are not owned by a profile.
    static func mergedContent(
        entries: [ParsedHostEntry],
        externalEntries: [ParsedHostEntry] = []
    ) -> String {
        var lines: [String] = ["# Managed by Hosts Manager — do not edit by hand", ""]
        lines.append("# --- System ---")
        lines.append("")
        for entry in systemDefaults { lines.append(line(for: entry)) }
        lines.append("")
        lines.append("# --- User ---")
        // Everything user-authored goes into the User section; entries whose
        // hostname is localhost/broadcasthost are covered by System above.
        let user = entries.filter { $0.isEnabled && !$0.hostnames.contains { systemNames.contains($0.lowercased()) } }
        var seenMappings = Set<String>()
        for entry in dedupeMappings(user, seen: &seenMappings) {
            lines.append(line(for: entry))
        }
        lines.append("")
        lines.append("# --- External ---")
        for entry in dedupeMappings(
            externalEntries.filter(\.isEnabled),
            seen: &seenMappings
        ) {
            lines.append(line(for: entry))
        }
        for entry in dedupeMappings(
            externalEntries.filter { !$0.isEnabled },
            seen: &seenMappings
        ) {
            lines.append("# " + line(for: entry))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func line(for entry: ParsedHostEntry) -> String {
        let hosts = entry.hostnames.joined(separator: " ")
        let padding = String(repeating: " ", count: max(1, 18 - entry.ip.count))
        let description = entry.desc.isEmpty ? "" : " # " + entry.desc
        return entry.ip + padding + hosts + description
    }

    /// Remove exact duplicate (ip + hostname) rows, keeping the first occurrence.
    static func dedupe(_ entries: [ParsedHostEntry]) -> [ParsedHostEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            let key = entry.ip + "|" + entry.hostnames.joined(separator: ",")
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    /// Collapse identical IP/hostname mappings while preserving the order and
    /// descriptions of the first occurrence.
    static func dedupeMappings(
        _ entries: [ParsedHostEntry],
        seen: inout Set<String>
    ) -> [ParsedHostEntry] {
        entries.compactMap { entry in
            var hostnames: [String] = []
            for hostname in entry.hostnames {
                let key = entry.ip.lowercased() + "|" + hostname.lowercased()
                if seen.insert(key).inserted {
                    hostnames.append(hostname)
                }
            }
            guard !hostnames.isEmpty else { return nil }
            var result = entry
            result.hostnames = hostnames
            return result
        }
    }

    static func entriesEquivalent(
        _ lhs: [ParsedHostEntry],
        _ rhs: [ParsedHostEntry]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.ip == right.ip &&
                left.hostnames == right.hostnames &&
                left.desc == right.desc &&
                left.isEnabled == right.isEnabled &&
                left.isSystem == right.isSystem
        }
    }
}

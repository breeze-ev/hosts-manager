import Foundation

// MARK: - Conflict detection

nonisolated enum HostValidator {
    /// Returns hostnames that appear in more than one entry with differing IPs (conflict)
    /// or the exact same ip+host (duplicate).
    static func issues(entries: [ParsedHostEntry]) -> [HostIssue] {
        var byHost: [String: [ParsedHostEntry]] = [:]
        for entry in entries {
            for host in entry.hostnames {
                byHost[host.lowercased(), default: []].append(entry)
            }
        }
        var result: [HostIssue] = []
        for (host, list) in byHost where list.count > 1 {
            let ips = Set(list.map(\.ip))
            result.append(HostIssue(hostname: host, kind: ips.count > 1 ? .conflict : .duplicate, count: list.count))
        }
        return result
    }
}

nonisolated enum HostIssueKind: Equatable { case conflict, duplicate }

nonisolated struct HostIssue: Identifiable {
    let id = UUID()
    let hostname: String
    let kind: HostIssueKind
    let count: Int
}

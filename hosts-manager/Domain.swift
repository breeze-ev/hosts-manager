import Foundation

// MARK: - Parsed host entry

nonisolated struct ParsedHostEntry: Identifiable, Equatable {
    let id = UUID()
    var ip: String
    var hostnames: [String]
    var desc: String
    var isEnabled: Bool
    var isSystem: Bool

    init(ip: String, hostnames: [String], desc: String = "", isEnabled: Bool = true, isSystem: Bool = false) {
        self.ip = ip
        self.hostnames = hostnames
        self.desc = desc
        self.isEnabled = isEnabled
        self.isSystem = isSystem
    }
}

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

/// Combines profile-managed entries with valid entries from the live system
/// file. Profile hostnames always win; unowned entries are retained as an
/// external layer and are never imported into Core Data.
nonisolated enum HostsContentMerger {
    static func merge(
        liveContent: String,
        managedEntries: [ParsedHostEntry],
        ownedHostnames: Set<String>
    ) -> String {
        let reserved = Set(
            ownedHostnames.map { $0.lowercased() }
                + HostsParser.systemNames.map { $0.lowercased() }
        )
        let external = HostsParser.parse(liveContent).compactMap { entry -> ParsedHostEntry? in
            let externalHostnames = entry.hostnames.filter {
                !reserved.contains($0.lowercased())
            }
            guard !externalHostnames.isEmpty else { return nil }
            var result = entry
            result.hostnames = externalHostnames
            return result
        }
        return HostsParser.mergedContent(
            entries: managedEntries,
            externalEntries: external
        )
    }
}

// MARK: - Conflict detection

enum HostValidator {
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

nonisolated struct HostsReconciliationBaseline: Equatable {
    let fingerprint: String
    let appliedProfileIDs: [UUID]
    let pendingAppliedProfileIDs: [UUID]?
    let managedHostnames: [String]
    let stateCommitFailed: Bool
}

nonisolated enum HostsReconciliationBaselineStore {
    private static let fingerprintKey = "hostsReconciliation.fingerprint"
    private static let appliedProfileIDsKey = "hostsReconciliation.appliedProfileIDs"
    private static let pendingAppliedProfileIDsKey = "hostsReconciliation.pendingAppliedProfileIDs"
    private static let managedHostnamesKey = "hostsReconciliation.managedHostnames"
    private static let stateCommitFailedKey = "hostsReconciliation.stateCommitFailed"

    static func load(from defaults: UserDefaults = .standard) -> HostsReconciliationBaseline? {
        guard let fingerprint = defaults.string(forKey: fingerprintKey) else {
            return nil
        }
        let rawIDs = defaults.stringArray(forKey: appliedProfileIDsKey) ?? []
        let pendingRawIDs = defaults.object(forKey: pendingAppliedProfileIDsKey) as? [String]
        return HostsReconciliationBaseline(
            fingerprint: fingerprint,
            appliedProfileIDs: rawIDs.compactMap(UUID.init(uuidString:)),
            pendingAppliedProfileIDs: pendingRawIDs?.compactMap(UUID.init(uuidString:)),
            managedHostnames: defaults.stringArray(forKey: managedHostnamesKey) ?? [],
            stateCommitFailed: defaults.bool(forKey: stateCommitFailedKey)
        )
    }

    static func save(
        _ baseline: HostsReconciliationBaseline,
        to defaults: UserDefaults = .standard
    ) {
        write(baseline, to: defaults)
        defaults.synchronize()
    }

    private static func write(
        _ baseline: HostsReconciliationBaseline,
        to defaults: UserDefaults
    ) {
        defaults.set(baseline.fingerprint, forKey: fingerprintKey)
        defaults.set(
            baseline.appliedProfileIDs.map(\.uuidString),
            forKey: appliedProfileIDsKey
        )
        if let pending = baseline.pendingAppliedProfileIDs {
            defaults.set(
                pending.map(\.uuidString),
                forKey: pendingAppliedProfileIDsKey
            )
        } else {
            defaults.removeObject(forKey: pendingAppliedProfileIDsKey)
        }
        defaults.set(
            baseline.managedHostnames,
            forKey: managedHostnamesKey
        )
        defaults.set(baseline.stateCommitFailed, forKey: stateCommitFailedKey)
    }

    /// Persist the intended selection before touching the system file. If the
    /// process crashes between the file write and the Core Data save, launch
    /// reconciliation can still restore the exact selection that was written.
    static func setPendingAppliedProfileIDs(
        _ profileIDs: [UUID],
        from defaults: UserDefaults = .standard
    ) {
        defaults.set(
            profileIDs.map(\.uuidString),
            forKey: pendingAppliedProfileIDsKey
        )
    }

    /// Record the exact file/state selection immediately after the system file
    /// changes and before Core Data is saved.
    static func markPendingWrite(
        fingerprint: String,
        appliedProfileIDs: [UUID],
        managedHostnames: [String],
        from defaults: UserDefaults = .standard
    ) {
        save(
            HostsReconciliationBaseline(
                fingerprint: fingerprint,
                appliedProfileIDs: appliedProfileIDs,
                pendingAppliedProfileIDs: appliedProfileIDs,
                managedHostnames: managedHostnames,
                stateCommitFailed: true
            ),
            to: defaults
        )
    }

    static func clearPendingAppliedProfileIDs(
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: pendingAppliedProfileIDsKey)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: fingerprintKey)
        defaults.removeObject(forKey: appliedProfileIDsKey)
        defaults.removeObject(forKey: pendingAppliedProfileIDsKey)
        defaults.removeObject(forKey: managedHostnamesKey)
        defaults.removeObject(forKey: stateCommitFailedKey)
    }
}

nonisolated enum HostsReconciliation {
    static func canonical(_ content: String) -> String {
        var mappings = Set<String>()
        for entry in HostsParser.parse(content) where entry.isEnabled {
            for hostname in entry.hostnames {
                mappings.insert("\(entry.ip)|\(hostname.lowercased())")
            }
        }
        return mappings.sorted().joined(separator: "\n")
    }
}

nonisolated enum HostIssueKind: Equatable { case conflict, duplicate }

struct HostIssue: Identifiable {
    let id = UUID()
    let hostname: String
    let kind: HostIssueKind
    let count: Int
}

// MARK: - Backups

enum BackupManager {
    static var backupsDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("hosts-manager/Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func createBackup(of content: String, in directory: URL? = nil) throws -> URL {
        let dir = directory ?? backupsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "hosts-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4)).hosts"
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func listBackups(in directory: URL? = nil) -> [URL] {
        let dir = directory ?? backupsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "hosts" }
            .sorted { ($0.fileModificationDate ?? .distantPast) > ($1.fileModificationDate ?? .distantPast) }
    }

    static func prune(
        keeping count: Int,
        in directory: URL? = nil,
        excluding protectedPaths: Set<String> = []
    ) {
        let backups = listBackups(in: directory)
        let normalizedProtectedPaths = Set(
            protectedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
        let candidates = backups.filter {
            !normalizedProtectedPaths.contains($0.standardizedFileURL.path)
        }
        guard count >= 0, candidates.count > count else { return }
        for url in candidates.dropFirst(count) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private extension URL {
    var fileModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

// MARK: - Privileged write via Authorization Services

enum HostsWriteError: LocalizedError {
    case invalidContent(String)
    case authorizationFailed
    case helperUnavailable
    case writeFailed
    case readFailed
    case verificationFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .invalidContent(message): return message
        case .authorizationFailed: return "Unable to establish administrator authorization."
        case .helperUnavailable: return "The background writer helper is unavailable. Enable and approve it in Settings."
        case .writeFailed: return "Failed to write /etc/hosts."
        case .readFailed: return "Unable to read /etc/hosts."
        case .verificationFailed: return "Verification failed after writing /etc/hosts."
        case .timedOut: return "The background writer helper timed out."
        }
    }
}

enum HostsWriter {
    static let hostsPath = "/etc/hosts"

    static func readContent() throws -> String {
        do {
            return try String(contentsOfFile: hostsPath, encoding: .utf8)
        } catch {
            throw HostsWriteError.readFailed
        }
    }

    static func currentContent() -> String {
        (try? readContent()) ?? ""
    }

    /// Write the given content to /etc/hosts with elevated privileges.
    /// Writes through the privileged LaunchDaemon helper exclusively (silent,
    /// app-attributed). No admin-password prompt is used.
    static func write(_ content: String) async throws {
        if let validationError = HostsValueValidator.validate(content: content) {
            throw HostsWriteError.invalidContent(validationError)
        }

        HostsHelperClient.registerIfNeeded()
        guard HostsHelperClient.isRegistered else {
            throw HostsWriteError.helperUnavailable
        }
        guard await HostsHelperClient.ensureResponding() else {
            throw HostsWriteError.helperUnavailable
        }
        switch await HostsHelperClient.write(content) {
        case .success:
            return
        case .invalidContent:
            throw HostsWriteError.invalidContent("The helper rejected the hosts content.")
        case .writeFailed:
            throw HostsWriteError.writeFailed
        case .unauthorized:
            throw HostsWriteError.authorizationFailed
        case .unavailable:
            throw HostsWriteError.helperUnavailable
        case .timedOut:
            throw HostsWriteError.timedOut
        }
    }
}

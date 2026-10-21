import Foundation

// MARK: - Parsed host entry

struct ParsedHostEntry: Identifiable, Equatable {
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

enum HostsParser {
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

    /// Merge a profile's enabled entries with the always-present system entries.
    static func mergedContent(entries: [ParsedHostEntry]) -> String {
        var lines: [String] = ["# Managed by Hosts Manager — do not edit by hand", ""]
        lines.append("# --- System ---")
        lines.append("")
        for entry in systemDefaults { lines.append(line(for: entry)) }
        lines.append("")
        lines.append("# --- User ---")
        // Everything user-authored goes into the User section; entries whose
        // hostname is localhost/broadcasthost are covered by System above.
        let user = entries.filter { $0.isEnabled && !$0.hostnames.contains { systemNames.contains($0.lowercased()) } }
        for entry in dedupe(user) { lines.append(line(for: entry)) }
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

    static func prune(keeping count: Int, in directory: URL? = nil) {
        let backups = listBackups(in: directory)
        guard count >= 0, backups.count > count else { return }
        for url in backups.dropFirst(count) {
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
    case denied
    case writeFailed
    case readFailed
    case verificationFailed
    case timedOut
    case alreadyInProgress

    var errorDescription: String? {
        switch self {
        case let .invalidContent(message): return message
        case .authorizationFailed: return "无法建立管理员授权"
        case .denied: return "已取消或拒绝管理员授权"
        case .writeFailed: return "写入 /etc/hosts 失败"
        case .readFailed: return "无法读取 /etc/hosts"
        case .verificationFailed: return "写入后校验失败"
        case .timedOut: return "特权助手响应超时"
        case .alreadyInProgress: return "已有写入任务正在进行"
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
    /// Tries the privileged LaunchDaemon helper first (silent, app-attributed),
    /// falling back to an `osascript` admin-password prompt when unavailable.
    static func write(_ content: String) async throws {
        if let validationError = HostsValueValidator.validate(content: content) {
            throw HostsWriteError.invalidContent(validationError)
        }

        HostsHelperClient.registerIfNeeded()
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
            try writeViaOsascript(content)
        case .timedOut:
            throw HostsWriteError.timedOut
        }
    }

    private static func writeViaOsascript(_ content: String) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("hosts-\(UUID().uuidString).tmp")
        try content.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let staged = "/etc/.hosts-manager-\(UUID().uuidString).tmp"
        let quotedSource = "'\(temp.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        let quotedStaged = "'\(staged)'"
        let command = "/usr/bin/install -m 644 -o root -g wheel \(quotedSource) \(quotedStaged) && /bin/mv -f \(quotedStaged) \(hostsPath)"
        let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedCommand)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw process.terminationStatus == -128 ? HostsWriteError.denied : HostsWriteError.writeFailed
        }
    }
}

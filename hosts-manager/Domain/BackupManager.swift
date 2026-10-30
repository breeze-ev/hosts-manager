import Foundation

// MARK: - Backups

nonisolated enum BackupManager {
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
    nonisolated var fileModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

import CoreData
import Foundation

@MainActor
enum BackupMaintenance {
    static func prune(
        context: NSManagedObjectContext,
        backupsDirectory: URL? = nil
    ) throws {
        let retention = max(
            1,
            Int(try context.fetch(AppSettings.fetchRequest()).first?.backupRetention ?? 30)
        )

        // A record without its backing file cannot be restored. Remove it first
        // so later retention selection only considers valid backups.
        let records = try context.fetch(BackupRecord.fetchRequest())
        for record in records where !FileManager.default.fileExists(
            atPath: record.filePath ?? ""
        ) {
            context.delete(record)
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }

        let request = BackupRecord.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BackupRecord.timestamp, ascending: false)
        ]
        let validRecords = try context.fetch(request)
        let staleRecords = Array(validRecords.dropFirst(retention))
        let stalePaths = staleRecords.compactMap(\.filePath)
        guard !staleRecords.isEmpty else { return }

        for record in staleRecords {
            context.delete(record)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        // Metadata is committed first. A failed file removal leaves an orphan
        // that is cleaned on a later maintenance pass instead of a dangling record.
        for path in stalePaths {
            try? FileManager.default.removeItem(atPath: path)
        }

        let retainedPaths = Set(
            try context.fetch(BackupRecord.fetchRequest())
                .compactMap(\.filePath)
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
        BackupManager.prune(
            keeping: retention,
            in: backupsDirectory,
            excluding: retainedPaths
        )
    }
}

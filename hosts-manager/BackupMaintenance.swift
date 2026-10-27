import CoreData
import Foundation

@MainActor
enum BackupMaintenance {
    static func prune(context: NSManagedObjectContext) throws {
        let retention = try context.fetch(AppSettings.fetchRequest()).first?.backupRetention ?? 30

        // Remove orphan records before pruning files. The old order removed
        // files first and could leave committed records pointing at deleted files.
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

        let retainedPaths = Set(
            try context.fetch(BackupRecord.fetchRequest())
                .compactMap(\.filePath)
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )
        BackupManager.prune(
            keeping: max(1, Int(retention)),
            excluding: retainedPaths
        )
    }
}

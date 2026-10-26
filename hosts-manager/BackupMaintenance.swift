import CoreData
import Foundation

@MainActor
enum BackupMaintenance {
    static func prune(context: NSManagedObjectContext) throws {
        let retention = try context.fetch(AppSettings.fetchRequest()).first?.backupRetention ?? 30

        // File retention runs first so records never point at files removed by
        // this pass. Any orphan records are then removed in a rollback-safe save.
        BackupManager.prune(keeping: max(1, Int(retention)))

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
    }
}

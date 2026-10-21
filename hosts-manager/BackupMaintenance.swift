import CoreData
import Foundation

@MainActor
enum BackupMaintenance {
    static func prune(context: NSManagedObjectContext) throws {
        let retention = try context.fetch(AppSettings.fetchRequest()).first?.backupRetention ?? 30
        BackupManager.prune(keeping: max(1, Int(retention)))

        let records = try context.fetch(BackupRecord.fetchRequest())
        for record in records {
            guard let path = record.filePath,
                  FileManager.default.fileExists(atPath: path) else {
                context.delete(record)
                continue
            }
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

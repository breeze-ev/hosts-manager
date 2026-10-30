import CoreData
import Foundation
import Testing
@testable import hosts_manager

@MainActor
struct BackupMaintenanceTests {
    @Test func retentionPrunesRecordsAndTheirFiles() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let settings = try #require(try context.fetch(AppSettings.fetchRequest()).first)
        settings.backupRetention = 2

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<3 {
            let fileURL = try BackupManager.createBackup(
                of: "content-\(index)",
                in: directory
            )
            let record = BackupRecord(context: context)
            record.id = UUID()
            record.timestamp = Date(timeIntervalSince1970: TimeInterval(index))
            record.filePath = fileURL.path
            record.note = "test"
        }
        try context.save()

        try BackupMaintenance.prune(
            context: context,
            backupsDirectory: directory
        )

        let records = try context.fetch(BackupRecord.fetchRequest())
        #expect(records.count == 2)
        #expect(BackupManager.listBackups(in: directory).count == 2)
    }
}

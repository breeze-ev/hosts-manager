import CoreData
import Foundation

@objc(BackupRecord)
class BackupRecord: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var timestamp: Date?
    @NSManaged var filePath: String?
    @NSManaged var profileName: String?
    @NSManaged var note: String?
}

extension BackupRecord: Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BackupRecord> {
        NSFetchRequest<BackupRecord>(entityName: "BackupRecord")
    }
}

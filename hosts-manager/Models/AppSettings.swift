import CoreData
import Foundation

@objc(AppSettings)
class AppSettings: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var backupRetention: Int64
    @NSManaged var defaultProfileID: UUID?
    @NSManaged var defaultView: String?
}

extension AppSettings: Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppSettings> {
        NSFetchRequest<AppSettings>(entityName: "AppSettings")
    }
}

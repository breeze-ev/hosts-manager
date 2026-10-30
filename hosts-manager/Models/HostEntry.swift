import CoreData
import Foundation

@objc(HostEntry)
class HostEntry: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var ip: String?
    @NSManaged var hostnames: [String]?
    @NSManaged var desc: String?
    @NSManaged var isEnabled: Bool
    @NSManaged var isSystem: Bool
    @NSManaged var sortIndex: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var profile: Profile?

    var hostList: [String] {
        hostnames ?? []
    }
}

extension HostEntry: Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<HostEntry> {
        NSFetchRequest<HostEntry>(entityName: "HostEntry")
    }
}

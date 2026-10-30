import CoreData
import Foundation

@objc(Profile)
class Profile: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    /// Canonical applied state. `isEnabled` is kept only as a compatibility mirror.
    @NSManaged var isActive: Bool
    @NSManaged var isSystem: Bool
    @NSManaged var isEnabled: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var lastActivatedAt: Date?
    @NSManaged var hostEntries: NSSet?

    var sortedEntries: [HostEntry] {
        let set = hostEntries as? Set<HostEntry> ?? []
        return set.sorted {
            ($0.sortIndex, $0.createdAt ?? .distantPast)
                < ($1.sortIndex, $1.createdAt ?? .distantPast)
        }
    }
}

extension Profile: Identifiable {
    func setApplied(_ applied: Bool) {
        isActive = applied
        isEnabled = applied
    }

    func synchronizeAppliedMirror() {
        isEnabled = isActive
    }

    var isAppliedForSystem: Bool {
        isActive && isEnabled
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Profile> {
        NSFetchRequest<Profile>(entityName: "Profile")
    }
}

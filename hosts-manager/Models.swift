import CoreData
import Foundation

@objc(Profile)
public class Profile: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var isSystem: Bool
    @NSManaged public var isEnabled: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var hostEntries: NSSet?

    var sortedEntries: [HostEntry] {
        let set = hostEntries as? Set<HostEntry> ?? []
        return set.sorted { ($0.sortIndex, $0.createdAt ?? .distantPast) < ($1.sortIndex, $1.createdAt ?? .distantPast) }
    }
}

@objc(HostEntry)
public class HostEntry: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var ip: String?
    @NSManaged public var hostnames: [String]?
    @NSManaged public var desc: String?
    @NSManaged public var isEnabled: Bool
    @NSManaged public var isSystem: Bool
    @NSManaged public var sortIndex: Int64
    @NSManaged public var createdAt: Date?
    @NSManaged public var profile: Profile?

    var hostList: [String] { hostnames ?? [] }
}

@objc(BackupRecord)
public class BackupRecord: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var filePath: String?
    @NSManaged public var profileName: String?
    @NSManaged public var note: String?
}

@objc(AppSettings)
public class AppSettings: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var backupRetention: Int64
    @NSManaged public var defaultProfileID: UUID?
    @NSManaged public var defaultView: String?
}

extension Profile {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Profile> {
        NSFetchRequest<Profile>(entityName: "Profile")
    }
}

extension HostEntry {
    @nonobjc class func fetchRequest() -> NSFetchRequest<HostEntry> {
        NSFetchRequest<HostEntry>(entityName: "HostEntry")
    }
}

extension BackupRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BackupRecord> {
        NSFetchRequest<BackupRecord>(entityName: "BackupRecord")
    }
}

extension AppSettings {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppSettings> {
        NSFetchRequest<AppSettings>(entityName: "AppSettings")
    }
}

extension Profile: Identifiable {}
extension HostEntry: Identifiable {}
extension BackupRecord: Identifiable {}
extension AppSettings: Identifiable {}

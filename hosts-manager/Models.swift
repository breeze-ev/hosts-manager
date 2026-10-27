import CoreData
import Foundation

@objc(Profile)
public class Profile: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    /// Canonical applied state. `isEnabled` is retained only as a compatibility mirror.
    @NSManaged public var isActive: Bool
    @NSManaged public var isSystem: Bool
    /// Compatibility mirror of `isActive`; use `setApplied(_:)` to keep both in sync.
    @NSManaged public var isEnabled: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var lastActivatedAt: Date?
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

@MainActor
func clearAppliedStateForUserProfiles(in context: NSManagedObjectContext) throws {
    let profiles = try context.fetch(Profile.fetchRequest())
    let now = Date()
    for profile in profiles where !profile.isSystem {
        profile.setApplied(false)
        profile.updatedAt = now
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

extension Profile {
    func localizedName(isEnglish: Bool) -> String {
        if isSystem {
            return localizedProfileName("系统", isEnglish: isEnglish)
        }
        return localizedProfileName(name, isEnglish: isEnglish)
    }
}

func localizedProfileName(_ name: String?, isEnglish: Bool) -> String {
    guard let name, !name.isEmpty else { return "" }

    switch name {
    case "系统", "System":
        return isEnglish ? "System" : "系统"
    case "默认", "Default":
        return isEnglish ? "Default" : "默认"
    case "新配置", "New Profile":
        return isEnglish ? "New Profile" : "新配置"
    default:
        break
    }

    if isEnglish, name.hasSuffix(" 副本") {
        let base = String(name.dropLast(3))
        return localizedProfileName(base, isEnglish: true) + " Copy"
    }
    if !isEnglish, name.hasSuffix(" Copy") {
        let base = String(name.dropLast(5))
        return localizedProfileName(base, isEnglish: false) + " 副本"
    }
    if isEnglish, name.hasPrefix("导入 ") {
        return "Imported " + name.dropFirst(3)
    }
    if !isEnglish, name.hasPrefix("Imported ") {
        return "导入 " + name.dropFirst(9)
    }
    if isEnglish, name.hasPrefix("从备份恢复 ") {
        return "Restored from backup " + name.dropFirst(6)
    }
    if !isEnglish, name.hasPrefix("Restored from backup ") {
        return "从备份恢复 " + name.dropFirst(21)
    }
    return name
}

func localizedSeedDescription(_ desc: String?, isEnglish: Bool) -> String {
    switch desc {
    case "本地 API 服务", "Local API service":
        return isEnglish ? "Local API service" : "本地 API 服务"
    case "开发数据库", "Development database":
        return isEnglish ? "Development database" : "开发数据库"
    default:
        return desc ?? ""
    }
}

func localizedSourceText(for profile: Profile, isEnglish: Bool) -> String {
    HostsParser.serialize(profile.sortedEntries.map {
        ParsedHostEntry(
            ip: $0.ip ?? "",
            hostnames: $0.hostList,
            desc: localizedSeedDescription($0.desc, isEnglish: isEnglish),
            isEnabled: $0.isEnabled,
            isSystem: $0.isSystem
        )
    })
}

func localizedBackupNote(_ note: String?, isEnglish: Bool) -> String {
    guard let note, !note.isEmpty else { return "" }

    switch note {
    case "启用配置前自动备份", "Auto backup before enabling profile":
        return isEnglish ? "Auto backup before enabling profile" : "启用配置前自动备份"
    case "停用当前配置前自动备份", "Auto backup before disabling the active profile":
        return isEnglish ? "Auto backup before disabling the active profile" : "停用当前配置前自动备份"
    case "列表编辑后实时应用", "Real-time apply after list edit":
        return isEnglish ? "Real-time apply after list edit" : "列表编辑后实时应用"
    case "还原备份前自动备份", "Auto backup before restore":
        return isEnglish ? "Auto backup before restore" : "还原备份前自动备份"
    default:
        break
    }

    if isEnglish, note.hasPrefix("应用“"), note.hasSuffix("”前自动备份") {
        let name = String(note.dropFirst(3).dropLast(6))
        return "Auto backup before applying “\(localizedProfileName(name, isEnglish: true))”"
    }
    if !isEnglish, note.hasPrefix("Auto backup before applying “"), note.hasSuffix("”") {
        let name = String(note.dropFirst(29).dropLast(1))
        return "应用“\(localizedProfileName(name, isEnglish: false))”前自动备份"
    }
    if isEnglish, note.hasPrefix("导入 ") {
        return "Imported " + note.dropFirst(3)
    }
    if !isEnglish, note.hasPrefix("Imported ") {
        return "导入 " + note.dropFirst(9)
    }
    if isEnglish, note.hasPrefix("从备份恢复 ") {
        return "Restored from backup " + note.dropFirst(6)
    }
    if !isEnglish, note.hasPrefix("Restored from backup ") {
        return "从备份恢复 " + note.dropFirst(21)
    }
    return note
}

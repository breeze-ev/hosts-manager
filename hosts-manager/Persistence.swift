import Combine
import CoreData

/// Programmatic Core Data model for the hosts manager.
/// Built in code instead of an `.xcdatamodeld` to keep entity wiring explicit.
@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()

    var container: NSPersistentContainer
    @Published private(set) var loadError: String?

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "hosts_manager", managedObjectModel: Self.model)
        loadError = nil
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        loadError = loadStores()
    }

    func retryLoad() {
        loadError = loadStores()
    }

    func resetStore() {
        let urls = [
            persistentStoreURL,
            persistentStoreURL.appendingPathExtension("wal"),
            persistentStoreURL.appendingPathExtension("shm")
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        container = NSPersistentContainer(name: "hosts_manager", managedObjectModel: Self.model)
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        container.viewContext.automaticallyMergesChangesFromParent = true
        loadError = loadStores()
    }

    var storeDirectoryURL: URL {
        persistentStoreURL.deletingLastPathComponent()
    }

    private var persistentStoreURL: URL {
        container.persistentStoreDescriptions.first?.url
            ?? NSPersistentContainer.defaultDirectoryURL()
                .appendingPathComponent("hosts_manager.sqlite")
    }

    private func loadStores() -> String? {
        var storeError: Error?
        container.loadPersistentStores { _, error in
            storeError = error
        }
        if let storeError {
            return storeError.localizedDescription
        }
        do {
            try ensureDefaults()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Migrate an existing store (or seed a fresh one) so there is exactly one
    /// read-only "系统" profile plus at least one editable custom profile.
    func ensureDefaults() throws {
        let context = container.viewContext
        let all = try context.fetch(Profile.fetchRequest())

        if all.isEmpty {
            try seed()
            return
        }

        if let system = all.first(where: { $0.name == "系统" }) {
            system.isSystem = true
            system.setApplied(false)
            for entry in system.sortedEntries { context.delete(entry) }
        } else {
            let system = Profile(context: context)
            system.id = UUID()
            system.name = "系统"
            system.setApplied(false)
            system.isSystem = true
            system.createdAt = Date()
            system.updatedAt = Date()
        }

        if all.filter({ !$0.isSystem }).isEmpty {
            let profile = Profile(context: context)
            profile.id = UUID()
            profile.name = "默认"
            profile.setApplied(true)
            profile.isSystem = false
            profile.lastActivatedAt = Date()
            profile.createdAt = Date()
            profile.updatedAt = Date()
        }

        if try context.count(for: AppSettings.fetchRequest()) == 0 {
            let settings = AppSettings(context: context)
            settings.id = UUID()
            settings.backupRetention = 30
            settings.defaultView = "list"
        } else if let settings = try context.fetch(AppSettings.fetchRequest()).first {
            if settings.defaultView == nil {
                settings.defaultView = "list"
            }
        }
        // Repair any entries that were previously mis-flagged as system.
        for profile in try context.fetch(Profile.fetchRequest()) {
            for entry in profile.sortedEntries {
                let isSys = entry.hostList.contains { HostsParser.systemNames.contains($0.lowercased()) }
                if entry.isSystem != isSys { entry.isSystem = isSys }
            }
        }
        // Backfill activation timestamps so older stores can still pick the
        // most recently activated profile on launch.
        for profile in all where profile.isAppliedForSystem && profile.lastActivatedAt == nil {
            profile.lastActivatedAt = profile.updatedAt ?? profile.createdAt
        }
        // 统一状态：开关（isEnabled）表示“该配置已写入 /etc/hosts”，必须与
        // isActive 一致。旧版本把新建 / 导入 / 复制出来的配置标成 isEnabled = true
        // 却从未写入，导致开关显示“已生效”但系统里没有内容；这里以实际写入状态为准
        // 把开关关掉（条目不会丢失，重新打开开关即可写入）。
        for profile in all where !profile.isSystem && profile.isEnabled != profile.isActive {
            profile.synchronizeAppliedMirror()
        }
        try context.save()
    }

    func seed() throws {
        let context = container.viewContext
        guard try context.count(for: Profile.fetchRequest()) == 0 else { return }

        // Read-only system profile: always shows the live /etc/hosts.
        let systemProfile = Profile(context: context)
        systemProfile.id = UUID()
        systemProfile.name = "系统"
        systemProfile.setApplied(false)
        systemProfile.isSystem = true
        systemProfile.createdAt = Date()
        systemProfile.updatedAt = Date()

        // Editable default custom profile.
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = "默认"
        profile.setApplied(true)
        profile.isSystem = false
        profile.lastActivatedAt = Date()
        profile.createdAt = Date()
        profile.updatedAt = Date()

        // Import the real non-system entries from /etc/hosts into the first custom profile.
        let userEntries = HostsParser.parse(HostsWriter.currentContent()).filter { !$0.isSystem }
        if userEntries.isEmpty {
            // Default entries are created disabled: they are not present in the
            // system hosts file and must not be written until the user enables them.
            addEntry(to: profile, ip: "127.0.0.1", hosts: ["api.dev.local"], desc: "Local API service", enabled: false, system: false)
            addEntry(to: profile, ip: "192.168.1.50", hosts: ["mysql.db.local"], desc: "Development database", enabled: false, system: false)
        } else {
            for item in userEntries {
                addEntry(to: profile, ip: item.ip, hosts: item.hostnames, desc: item.desc, enabled: item.isEnabled, system: false)
            }
        }

        let settings = AppSettings(context: context)
        settings.id = UUID()
        settings.backupRetention = 30
        settings.defaultView = "list"

        try context.save()
    }

    private func addEntry(to profile: Profile, ip: String, hosts: [String], desc: String, enabled: Bool, system: Bool) {
        let entry = HostEntry(context: container.viewContext)
        entry.id = UUID()
        entry.profile = profile
        entry.ip = ip
        entry.hostnames = hosts
        entry.desc = desc
        entry.isEnabled = enabled
        entry.isSystem = system
        entry.sortIndex = Int64(profile.hostEntries?.count ?? 0)
        entry.createdAt = Date()
    }

    /// Programmatically declared entities: Profile, HostEntry, BackupRecord, AppSettings.
    static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let profile = entity("Profile", className: Profile.self)
        profile.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("name", .stringAttributeType),
            attribute("isActive", .booleanAttributeType, defaultValue: false),
            attribute("isSystem", .booleanAttributeType, defaultValue: false),
            attribute("isEnabled", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("lastActivatedAt", .dateAttributeType)
        ]

        let entry = entity("HostEntry", className: HostEntry.self)
        let hostnames = NSAttributeDescription()
        hostnames.name = "hostnames"
        hostnames.attributeType = .transformableAttributeType
        hostnames.attributeValueClassName = "Swift.Array<Swift.String>"
        hostnames.isOptional = false
        entry.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            hostnames,
            attribute("ip", .stringAttributeType),
            attribute("desc", .stringAttributeType),
            attribute("isEnabled", .booleanAttributeType, defaultValue: true),
            attribute("isSystem", .booleanAttributeType, defaultValue: false),
            attribute("sortIndex", .integer64AttributeType, defaultValue: 0),
            attribute("createdAt", .dateAttributeType)
        ]

        let backup = entity("BackupRecord", className: BackupRecord.self)
        backup.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("timestamp", .dateAttributeType),
            attribute("filePath", .stringAttributeType),
            attribute("profileName", .stringAttributeType),
            attribute("note", .stringAttributeType)
        ]

        let settings = entity("AppSettings", className: AppSettings.self)
        settings.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("backupRetention", .integer64AttributeType, defaultValue: 30),
            attribute("defaultProfileID", .UUIDAttributeType),
            attribute("defaultView", .stringAttributeType, defaultValue: "list")
        ]

        let entries = NSRelationshipDescription()
        entries.name = "hostEntries"
        entries.destinationEntity = entry
        entries.deleteRule = .cascadeDeleteRule
        entries.isOptional = true
        entries.minCount = 0
        entries.maxCount = 0

        let belongsTo = NSRelationshipDescription()
        belongsTo.name = "profile"
        belongsTo.destinationEntity = profile
        belongsTo.deleteRule = .nullifyDeleteRule
        belongsTo.isOptional = true
        belongsTo.minCount = 0
        belongsTo.maxCount = 1

        entries.inverseRelationship = belongsTo
        belongsTo.inverseRelationship = entries
        profile.properties.append(entries)
        entry.properties.append(belongsTo)

        model.entities = [profile, entry, backup, settings]
        return model
    }()

    private static func entity<T: NSManagedObject>(_ name: String, className: T.Type) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(className)
        return entity
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true, defaultValue: Any? = nil) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        if let value = defaultValue { attr.defaultValue = value }
        return attr
    }
}

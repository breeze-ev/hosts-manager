import CoreData
import Foundation

@MainActor
enum PreviewFixtures {
    static var context: NSManagedObjectContext {
        PersistenceController.preview.container.viewContext
    }

    static var systemProfile: Profile {
        let profiles = (try? context.fetch(Profile.fetchRequest())) ?? []
        if let system = profiles.first(where: \.isSystem) {
            return system
        }

        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = "系统"
        profile.setApplied(false)
        profile.isSystem = true
        profile.createdAt = Date()
        profile.updatedAt = Date()
        try? context.save()
        return profile
    }

    static var userProfile: Profile {
        let request = Profile.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "预览配置")
        if let profile = try? context.fetch(request).first {
            return profile
        }

        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = "预览配置"
        profile.setApplied(false)
        profile.isSystem = false
        profile.createdAt = Date()
        profile.updatedAt = Date()

        addEntry(
            to: profile,
            ip: "127.0.0.1",
            hostnames: ["api.dev.local", "admin.dev.local"],
            description: "本地 API 服务",
            enabled: true,
            sortIndex: 0
        )
        addEntry(
            to: profile,
            ip: "192.168.1.50",
            hostnames: ["mysql.db.local"],
            description: "开发数据库",
            enabled: true,
            sortIndex: 1
        )
        addEntry(
            to: profile,
            ip: "10.0.0.8",
            hostnames: ["metrics.internal", "grafana.internal"],
            description: "Monitoring",
            enabled: false,
            sortIndex: 2
        )
        try? context.save()
        return profile
    }

    static var entry: HostEntry {
        userProfile.sortedEntries.first ?? {
            let entry = HostEntry(context: context)
            entry.id = UUID()
            entry.profile = userProfile
            entry.ip = "127.0.0.1"
            entry.hostnames = ["api.dev.local"]
            entry.desc = "本地 API 服务"
            entry.isEnabled = true
            entry.isSystem = false
            entry.sortIndex = 0
            entry.createdAt = Date()
            return entry
        }()
    }

    static var backup: BackupRecord {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hosts-manager-preview.hosts")
        let content = """
        127.0.0.1 localhost
        255.255.255.255 broadcasthost
        ::1 localhost

        127.0.0.1 api.dev.local admin.dev.local
        192.168.1.50 mysql.db.local
        """
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        let request = BackupRecord.fetchRequest()
        request.predicate = NSPredicate(format: "filePath == %@", fileURL.path)
        if let record = try? context.fetch(request).first {
            record.timestamp = Date()
            record.profileName = "预览配置"
            record.note = "列表编辑后实时应用"
            return record
        }

        let record = BackupRecord(context: context)
        record.id = UUID()
        record.timestamp = Date()
        record.filePath = fileURL.path
        record.profileName = "预览配置"
        record.note = "列表编辑后实时应用"
        try? context.save()
        return record
    }

    private static func addEntry(
        to profile: Profile,
        ip: String,
        hostnames: [String],
        description: String,
        enabled: Bool,
        sortIndex: Int64
    ) {
        let entry = HostEntry(context: context)
        entry.id = UUID()
        entry.profile = profile
        entry.ip = ip
        entry.hostnames = hostnames
        entry.desc = description
        entry.isEnabled = enabled
        entry.isSystem = false
        entry.sortIndex = sortIndex
        entry.createdAt = Date()
    }
}

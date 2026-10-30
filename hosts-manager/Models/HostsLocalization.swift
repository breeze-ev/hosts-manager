import CoreData
import Foundation

extension Profile {
    func localizedName(isEnglish: Bool) -> String {
        if isSystem {
            return localizedProfileName("系统", isEnglish: isEnglish)
        }
        // Only the seeded default profile gets a localized alias. A user-created
        // profile with the same text must keep exactly what the user entered.
        if let profileID = id,
           ["默认", "Default"].contains(name),
           let context = managedObjectContext,
           let settings = try? context.fetch(AppSettings.fetchRequest()).first,
           settings.defaultProfileID == profileID {
            return localizedProfileName(name, isEnglish: isEnglish)
        }
        return name ?? ""
    }
}

nonisolated func localizedProfileName(_ name: String?, isEnglish: Bool) -> String {
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
        return localizedProfileName(String(name.dropLast(3)), isEnglish: true) + " Copy"
    }
    if !isEnglish, name.hasSuffix(" Copy") {
        return localizedProfileName(String(name.dropLast(5)), isEnglish: false) + " 副本"
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

nonisolated func localizedSeedDescription(_ desc: String?, isEnglish: Bool) -> String {
    switch desc {
    case "本地 API 服务", "Local API service":
        return isEnglish ? "Local API service" : "本地 API 服务"
    case "开发数据库", "Development database":
        return isEnglish ? "Development database" : "开发数据库"
    default:
        return desc ?? ""
    }
}

@MainActor
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

nonisolated func localizedBackupNote(_ note: String?, isEnglish: Bool) -> String {
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

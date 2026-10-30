import Foundation

func detailProfileStatusText(for profile: Profile, l10n: Localization) -> String {
    if profile.isSystem { return l10n.s("系统只读", "System") }
    if profile.isAppliedForSystem { return l10n.s("已应用", "Applied") }
    return l10n.s("未应用", "Not applied")
}

func detailProfileSubtitle(for profile: Profile, l10n: Localization) -> String {
    if profile.isSystem {
        return l10n.s("系统文件 · 只读", "System file · read-only")
    }
    let on = profile.sortedEntries.filter(\.isEnabled).count
    let off = profile.sortedEntries.count - on
    return l10n.s("\(on) 条启用 · \(off) 条停用", "\(on) enabled · \(off) disabled")
}

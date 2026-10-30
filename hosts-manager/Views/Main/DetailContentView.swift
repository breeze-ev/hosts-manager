import SwiftUI

struct DetailContentView: View {
    let selection: SidebarItem
    let selectedProfile: Profile?
    @Binding var mode: EntryMode
    @Binding var query: String
    let sourceText: (Profile) -> Binding<String>
    let isSourceDirty: (Profile) -> Bool
    let hasDraftConflict: (Profile) -> Bool
    let onApply: (Profile) -> Void
    let onDiscardDraft: (Profile) -> Void
    let isTitleBarCollapsed: Bool
    let onTitleBarScrollOffsetChange: (CGFloat) -> Void
    @EnvironmentObject private var l10n: Localization

    @ViewBuilder
    var body: some View {
        switch selection {
        case .profiles:
            if let profile = selectedProfile {
                ProfileDetailView(
                    profile: profile,
                    mode: $mode,
                    query: $query,
                    sourceText: sourceText(profile),
                    isSourceDirty: isSourceDirty(profile),
                    hasDraftConflict: hasDraftConflict(profile),
                    onApply: { onApply(profile) },
                    onDiscardDraft: { onDiscardDraft(profile) },
                    isTitleBarCollapsed: isTitleBarCollapsed,
                    onTitleBarScrollOffsetChange: onTitleBarScrollOffsetChange
                )
                .id(profile.id)
            } else {
                ContentUnavailableView(
                    l10n.s("暂无配置", "No Profiles"),
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text(l10n.s("创建一个配置开始管理 hosts。", "Create a profile to start managing hosts."))
                )
            }
        case .backups:
            BackupsView(
                isTitleBarCollapsed: isTitleBarCollapsed,
                onTitleBarScrollOffsetChange: onTitleBarScrollOffsetChange
            )
        case .settings:
            SettingsView()
        }
    }
}

#Preview("Profile Detail Content") {
    @Previewable @State var mode: EntryMode = .list
    @Previewable @State var query = ""
    @Previewable @State var sourceText = localizedSourceText(
        for: PreviewFixtures.userProfile,
        isEnglish: false
    )

    DetailContentView(
        selection: .profiles,
        selectedProfile: PreviewFixtures.userProfile,
        mode: $mode,
        query: $query,
        sourceText: { _ in $sourceText },
        isSourceDirty: { _ in false },
        hasDraftConflict: { _ in false },
        onApply: { _ in },
        onDiscardDraft: { _ in },
        isTitleBarCollapsed: false,
        onTitleBarScrollOffsetChange: { _ in }
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .frame(width: 860, height: 640)
}

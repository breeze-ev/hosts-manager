import AppKit
import Combine
import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct HostsWorkspaceView: View {
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Profile.isSystem, ascending: false),
            NSSortDescriptor(keyPath: \Profile.createdAt, ascending: true)
        ],
        animation: .default
    )
    private var profiles: FetchedResults<Profile>

    @EnvironmentObject private var l10n: Localization
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("backgroundBlurEnabled") private var backgroundBlurEnabled = false

    let workspace: HostsWorkspaceModel
    @State private var query = ""
    @State private var detailTitleBarCollapsed = false
    @State private var showHelperGuide = false

    private var profileList: [Profile] {
        Array(profiles)
    }

    private var selectedProfile: Profile? {
        workspace.selectedProfile(in: profileList)
    }

    private var navigationTitle: String {
        guard showsCompactTitleBar else { return "Hosts Manager" }
        switch workspace.selection {
        case .profiles:
            guard let profile = selectedProfile else { return "Hosts Manager" }
            return "\(profile.localizedName(isEnglish: l10n.isEnglish)) · \(detailProfileStatusText(for: profile, l10n: l10n))"
        case .backups:
            return l10n.s("备份", "Backups")
        case .settings:
            return "Hosts Manager"
        }
    }

    private var navigationSubtitle: String {
        guard showsCompactTitleBar else { return "" }
        switch workspace.selection {
        case .profiles:
            guard let profile = selectedProfile else { return "" }
            return detailProfileSubtitle(for: profile, l10n: l10n)
        case .backups:
            return l10n.s(
                "每次写入前自动生成时间戳备份，可查看并还原。",
                "Timestamped backups are created before each write. View or restore anytime."
            )
        case .settings:
            return ""
        }
    }

    private var showsCompactTitleBar: Bool {
        detailTitleBarCollapsed && workspace.selection != .settings
    }

    private var shouldShowHelperGuideOnLaunch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestDisableHelperGuide") {
            return false
        }
        if PreviewEnvironment.isRunning {
            return false
        }
        #endif
        return !HostsHelperClient.isRegistered
    }

    var body: some View {
        @Bindable var workspace = workspace

        NavigationSplitView {
            NavigationSidebarView(
                profiles: profiles,
                selection: $workspace.selection,
                selectedProfileID: selectedProfile?.id,
                pendingScrollProfileID: $workspace.pendingScrollProfileID,
                onCreate: workspace.createProfile,
                onSelect: workspace.selectProfile,
                onEnable: { workspace.enableProfile($0, in: profileList) },
                onDisable: workspace.disableActiveProfile,
                onDelete: { workspace.deleteProfile($0, in: profileList) }
            )
            .navigationSplitViewColumnWidth(min: 244, ideal: 276)
        } detail: {
            DetailContentView(
                selection: workspace.selection,
                selectedProfile: selectedProfile,
                mode: $workspace.mode,
                query: $query,
                sourceText: { workspace.sourceBinding(for: $0) },
                isSourceDirty: { profile in
                    profile.id.map { workspace.sourceDrafts[$0] != nil } ?? false
                },
                hasDraftConflict: { profile in
                    profile.id.map { workspace.conflictingDrafts.contains($0) }
                        ?? false
                },
                onApply: { profile in
                    workspace.applyProfile(profile, in: profileList)
                },
                onDiscardDraft: workspace.discardSourceDraft,
                isTitleBarCollapsed: detailTitleBarCollapsed,
                onTitleBarScrollOffsetChange: updateDetailTitleBarState
            )
        }
        .containerBackground(for: .window) {
            MainWindowBackground(isBlurEnabled: backgroundBlurEnabled)
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(navigationSubtitle)
        .toolbar {
            MainToolbarContent(
                selection: workspace.selection,
                query: $query,
                mode: $workspace.mode,
                selectedProfile: selectedProfile,
                l10n: l10n,
                onImport: importProfileFromFile,
                onDuplicate: { workspace.duplicateSelectedProfile(in: profileList) },
                onExport: exportSelectedProfile
            )
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .buttonBorderShape(.capsule)
        .sheet(
            isPresented: $workspace.showApply,
            onDismiss: { workspace.applyDraftText = nil }
        ) {
            if let profile = selectedProfile {
                ApplySheet(
                    profile: profile,
                    draftText: workspace.applyDraftText,
                    managedHostnamesBaseline: workspace.managedHostnamesBaseline
                )
            }
        }
        .sheet(isPresented: $showHelperGuide) {
            HelperGuideSheet(onClose: { showHelperGuide = false })
        }
        .modifier(OperationErrorAlert(
            title: l10n.s("操作失败", "Operation Failed"),
            error: $workspace.operationError
        ))
        .alert(
            l10n.s("配置状态保存失败", "Profile State Save Failed"),
            isPresented: $workspace.showStateRecoveryWarning
        ) {
            Button(l10n.s("保留当前系统文件", "Keep Current System File")) {
                workspace.keepCurrentHostsContent()
            }
            Button(l10n.s("重新应用配置", "Reapply Profiles")) {
                workspace.reapplyActiveProfiles()
            }
            Button(l10n.s("稍后处理", "Later"), role: .cancel) {
                workspace.showStateRecoveryWarning = false
            }
        } message: {
            Text(l10n.s(
                "/etc/hosts 已写入，但配置开关状态未能保存。为避免文件与数据库继续分叉，后续写入已暂停；请选择如何处理。",
                "/etc/hosts was written, but the profile switch state could not be saved. Further writes are paused to prevent divergence; choose how to recover."
            ))
        }
        .onAppear(perform: handleAppear)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            if HostsHelperClient.isRegistered {
                showHelperGuide = false
            }
            if !PreviewEnvironment.isRunning {
                workspace.reconcileOnLaunch()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .hostsStateReconciled)
        ) { _ in
            workspace.reconcileSystemHosts()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .hostsStateSynchronized)
        ) { notification in
            guard let content = notification.object as? String else { return }
            let appliedIDs = notification.userInfo?[
                HostsStateNotificationKey.appliedProfileIDs
            ] as? [UUID]
            let managedHostnames = notification.userInfo?[
                HostsStateNotificationKey.managedHostnames
            ] as? [String]
            workspace.noteSynchronizedHostsContent(
                content,
                appliedProfileIDs: appliedIDs,
                managedHostnames: managedHostnames
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .hostsStateNeedsReconciliation
            )
        ) { notification in
            workspace.handleStateNeedsReconciliation(notification)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openSettings)
        ) { _ in
            workspace.selection = .settings
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .performApply)
        ) { _ in
            workspace.requestApply(in: profileList)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .sourceDraftApplied)
        ) { notification in
            if let profileID = notification.object as? UUID {
                workspace.handleSourceDraftApplied(profileID)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .profileEntriesChanged)
        ) { notification in
            guard let profileID = notification.object as? UUID else { return }
            workspace.handleProfileEntriesChanged(
                for: profileID,
                skipRealtimeApply: notification.userInfo?[
                    HostsStateNotificationKey.skipRealtimeApply
                ] as? Bool == true,
                in: profileList
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .defaultEntryModeChanged)
        ) { notification in
            if let rawValue = notification.object as? String {
                workspace.mode = EntryMode(rawValue: rawValue) ?? .list
            }
        }
        .onChange(of: appearance) { _, _ in
            applyAppearance()
        }
        .onChange(of: workspace.selection) { _, _ in
            resetDetailTitleBarState()
        }
        .onChange(of: workspace.selectedProfileID) { _, _ in
            resetDetailTitleBarState()
        }
        .onChange(of: workspace.mode) { _, _ in
            resetDetailTitleBarState()
        }
    }

    private func handleAppear() {
        workspace.applyDefaultModeIfNeeded()
        if workspace.selectedProfileID == nil {
            workspace.selectedProfileID = workspace.initialProfileID(in: profileList)
        }
        if shouldShowHelperGuideOnLaunch {
            showHelperGuide = true
        }
        applyAppearance()
        if !PreviewEnvironment.isRunning {
            workspace.reconcileOnLaunch()
        }
    }

    private func updateDetailTitleBarState(for offset: CGFloat) {
        if detailTitleBarCollapsed {
            if offset <= 24 {
                detailTitleBarCollapsed = false
            }
        } else if offset >= 96 {
            detailTitleBarCollapsed = true
        }
    }

    private func resetDetailTitleBarState() {
        // Assigning an unchanged @State value during an interaction can publish
        // from inside SwiftUI's update transaction.
        if detailTitleBarCollapsed {
            detailTitleBarCollapsed = false
        }
    }

    private func applyAppearance() {
        switch appearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    private func importProfileFromFile() {
        let panel = NSOpenPanel()
        panel.title = l10n.s("从文件导入配置", "Import Profile from File")
        panel.message = l10n.s(
            "选择一个 hosts 文本文件。导入后会创建为未应用配置，不会修改系统文件。",
            "Choose a hosts text file. It will be imported as an unapplied profile without changing the system file."
        )
        panel.prompt = l10n.s("导入", "Import")
        panel.allowedContentTypes = HostsImport.allowedContentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.importProfile(from: url)
    }

    private func exportSelectedProfile() {
        guard let profile = selectedProfile, !profile.isSystem else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(profile.localizedName(isEnglish: l10n.isEnglish)).hosts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.exportSelectedProfile(to: url, in: profileList)
    }
}

#Preview("Workspace") {
    HostsWorkspaceRootView(
        context: PreviewFixtures.context,
        localization: Localization()
    )
    .environmentObject(Localization())
    .frame(minWidth: 1_000, minHeight: 680)
}

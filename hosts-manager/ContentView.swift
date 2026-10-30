import SwiftUI
import CoreData
import AppKit
import Combine
import UniformTypeIdentifiers

extension Notification.Name {
    static let openSettings = Notification.Name("hostsManager.openSettings")
    static let performApply = Notification.Name("hostsManager.performApply")
    static let sourceDraftApplied = Notification.Name("hostsManager.sourceDraftApplied")
    static let profileEntriesChanged = Notification.Name("hostsManager.profileEntriesChanged")
    static let defaultEntryModeChanged = Notification.Name("hostsManager.defaultEntryModeChanged")
    static let sourceFind = Notification.Name("hostsManager.sourceFind")
    static let sourceToggleComment = Notification.Name("hostsManager.sourceToggleComment")
    static let hostsStateReconciled = Notification.Name("hostsManager.hostsStateReconciled")
    static let hostsStateNeedsReconciliation = Notification.Name("hostsManager.hostsStateNeedsReconciliation")
    static let hostsStateSynchronized = Notification.Name("hostsManager.hostsStateSynchronized")
}

enum HostsStateNotificationKey {
    static let appliedProfileIDs = "appliedProfileIDs"
    static let managedHostnames = "managedHostnames"
    static let skipRealtimeApply = "skipRealtimeApply"
}

enum SidebarItem: String, CaseIterable, Hashable {
    case profiles, backups, settings
}

enum EntryMode: String, CaseIterable {
    case list, source
}

var isRunningInXcodePreview: Bool {
    #if DEBUG
    let environment = ProcessInfo.processInfo.environment
    return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    #else
    return false
    #endif
}

struct HostsWriteConflictError: Error {
    let profileID: UUID
}

struct HostsWriteAbortedError: Error {}

/// Commits the backup record and profile state in one Core Data transaction.
/// The hosts file has already been written when this runs. If the transaction
/// fails, roll back the in-memory changes and surface the original error so the
/// caller can report "file written, state not saved" instead of claiming the
/// write itself failed.
@MainActor
@discardableResult
func commitHostsWrite(
    result: HostsWriteResult,
    context: NSManagedObjectContext,
    profileName: String?,
    note: String,
    appliedProfileIDs: [UUID],
    checkStateIntegrity: () -> Bool = { true },
    stateChanges: () throws -> Void
) throws -> Bool {
    let record = BackupRecord(context: context)
    record.id = UUID()
    record.timestamp = Date()
    record.filePath = result.backupURL.path
    record.profileName = profileName
    record.note = note

    do {
        try stateChanges()
        guard checkStateIntegrity() else {
            throw HostsWriteStateReconciliationError()
        }
        try context.save()
    } catch {
        context.rollback()
        NotificationCenter.default.post(
            name: .hostsStateNeedsReconciliation,
            object: result.content,
            userInfo: [
                HostsStateNotificationKey.appliedProfileIDs: appliedProfileIDs
            ]
        )
        throw error
    }

    // Retention cleanup is not part of the write transaction. A cleanup
    // failure must not turn a successfully committed write into a failure.
    do {
        try BackupMaintenance.prune(context: context)
    } catch {
        // prune may have queued record deletions before its save failed.
        // Never leave those deletions to be committed by an unrelated save.
        context.rollback()
    }
    return true
}

extension View {
    func zebraRowBackground(_ index: Int) -> some View {
        // Keep the stripe as a faint tint. The system alternating colors are
        // opaque, which becomes very heavy over a translucent window.
        let color = index.isMultiple(of: 2)
            ? Color.clear
            : Color.primary.opacity(0.05)
        return listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        )
    }

    func detailHeaderScrollTracking(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            onChange(offset)
        }
    }

    func detailListSafeAreaHeader<Header: View>(
        isCollapsed: Bool,
        @ViewBuilder _ header: () -> Header
    ) -> some View {
        scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                if !isCollapsed {
                    header()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                }
            }
    }

    func editorSurface(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(.thinMaterial))
            .overlay(shape.stroke(.quaternary.opacity(0.5), lineWidth: 1))
            .clipShape(shape)
    }

    func detailCard(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(.ultraThinMaterial))
            .overlay(shape.stroke(.quaternary.opacity(0.45), lineWidth: 1))
            .clipShape(shape)
    }
}

func detailProfileStatusText(for profile: Profile, l10n: Localization) -> String {
    if profile.isSystem { return l10n.s("系统只读", "System") }
    if profile.isAppliedForSystem { return l10n.s("已应用", "Applied") }
    return l10n.s("未应用", "Not applied")
}

func detailProfileSubtitle(for profile: Profile, l10n: Localization) -> String {
    if profile.isSystem {
        let live = HostsParser.parse(HostsWriter.currentContent())
        let on = live.filter(\.isEnabled).count
        let off = live.count - on
        return l10n.s("\(on) 条启用 · \(off) 条停用", "\(on) enabled · \(off) disabled")
    }
    let on = profile.sortedEntries.filter(\.isEnabled).count
    let off = profile.sortedEntries.count - on
    return l10n.s("\(on) 条启用 · \(off) 条停用", "\(on) enabled · \(off) disabled")
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \Profile.isSystem, ascending: false),
        NSSortDescriptor(keyPath: \Profile.createdAt, ascending: true)
    ], animation: .default)
    private var profiles: FetchedResults<Profile>
    @EnvironmentObject private var l10n: Localization
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("backgroundBlurEnabled") private var backgroundBlurEnabled = false

    @State private var selection: SidebarItem = .profiles
    @State private var selectedProfileID: UUID?
    @State private var mode: EntryMode = .list
    @State private var didApplyDefaultMode = false
    @State private var showApply = false
    @State private var applyDraftText: String?
    @State private var query = ""
    @State private var detailTitleBarCollapsed = false
    @State private var sourceDrafts: [UUID: String] = [:]
    /// 源码草稿与列表内容发生冲突的配置：草稿不会被静默丢弃，而是标记出来让用户决定。
    @State private var conflictingDrafts: Set<UUID> = []
    /// Last source text explicitly validated for each profile. A list edit only
    /// clears a draft after the text is observed equivalent to the new stored
    /// entries; overwriting the draft binding itself marks it dirty again.
    @State private var sourceDraftValidations: [UUID: String] = [:]
    /// 同一配置再次编辑时递增；实时任务在真正写盘前核对，旧快照不能覆盖新编辑。
    @State private var realtimeApplyRevisions: [UUID: Int] = [:]
    @State private var operationError: String?
    @State private var showHelperGuide = false
    @State private var showStateRecoveryWarning = false
    /// The file was written, but the matching Core Data transaction failed.
    /// Keep writes blocked until the user explicitly reconciles the two states.
    @State private var stateCommitFailed = false
    /// When Core Data saving fails, the current model remains applied while the
    /// file contains the new merge. Remember the intended set so "reapply"
    /// actually completes the interrupted transaction.
    @State private var pendingAppliedProfileIDs: [UUID] = []
    /// Distinguishes an empty pending set (valid) from no pending intent.
    @State private var hasPendingAppliedProfileSelection = false
    /// Canonical fingerprint of the last file content observed at launch or
    /// successfully written by the app. It is used only for crash recovery.
    @State private var lastKnownHostsFingerprint: String?
    /// Hostnames emitted by the last successful managed write. The union with
    /// current profiles identifies old rows that must be removed after edits.
    @State private var managedHostnamesBaseline: Set<String> = []
    /// 每个配置独立防抖，避免编辑 A 后紧接着编辑 B 时取消 A 的落盘任务。
    @State private var realtimeApplyTasks: [UUID: Task<Void, Never>] = [:]
    @State private var pendingScrollProfileID: UUID?
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared

    private var selectedProfile: Profile? {
        if let id = selectedProfileID, let p = profiles.first(where: { $0.id == id }) { return p }
        if let active = profiles.first(where: \.isAppliedForSystem) { return active }
        return profiles.first(where: { !$0.isSystem }) ?? profiles.first
    }

    private var navigationTitle: String {
        guard showsCompactTitleBar else { return "Hosts Manager" }
        switch selection {
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
        switch selection {
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
        detailTitleBarCollapsed && selection != .settings
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

    private var shouldShowHelperGuideOnLaunch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestDisableHelperGuide") {
            return false
        }
        if isRunningInXcodePreview {
            return false
        }
        #endif
        return !HostsHelperClient.isRegistered
    }

    var body: some View {
        NavigationSplitView {
            NavigationSidebarView(
                profiles: profiles,
                selection: $selection,
                selectedProfileID: selectedProfile?.id,
                pendingScrollProfileID: $pendingScrollProfileID,
                onCreate: createProfile,
                onSelect: { profile in
                    selection = .profiles
                    selectedProfileID = profile.id
                },
                onEnable: enableProfile,
                onDisable: disableActiveProfile,
                onDelete: deleteProfile
            )
                .navigationSplitViewColumnWidth(min: 244, ideal: 276)
        } detail: {
            DetailContentView(
                selection: selection,
                selectedProfile: selectedProfile,
                mode: $mode,
                query: $query,
                sourceText: { profile in sourceBinding(for: profile) },
                isSourceDirty: { profile in
                    profile.id.map { sourceDrafts[$0] != nil } ?? false
                },
                hasDraftConflict: { profile in
                    profile.id.map { conflictingDrafts.contains($0) } ?? false
                },
                onApply: { profile in
                    _ = applyProfile(profile)
                },
                onDiscardDraft: { profile in
                    discardSourceDraft(for: profile)
                },
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
                selection: selection,
                query: $query,
                mode: $mode,
                selectedProfile: selectedProfile,
                l10n: l10n,
                onImport: importProfileFromFile,
                onDuplicate: duplicateSelectedProfile,
                onExport: exportSelectedProfile
            )
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .buttonBorderShape(.capsule)
        .sheet(isPresented: $showApply, onDismiss: { applyDraftText = nil }) {
            if let profile = selectedProfile {
                ApplySheet(
                    profile: profile,
                    draftText: applyDraftText,
                    managedHostnamesBaseline: managedHostnamesBaseline
                )
            }
        }
        .sheet(isPresented: $showHelperGuide) {
            HelperGuideSheet(onClose: { showHelperGuide = false })
        }
        .modifier(OperationErrorAlert(
            title: l10n.s("操作失败", "Operation Failed"),
            error: $operationError
        ))
        .alert(
            l10n.s("配置状态保存失败", "Profile State Save Failed"),
            isPresented: $showStateRecoveryWarning
        ) {
            Button(l10n.s("保留当前系统文件", "Keep Current System File")) {
                keepCurrentHostsContent()
            }
            Button(l10n.s("重新应用配置", "Reapply Profiles")) {
                reapplyActiveProfiles()
            }
            Button(l10n.s("稍后处理", "Later"), role: .cancel) {
                showStateRecoveryWarning = false
            }
        } message: {
            Text(l10n.s(
                "/etc/hosts 已写入，但配置开关状态未能保存。为避免文件与数据库继续分叉，后续写入已暂停；请选择如何处理。",
                "/etc/hosts was written, but the profile switch state could not be saved. Further writes are paused to prevent divergence; choose how to recover."
            ))
        }
        .onAppear {
            if !didApplyDefaultMode {
                if let stored = (try? context.fetch(AppSettings.fetchRequest()))?.first?.defaultView {
                    mode = EntryMode(rawValue: stored) ?? .list
                }
                didApplyDefaultMode = true
            }
            if selectedProfileID == nil {
                selectedProfileID = initialProfileID()
            }
            if shouldShowHelperGuideOnLaunch {
                showHelperGuide = true
            }
            applyAppearance()
            reconcileOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if HostsHelperClient.isRegistered {
                showHelperGuide = false
            }
            reconcileOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hostsStateReconciled)) { _ in
            reconcileSystemHosts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hostsStateSynchronized)) { notification in
            if let content = notification.object as? String {
                let appliedIDs = notification.userInfo?[
                    HostsStateNotificationKey.appliedProfileIDs
                ] as? [UUID]
                let managedHostnames = notification.userInfo?[
                    HostsStateNotificationKey.managedHostnames
                ] as? [String]
                noteSynchronizedHostsContent(
                    content,
                    appliedProfileIDs: appliedIDs,
                    managedHostnames: managedHostnames
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hostsStateNeedsReconciliation)) { notification in
            stateCommitFailed = true
            lastKnownHostsFingerprint = (try? HostsWriter.readContent()).map(
                HostsReconciliation.canonical
            )
            if let profileIDs = notification.userInfo?[
                HostsStateNotificationKey.appliedProfileIDs
            ] as? [UUID] {
                pendingAppliedProfileIDs = profileIDs
                hasPendingAppliedProfileSelection = true
            }
            if let managedHostnames = HostsReconciliationBaselineStore.load()?.managedHostnames {
                managedHostnamesBaseline = Set(managedHostnames)
            }
            persistReconciliationBaseline()
            reconcileSystemHosts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .performApply)) { _ in
            requestApply()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceDraftApplied)) { notification in
            if let profileID = notification.object as? UUID {
                realtimeApplyTasks[profileID]?.cancel()
                realtimeApplyTasks.removeValue(forKey: profileID)
                realtimeApplyRevisions.removeValue(forKey: profileID)
                sourceDrafts.removeValue(forKey: profileID)
                conflictingDrafts.remove(profileID)
                sourceDraftValidations.removeValue(forKey: profileID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileEntriesChanged)) { notification in
            if let profileID = notification.object as? UUID {
                // 列表改动已经落库。若此时还留着源码草稿，不能直接删掉（会静默丢失
                // 用户未应用的编辑），而是标记冲突，交给用户决定以哪边为准。
                if let draft = sourceDrafts[profileID],
                   let profile = profiles.first(where: { $0.id == profileID }),
                   sourceDraftMatchesStored(draft, profile: profile) {
                    sourceDrafts.removeValue(forKey: profileID)
                    conflictingDrafts.remove(profileID)
                    if sourceDraftValidations[profileID] == draft {
                        sourceDraftValidations.removeValue(forKey: profileID)
                    }
                } else if sourceDrafts[profileID] != nil {
                    conflictingDrafts.insert(profileID)
                    sourceDraftValidations.removeValue(forKey: profileID)
                }
                // 已应用配置的列表改动要实时写回系统；未应用配置只改库。
                if let profile = profiles.first(where: { $0.id == profileID }),
                   profile.isAppliedForSystem {
                    guard notification.userInfo?[
                        HostsStateNotificationKey.skipRealtimeApply
                    ] as? Bool != true else {
                        return
                    }
                    if stateCommitFailed {
                        showStateRecoveryWarning = true
                    } else {
                        scheduleRealtimeApply(for: profile)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .defaultEntryModeChanged)) { notification in
            if let rawValue = notification.object as? String {
                mode = EntryMode(rawValue: rawValue) ?? .list
            }
        }
        .onChange(of: appearance) { _, _ in
            applyAppearance()
        }
        .onChange(of: selection) { _, _ in
            detailTitleBarCollapsed = false
        }
        .onChange(of: selectedProfileID) { _, _ in
            detailTitleBarCollapsed = false
        }
        .onChange(of: mode) { _, _ in
            detailTitleBarCollapsed = false
        }
    }

    private func createProfile() {
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = l10n.s("新配置", "New Profile")
        // 新配置还没有写入 /etc/hosts，开关必须是关闭的：打开开关才代表“已生效”。
        profile.setApplied(false)
        profile.createdAt = Date()
        profile.updatedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
            operationError = localizedError(error)
            return
        }
        selectedProfileID = profile.id
        selection = .profiles
        pendingScrollProfileID = profile.id
    }

    private func deleteProfile(_ profile: Profile) {
        guard !profile.isAppliedForSystem else {
            operationError = l10n.s(
                "请先停用当前配置，再删除它。",
                "Disable the active profile before deleting it."
            )
            return
        }
        // 先取 id：对象删除并保存之后再去读属性是不可靠的。
        let profileID = profile.id
        let wasSelected = selectedProfileID == profileID
        context.delete(profile)
        do {
            try context.save()
        } catch {
            context.rollback()
            operationError = localizedError(error)
            return
        }
        if let profileID {
            realtimeApplyTasks[profileID]?.cancel()
            realtimeApplyTasks.removeValue(forKey: profileID)
            realtimeApplyRevisions.removeValue(forKey: profileID)
            sourceDrafts.removeValue(forKey: profileID)
            conflictingDrafts.remove(profileID)
            sourceDraftValidations.removeValue(forKey: profileID)
        }
        if wasSelected {
            selectedProfileID = profiles.first(where: { $0.id != profileID })?.id
        }
        NotificationCenter.default.post(name: .hostsStateReconciled, object: nil)
    }

    @discardableResult
    private func saveSourceIfNeeded(for target: Profile? = nil) -> Bool {
        guard mode == .source, let profile = target ?? selectedProfile, !profile.isSystem else {
            return true
        }
        // 没有草稿就什么都不用做。旧实现会把“重新生成的文本”当作草稿整体删库重建，
        // 等于顺手重写了一个用户根本没有编辑过的配置（id 全变、描述被本地化写回）。
        guard let profileID = profile.id, let draft = sourceDrafts[profileID] else {
            return true
        }
        if HostsValueValidator.validate(content: draft) != nil {
            operationError = l10n.s(
                "内容包含无效的 IP、主机名或控制字符。",
                "The content contains an invalid IP address, hostname, or control character."
            )
            return false
        }
        let newEntries = HostsParser.parse(draft)
        if HostsParser.entriesEquivalent(newEntries, parsedEntries(for: profile)) {
            sourceDrafts.removeValue(forKey: profileID)
            conflictingDrafts.remove(profileID)
            sourceDraftValidations.removeValue(forKey: profileID)
            return true
        }
        let sorted = profile.sortedEntries
        for e in sorted { context.delete(e) }
        var idx = 0
        for item in newEntries {
            let entry = HostEntry(context: context)
            entry.id = UUID()
            entry.profile = profile
            entry.ip = item.ip
            entry.hostnames = item.hostnames
            entry.desc = item.desc
            entry.isEnabled = item.isEnabled
            entry.isSystem = item.isSystem
            entry.sortIndex = Int64(idx)
            entry.createdAt = Date()
            idx += 1
        }
        profile.updatedAt = Date()
        do {
            try context.save()
        } catch {
            // 上面的删除已经发生在上下文里。不回滚的话，下一次任意一次保存
            // （备份记录、清理旧备份等）都会把“删除全部条目”提交掉。
            context.rollback()
            operationError = localizedError(error)
            return false
        }
        sourceDrafts[profileID] = draft
        sourceDraftValidations[profileID] = draft
        conflictingDrafts.remove(profileID)
        return true
    }

    /// 放弃源码草稿，回到数据库里的内容。只在用户明确点击时调用。
    private func discardSourceDraft(for profile: Profile) {
        guard let profileID = profile.id else { return }
        sourceDrafts.removeValue(forKey: profileID)
        conflictingDrafts.remove(profileID)
        sourceDraftValidations.removeValue(forKey: profileID)
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

    private func requestApply() {
        // 应用操作只属于编辑视图，列表视图里没有应用入口。
        guard mode == .source, selection == .profiles, let profile = selectedProfile else { return }
        guard !stateCommitFailed else {
            showStateRecoveryWarning = true
            return
        }
        applyProfile(profile)
    }

    private func parsedEntries(for profile: Profile) -> [ParsedHostEntry] {
        profile.sortedEntries.map {
            ParsedHostEntry(
                ip: $0.ip ?? "",
                hostnames: $0.hostList,
                desc: localizedSeedDescription($0.desc, isEnglish: l10n.isEnglish),
                isEnabled: $0.isEnabled,
                isSystem: $0.isSystem
            )
        }
    }

    private var activeProfiles: [Profile] {
        profiles.filter(\.isAppliedForSystem)
    }

    private var pendingApplyTargetProfiles: [Profile] {
        guard hasPendingAppliedProfileSelection else { return activeProfiles }
        let ids = Set(pendingAppliedProfileIDs)
        return profiles.filter { $0.id.map(ids.contains) == true }
    }

    private var configuredHostnames: Set<String> {
        Set(
            profiles
                .filter { !$0.isSystem }
                .flatMap(\.sortedEntries)
                .flatMap(\.hostList)
                .map { $0.lowercased() }
        )
    }

    private var ownedHostnames: Set<String> {
        configuredHostnames.union(managedHostnamesBaseline)
    }

    private func mergedContent(
        for profiles: [Profile],
        liveContent: String
    ) -> String {
        HostsContentMerger.merge(
            liveContent: liveContent,
            managedEntries: profiles.flatMap(parsedEntries(for:)),
            ownedHostnames: ownedHostnames
        )
    }

    private func validationIssues(for profiles: [Profile]) -> [HostIssue] {
        HostValidator.issues(entries: profiles.flatMap(parsedEntries(for:)).filter(\.isEnabled))
    }

    private func hasWriteConflict(in profiles: [Profile]) -> Bool {
        validationIssues(for: profiles).contains { $0.kind == .conflict }
    }

    // 配置开关 = 系统内容总开关：打开立即把该配置已启用的条目并入 /etc/hosts，
    // 关闭则只移除该配置。可同时启用多条配置，写入内容是它们已启用条目的并集。
    // 应用（Apply）是带预览和冲突检查的重新同步入口。
    // 开关的“开”必须等于“已写入系统”，因此新建 / 导入 / 复制的配置默认是关闭的。
    private func enableProfile(_ profile: Profile) {
        guard !profile.isSystem else { return }
        guard !stateCommitFailed else {
            showStateRecoveryWarning = true
            return
        }
        if let profileID = profile.id, sourceDrafts[profileID] != nil {
            selection = .profiles
            selectedProfileID = profileID
            applyDraftText = sourceDrafts[profileID]
            showApply = true
            return
        }
        guard saveSourceIfNeeded(for: profile) else { return }
        guard let profileID = profile.id else { return }
        let profileName = profile.localizedName(isEnglish: l10n.isEnglish)

        // 只有真正的主机名/IP 冲突需要阻断；完全重复项由合并管线自动去重。
        let initialTargets = activeProfiles.filter { $0.id != profile.id } + [profile]
        if hasWriteConflict(in: initialTargets) {
            selection = .profiles
            selectedProfileID = profile.id
            applyDraftText = nil
            showApply = true
            return
        }

        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(makeContent: { liveContent in
                    // Re-read active profiles when this operation reaches the
                    // queue head. A preceding queued operation may have changed
                    // the active set since the button was pressed.
                    guard let targetProfile = self.profiles.first(where: {
                        $0.id == profileID && !$0.isDeleted
                    }) else {
                        throw HostsWriteAbortedError()
                    }
                    let targets = self.activeProfiles.filter { $0.id != profileID } + [targetProfile]
                    if self.hasWriteConflict(in: targets) {
                        throw HostsWriteConflictError(profileID: profileID)
                    }
                    appliedProfileIDs = targets.compactMap(\.id)
                    return HostsWriteRequest(
                        content: self.mergedContent(
                            for: targets,
                            liveContent: liveContent
                        ),
                        appliedProfileIDs: targets.compactMap(\.id),
                        managedHostnames: Array(self.configuredHostnames).sorted()
                    )
                }, commit: { result in
                    try commitHostsWrite(
                        result: result,
                        context: context,
                        profileName: profileName,
                        note: l10n.s("启用配置前自动备份", "Auto backup before enabling profile"),
                        appliedProfileIDs: appliedProfileIDs,
                        checkStateIntegrity: {
                            let finalContent = self.mergedContent(
                                for: self.profiles.filter {
                                    $0.id.map(appliedProfileIDs.contains) == true
                                },
                                liveContent: result.content
                            )
                            return HostsReconciliation.canonical(finalContent)
                                == HostsReconciliation.canonical(result.content)
                        }
                    ) {
                        try setAppliedProfileSelection(
                            appliedProfileIDs,
                            lastActivatedProfileID: profileID,
                            context: context
                        )
                    }
                })
                resetReconciliationBaseline(
                    to: result.content,
                    appliedProfileIDs: appliedProfileIDs
                )
            } catch {
                handleWriteFailure(error, profileID: profileID)
            }
        }
    }

    @discardableResult
    private func applyProfile(_ profile: Profile) -> Bool {
        // 未启用的配置也允许“应用”：应用本身就是带预览的启用流程，
        // 确认写入后会同时把开关打开。
        guard !profile.isSystem else { return false }
        guard validateSourceDraftIfNeeded(for: profile) else { return false }
        if let profileID = profile.id,
           let draft = sourceDrafts[profileID],
           sourceDraftMatchesStored(draft, profile: profile) {
            sourceDrafts.removeValue(forKey: profileID)
            conflictingDrafts.remove(profileID)
            sourceDraftValidations.removeValue(forKey: profileID)
        }
        selection = .profiles
        selectedProfileID = profile.id
        applyDraftText = profile.id.flatMap { sourceDrafts[$0] }
        showApply = true
        return true
    }

    private func disableActiveProfile(_ profile: Profile) {
        guard let profileID = profile.id else { return }
        guard !stateCommitFailed else {
            showStateRecoveryWarning = true
            return
        }
        let profileName = profile.localizedName(isEnglish: l10n.isEnglish)
        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(makeContent: { liveContent in
                    // Only remove this profile; other active profiles stay.
                    let remaining = self.activeProfiles.filter { $0.id != profileID }
                    // The switch may have been turned on while an earlier queued
                    // write was still running, then immediately turned off. We
                    // still need to write the current remaining set because the
                    // earlier write may have applied this profile.
                    appliedProfileIDs = remaining.compactMap(\.id)
                    return HostsWriteRequest(
                        content: self.mergedContent(
                            for: remaining,
                            liveContent: liveContent
                        ),
                        appliedProfileIDs: remaining.compactMap(\.id),
                        managedHostnames: Array(self.configuredHostnames).sorted()
                    )
                }, commit: { result in
                    try commitHostsWrite(
                        result: result,
                        context: context,
                        profileName: profileName,
                        note: l10n.s("停用当前配置前自动备份", "Auto backup before disabling the active profile"),
                        appliedProfileIDs: appliedProfileIDs,
                        checkStateIntegrity: {
                            let finalContent = self.mergedContent(
                                for: self.profiles.filter {
                                    $0.id.map(appliedProfileIDs.contains) == true
                                },
                                liveContent: result.content
                            )
                            return HostsReconciliation.canonical(finalContent)
                                == HostsReconciliation.canonical(result.content)
                        }
                    ) {
                        try setAppliedProfileSelection(
                            appliedProfileIDs,
                            context: context
                        )
                    }
                })
                resetReconciliationBaseline(
                    to: result.content,
                    appliedProfileIDs: appliedProfileIDs
                )
            } catch {
                handleWriteFailure(error, profileID: profileID)
            }
        }
    }

    /// 列表视图实时应用：条目变动后把已启用配置的并集立即写回 /etc/hosts。
    /// 用短暂防抖合并连续操作；写入本身由 HostsWriteCoordinator 串行排队，
    /// 这里不再判断/重试 isWriting。
    private func scheduleRealtimeApply(for profile: Profile) {
        guard let profileID = profile.id else { return }
        let revision = realtimeApplyRevisions[profileID, default: 0] + 1
        realtimeApplyRevisions[profileID] = revision
        let existing = realtimeApplyTasks[profileID]
        realtimeApplyTasks[profileID] = Task { @MainActor in
            defer {
                if realtimeApplyRevisions[profileID] == revision {
                    realtimeApplyTasks.removeValue(forKey: profileID)
                    realtimeApplyRevisions.removeValue(forKey: profileID)
                }
            }
            // If an earlier realtime write already started, let it finish without
            // cancelling it; this task will then perform a follow-up write with
            // the latest database contents.
            _ = await existing?.value
            guard !Task.isCancelled,
                  realtimeApplyRevisions[profileID] == revision else {
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  realtimeApplyRevisions[profileID] == revision,
                  let current = profiles.first(where: { $0.id == profileID }),
                  !current.isDeleted else {
                return
            }
            guard !stateCommitFailed else {
                showStateRecoveryWarning = true
                return
            }
            realtimeApplyTasks.removeValue(forKey: profileID)
            applyActiveProfilesToSystem(for: current)
        }
    }

    private func applyActiveProfilesToSystem(for profile: Profile) {
        // 开关打开才代表“该配置属于系统内容”。关闭的配置列表编辑后只改库，
        // 不会被静默带进 /etc/hosts。
        guard !profile.isSystem else { return }
        guard profile.isAppliedForSystem else { return }
        guard let profileID = profile.id else { return }
        let profileName = profile.localizedName(isEnglish: l10n.isEnglish)
        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(makeContent: { liveContent in
                    // A restore or another queued operation may have disabled
                    // this profile after the debounce fired. Re-check at the
                    // queue head so a stale task cannot undo that state.
                    guard let current = self.profiles.first(where: { $0.id == profileID }),
                          current.isAppliedForSystem else {
                        throw HostsWriteAbortedError()
                    }
                    let targets = self.activeProfiles
                    guard !targets.isEmpty else { throw HostsWriteAbortedError() }
                    if self.hasWriteConflict(in: targets) {
                        throw HostsWriteConflictError(profileID: profileID)
                    }
                    appliedProfileIDs = targets.compactMap(\.id)
                    return HostsWriteRequest(
                        content: self.mergedContent(
                            for: targets,
                            liveContent: liveContent
                        ),
                        appliedProfileIDs: targets.compactMap(\.id),
                        managedHostnames: Array(self.configuredHostnames).sorted()
                    )
                }, commit: { result in
                    try commitHostsWrite(
                        result: result,
                        context: context,
                        profileName: profileName,
                        note: l10n.s("列表编辑后实时应用", "Real-time apply after list edit"),
                        appliedProfileIDs: appliedProfileIDs,
                        checkStateIntegrity: {
                            let finalContent = self.mergedContent(
                                for: self.profiles.filter {
                                    $0.id.map(appliedProfileIDs.contains) == true
                                },
                                liveContent: result.content
                            )
                            return HostsReconciliation.canonical(finalContent)
                                == HostsReconciliation.canonical(result.content)
                        }
                    ) {
                        try setAppliedProfileSelection(
                            appliedProfileIDs,
                            lastActivatedProfileID: profileID,
                            context: context
                        )
                    }
                })
                resetReconciliationBaseline(
                    to: result.content,
                    appliedProfileIDs: appliedProfileIDs
                )
            } catch {
                handleWriteFailure(error, profileID: profileID)
            }
        }
    }

    private func reconcileSystemHosts() {
        showStateRecoveryWarning = stateCommitFailed
    }

    private func reconcileOnLaunch() {
        if lastKnownHostsFingerprint == nil {
            loadPersistedReconciliationBaseline()
        }
        if let baseline = HostsReconciliationBaselineStore.load(),
           let recovery = HostsRecoveryPlanner.resolve(baseline: baseline) {
            stateCommitFailed = true
            pendingAppliedProfileIDs = recovery.appliedProfileIDs
            hasPendingAppliedProfileSelection = true
        } else {
            stateCommitFailed = false
            pendingAppliedProfileIDs = []
            hasPendingAppliedProfileSelection = false
        }
        if managedHostnamesBaseline.isEmpty {
            managedHostnamesBaseline = configuredHostnames
        }
        refreshReconciliationBaselineFromLiveFile()
    }

    private func refreshReconciliationBaselineFromLiveFile() {
        if let liveContent = try? HostsWriter.readContent() {
            lastKnownHostsFingerprint = HostsReconciliation.canonical(liveContent)
            persistReconciliationBaseline()
        } else if lastKnownHostsFingerprint == nil {
            HostsReconciliationBaselineStore.clear()
        }
        reconcileSystemHosts()
    }

    private func loadPersistedReconciliationBaseline() {
        guard let baseline = HostsReconciliationBaselineStore.load() else {
            return
        }
        lastKnownHostsFingerprint = baseline.fingerprint
        managedHostnamesBaseline = Set(baseline.managedHostnames)
        stateCommitFailed = baseline.stateCommitFailed
        if let pending = baseline.pendingAppliedProfileIDs {
            pendingAppliedProfileIDs = pending
            hasPendingAppliedProfileSelection = true
        } else if baseline.stateCommitFailed {
            pendingAppliedProfileIDs = baseline.appliedProfileIDs
            hasPendingAppliedProfileSelection = true
        }
    }

    private func persistReconciliationBaseline() {
        guard let fingerprint = lastKnownHostsFingerprint else {
            HostsReconciliationBaselineStore.clear()
            return
        }
        HostsReconciliationBaselineStore.save(
            HostsReconciliationBaseline(
                fingerprint: fingerprint,
                appliedProfileIDs: activeProfiles.compactMap(\.id),
                pendingAppliedProfileIDs: hasPendingAppliedProfileSelection
                    ? pendingAppliedProfileIDs
                    : nil,
                managedHostnames: managedHostnamesBaseline.sorted(),
                stateCommitFailed: stateCommitFailed
            )
        )
    }

    /// Resolve a failed state commit by keeping the file and clearing applied
    /// profile switches in Core Data.
    private func keepCurrentHostsContent() {
        let liveContent = try? HostsWriter.readContent()
        let liveFingerprint = liveContent.map(HostsReconciliation.canonical)
        let previousFingerprint = lastKnownHostsFingerprint
        let previousStateCommitFailed = stateCommitFailed
        let previousPending = pendingAppliedProfileIDs
        let previousHasPending = hasPendingAppliedProfileSelection
        do {
            try clearAppliedStateForUserProfiles(in: context)
            try context.save()
        } catch {
            context.rollback()
            lastKnownHostsFingerprint = previousFingerprint
            stateCommitFailed = previousStateCommitFailed
            pendingAppliedProfileIDs = previousPending
            hasPendingAppliedProfileSelection = previousHasPending
            operationError = localizedError(error)
            persistReconciliationBaseline()
            return
        }
        writeCoordinator.clearStateRecovery()
        lastKnownHostsFingerprint = liveFingerprint
        pendingAppliedProfileIDs = []
        hasPendingAppliedProfileSelection = false
        stateCommitFailed = false
        showStateRecoveryWarning = false
        persistReconciliationBaseline()
        NotificationCenter.default.post(name: .hostsStateReconciled, object: nil)
    }

    /// Resolve a failed state commit by applying the pending profile selection.
    private func reapplyActiveProfiles() {
        let targetIDs = stateCommitFailed && hasPendingAppliedProfileSelection
            ? pendingAppliedProfileIDs
            : activeProfiles.compactMap(\.id)
        let sourceProfiles = stateCommitFailed && hasPendingAppliedProfileSelection
            ? pendingApplyTargetProfiles
            : activeProfiles
        let first = sourceProfiles.first {
            $0.id.map(targetIDs.contains) == true
        }
        let primaryProfile = first ?? selectedProfile
        let targets = profiles.filter { profile in
            profile.id.map(targetIDs.contains) == true && !profile.isDeleted
        }
        guard !hasWriteConflict(in: targets) else {
            selection = .profiles
            selectedProfileID = first?.id
            applyDraftText = nil
            writeCoordinator.clearStateRecovery()
            showApply = true
            showStateRecoveryWarning = false
            return
        }
        showStateRecoveryWarning = false
        writeCoordinator.clearStateRecovery()
        if targetIDs.isEmpty {
            writeEmptyAppliedSelection()
            return
        }
        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(makeContent: { liveContent in
                    let targets = self.profiles.filter { profile in
                        profile.id.map(targetIDs.contains) == true
                    }
                    if self.hasWriteConflict(in: targets) {
                        guard let profileID = targets.first?.id else { throw HostsWriteAbortedError() }
                        throw HostsWriteConflictError(profileID: profileID)
                    }
                    appliedProfileIDs = targets.compactMap(\.id)
                    return HostsWriteRequest(
                        content: self.mergedContent(
                            for: targets,
                            liveContent: liveContent
                        ),
                        appliedProfileIDs: targets.compactMap(\.id),
                        managedHostnames: Array(self.configuredHostnames).sorted()
                    )
                }, commit: { result in
                    try commitHostsWrite(
                        result: result,
                        context: context,
                        profileName: primaryProfile?.localizedName(isEnglish: l10n.isEnglish),
                        note: l10n.s("重新同步配置前自动备份", "Auto backup before resynchronizing profiles"),
                        appliedProfileIDs: appliedProfileIDs,
                        checkStateIntegrity: {
                            let finalContent = self.mergedContent(
                                for: self.profiles.filter {
                                    $0.id.map(appliedProfileIDs.contains) == true
                                },
                                liveContent: result.content
                            )
                            return HostsReconciliation.canonical(finalContent)
                                == HostsReconciliation.canonical(result.content)
                        }
                    ) {
                        try setAppliedProfileSelection(
                            appliedProfileIDs,
                            context: context
                        )
                    }
                })
                resetReconciliationBaseline(
                    to: result.content,
                    appliedProfileIDs: appliedProfileIDs
                )
            } catch {
                handleWriteFailure(error, profileID: first?.id)
            }
        }
    }

    private func writeEmptyAppliedSelection() {
        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(makeContent: { liveContent in
                    appliedProfileIDs = []
                    return HostsWriteRequest(
                        content: self.mergedContent(
                            for: [],
                            liveContent: liveContent
                        ),
                        appliedProfileIDs: [],
                        managedHostnames: Array(self.configuredHostnames).sorted()
                    )
                }, commit: { result in
                    try commitHostsWrite(
                        result: result,
                        context: context,
                        profileName: nil,
                        note: l10n.s(
                            "重新同步配置前自动备份",
                            "Auto backup before resynchronizing profiles"
                        ),
                        appliedProfileIDs: []
                    ) {
                        try setAppliedProfileSelection([], context: context)
                    }
                })
                resetReconciliationBaseline(
                    to: result.content,
                    appliedProfileIDs: appliedProfileIDs
                )
            } catch {
                handleWriteFailure(error, profileID: nil)
            }
        }
    }

    private func noteSynchronizedHostsContent(
        _ content: String,
        appliedProfileIDs: [UUID]? = nil,
        managedHostnames: [String]? = nil
    ) {
        lastKnownHostsFingerprint = HostsReconciliation.canonical(content)
        managedHostnamesBaseline = managedHostnames.map { Set($0) } ?? configuredHostnames
        stateCommitFailed = false
        pendingAppliedProfileIDs = []
        hasPendingAppliedProfileSelection = false
        showStateRecoveryWarning = false
        if let appliedProfileIDs {
            HostsReconciliationBaselineStore.save(
                HostsReconciliationBaseline(
                    fingerprint: HostsReconciliation.canonical(content),
                    appliedProfileIDs: appliedProfileIDs,
                    pendingAppliedProfileIDs: nil,
                    managedHostnames: managedHostnamesBaseline.sorted(),
                    stateCommitFailed: false
                )
            )
            return
        }
        persistReconciliationBaseline()
    }

    private func resetReconciliationBaseline(
        to content: String,
        appliedProfileIDs: [UUID]? = nil
    ) {
        noteSynchronizedHostsContent(
            content,
            appliedProfileIDs: appliedProfileIDs
        )
    }

    private func sourceText(for profile: Profile) -> String {
        if let profileID = profile.id, let draft = sourceDrafts[profileID] {
            return draft
        }
        return localizedSourceText(for: profile, isEnglish: l10n.isEnglish)
    }

    private func sourceDraftMatchesStored(_ draft: String, profile: Profile) -> Bool {
        guard let profileID = profile.id else { return false }
        let matches = HostsParser.entriesEquivalent(
            HostsParser.parse(draft),
            parsedEntries(for: profile)
        )
        if matches {
            sourceDraftValidations[profileID] = draft
        }
        return matches
    }

    private func validateSourceDraftIfNeeded(for profile: Profile) -> Bool {
        guard let profileID = profile.id, let draft = sourceDrafts[profileID] else {
            return true
        }
        guard HostsValueValidator.validate(content: draft) == nil else {
            operationError = l10n.s(
                "内容包含无效的 IP、主机名或控制字符。",
                "The content contains an invalid IP address, hostname, or control character."
            )
            return false
        }
        return true
    }

    private func sourceBinding(for profile: Profile) -> Binding<String> {
        Binding(
            get: { sourceText(for: profile) },
            set: { value in
                if let profileID = profile.id {
                    let stored = parsedEntries(for: profile)
                    if HostsParser.entriesEquivalent(HostsParser.parse(value), stored) {
                        sourceDrafts.removeValue(forKey: profileID)
                        conflictingDrafts.remove(profileID)
                        sourceDraftValidations.removeValue(forKey: profileID)
                        return
                    }
                    if sourceDraftValidations[profileID] == value {
                        sourceDrafts.removeValue(forKey: profileID)
                        conflictingDrafts.remove(profileID)
                        sourceDraftValidations.removeValue(forKey: profileID)
                    } else {
                        sourceDrafts[profileID] = value
                    }
                }
            }
        )
    }

    private func initialProfileID() -> UUID? {
        let candidates = profiles.filter { !$0.isSystem }
        if let last = candidates.max(by: {
            ($0.lastActivatedAt ?? $0.updatedAt ?? $0.createdAt ?? .distantPast)
                < ($1.lastActivatedAt ?? $1.updatedAt ?? $1.createdAt ?? .distantPast)
        }) {
            return last.id
        }
        return selectedProfile?.id
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

        do {
            let imported = try HostsImport.load(from: url)
            let profile = Profile(context: context)
            profile.id = UUID()
            profile.name = l10n.s(
                "导入 \(imported.suggestedProfileName)",
                "Imported \(imported.suggestedProfileName)"
            )
            profile.setApplied(false)
            profile.createdAt = Date()
            profile.updatedAt = Date()
            addEntries(imported.entries, to: profile)
            try context.save()
            selectedProfileID = profile.id
            selection = .profiles
            mode = .list
            pendingScrollProfileID = profile.id
        } catch let error as HostsImportError {
            context.rollback()
            operationError = importErrorMessage(error)
        } catch {
            context.rollback()
            operationError = localizedError(error)
        }
    }

    private func importErrorMessage(_ error: HostsImportError) -> String {
        switch error {
        case .unreadable:
            return l10n.s("无法读取所选文件。", "The selected file could not be read.")
        case .tooLarge:
            return l10n.s("文件超过 1 MiB，无法导入。", "The file exceeds the 1 MiB import limit.")
        case .invalidEncoding:
            return l10n.s("文件不是有效的 UTF-8 文本。", "The file is not valid UTF-8 text.")
        case .invalidContent:
            return l10n.s(
                "文件包含无效的 IP 地址、主机名或控制字符。",
                "The file contains an invalid IP address, hostname, or control character."
            )
        case .noUserEntries:
            return l10n.s("文件中没有可导入的用户条目。", "The file does not contain any user entries to import.")
        }
    }

    private func duplicateSelectedProfile() {
        guard let source = selectedProfile, !source.isSystem else { return }
        let profile = Profile(context: context)
        profile.id = UUID()
        let sourceName = source.localizedName(isEnglish: l10n.isEnglish)
        profile.name = l10n.s("\(sourceName) 副本", "\(sourceName) Copy")
        // 副本没有写入系统，开关保持关闭，避免“开关已开但系统里没有内容”。
        profile.setApplied(false)
        profile.createdAt = Date()
        profile.updatedAt = Date()
        let entries = source.sortedEntries.map {
            ParsedHostEntry(
                ip: $0.ip ?? "",
                hostnames: $0.hostList,
                desc: $0.desc ?? "",
                isEnabled: $0.isEnabled,
                isSystem: $0.isSystem
            )
        }
        addEntries(entries, to: profile)
        do {
            try context.save()
            selectedProfileID = profile.id
        } catch {
            context.rollback()
            operationError = localizedError(error)
        }
    }

    private func exportSelectedProfile() {
        guard let profile = selectedProfile, !profile.isSystem else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(profile.localizedName(isEnglish: l10n.isEnglish)).hosts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try sourceText(for: profile).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            operationError = localizedError(error)
        }
    }

    private func addEntries(_ entries: [ParsedHostEntry], to profile: Profile) {
        for (index, item) in entries.enumerated() {
            let entry = HostEntry(context: context)
            entry.id = UUID()
            entry.profile = profile
            entry.ip = item.ip
            entry.hostnames = item.hostnames
            entry.desc = item.desc
            entry.isEnabled = item.isEnabled
            entry.isSystem = item.isSystem
            entry.sortIndex = Int64(index)
            entry.createdAt = Date()
        }
    }

    private func handleWriteFailure(_ error: Error, profileID: UUID?) {
        if error is HostsStateRecoveryRequiredError {
            showStateRecoveryWarning = true
            return
        }
        if error is HostsWriteStateReconciliationError {
            stateCommitFailed = true
            persistReconciliationBaseline()
            showStateRecoveryWarning = true
            return
        }
        if let conflict = error as? HostsWriteConflictError {
            if conflict.profileID == profileID {
                selection = .profiles
                selectedProfileID = conflict.profileID
                applyDraftText = sourceDrafts[conflict.profileID]
                showApply = true
            }
            return
        }
        if error is HostsWriteAbortedError {
            return
        }
        if error is HostsWriteCommitError {
            stateCommitFailed = true
            hasPendingAppliedProfileSelection = true
            if let managedHostnames = HostsReconciliationBaselineStore.load()?.managedHostnames {
                managedHostnamesBaseline = Set(managedHostnames)
            }
            if let content = try? HostsWriter.readContent() {
                lastKnownHostsFingerprint = HostsReconciliation.canonical(content)
            }
            persistReconciliationBaseline()
            showStateRecoveryWarning = true
            return
        }
        operationError = localizedError(error)
    }

    private func localizedError(_ error: Error) -> String {
        if error is HostsStateRecoveryRequiredError {
            return l10n.s(
                "配置状态尚未恢复，写入已暂停。",
                "Profile state recovery is pending; writes are paused."
            )
        }
        if error is HostsWriteStateReconciliationError {
            return l10n.s(
                "/etc/hosts 已写入，但配置状态未能完整同步。请先恢复配置状态。",
                "/etc/hosts was written, but the profile state is not fully synchronized. Recover the profile state first."
            )
        }
        if error is HostsWriteConflictError {
            return l10n.s(
                "配置与其它已启用配置存在主机名冲突，未写入系统。",
                "The profile conflicts with another active profile; nothing was written."
            )
        }
        if error is HostsWriteAbortedError {
            return l10n.s(
                "写入已取消，配置状态未变更。",
                "The write was cancelled; profile state was not changed."
            )
        }
        if let commitError = error as? HostsWriteCommitError {
            return l10n.s(
                "/etc/hosts 已写入，但配置状态保存失败。请检查磁盘空间后重试同步。\n\(commitError.underlying.localizedDescription)",
                "/etc/hosts was written, but the profile state could not be saved. Check available disk space and resync.\n\(commitError.underlying.localizedDescription)"
            )
        }
        if let writeError = error as? HostsWriteError {
            switch writeError {
            case .invalidContent(_):
                return l10n.s(
                    "内容包含无效的 IP、主机名或控制字符。",
                    "The content contains an invalid IP address, hostname, or control character."
                )
            case .authorizationFailed:
                return l10n.s("无法通过后台写入助手授权。", "The background writer helper rejected the request.")
            case .helperUnavailable:
                return l10n.s(
                    "后台写入助手不可用。请在设置中启用，并在“系统设置 → 通用 → 登录项与扩展”中批准后重试。",
                    "The background writer helper is unavailable. Enable it in Settings and approve it in System Settings > General > Login Items & Extensions."
                )
            case .writeFailed:
                return l10n.s("写入 /etc/hosts 失败。", "Failed to write /etc/hosts.")
            case .readFailed:
                return l10n.s("无法读取 /etc/hosts。", "Unable to read /etc/hosts.")
            case .verificationFailed:
                return l10n.s("写入后校验失败，请检查 hosts 文件。", "Verification failed after writing /etc/hosts.")
            case .timedOut:
                return l10n.s("后台写入助手响应超时。", "The background writer helper timed out.")
            }
        }
        return error.localizedDescription
    }
}

#Preview("Main Window") {
    ContentView()
        .environment(\.managedObjectContext, PreviewFixtures.context)
        .environmentObject(Localization())
        .frame(minWidth: 1_000, minHeight: 680)
}

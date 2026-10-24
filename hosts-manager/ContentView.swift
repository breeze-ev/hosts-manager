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
}

enum SidebarItem: String, CaseIterable, Hashable {
    case profiles, backups, settings
}

enum EntryMode: String, CaseIterable {
    case list, source
}

struct ProfileSidebarRow: View {
    @ObservedObject var profile: Profile
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void
    let onEnableActive: () -> Void
    let onDisableActive: () -> Void
    let onDelete: () -> Void
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization
    @State private var showDeleteConfirm = false
    @State private var showDisableConfirm = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var renameError: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isRenaming {
                ProfileAvatar(profile: profile)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($isNameFocused)
                        .onSubmit(saveRename)
                        .onExitCommand(perform: cancelRename)
                    if let renameError {
                        Text(renameError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    cancelRename()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(l10n.s("取消", "Cancel"))

                Button {
                    saveRename()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(l10n.s("保存", "Save"))
            } else {
                Button {
                    onSelect()
                } label: {
                    ProfileRow(profile: profile, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-row-\(profile.name ?? "")")

                if !profile.isSystem {
                    Toggle("", isOn: Binding(
                        get: { profile.isEnabled },
                        set: { newValue in
                            if !newValue && profile.isActive {
                                showDisableConfirm = true
                            } else if newValue && !profile.isActive {
                                onEnableActive()
                            } else {
                                onToggle(newValue)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .help(l10n.s("启用并写入系统，停用则移除", "Enable and write to system, disable removes it"))
                    .popover(isPresented: $showDisableConfirm, arrowEdge: .bottom) {
                        ConfirmPopover(
                            title: l10n.s("停用当前配置？", "Disable the active profile?"),
                            message: l10n.s(
                                "当前配置会从 /etc/hosts 中移除，操作前会自动备份。",
                                "The active profile will be removed from /etc/hosts. A backup is created first."
                            ),
                            cancelTitle: l10n.s("取消", "Cancel"),
                            confirmTitle: l10n.s("停用并清除用户条目", "Disable and clear user entries"),
                            onCancel: { showDisableConfirm = false },
                            onConfirm: {
                                showDisableConfirm = false
                                onDisableActive()
                            }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(isRenaming ? 1 : (profile.isEnabled ? 1 : 0.45))
        .contextMenu {
            if !profile.isSystem {
                Button(l10n.s("重命名", "Rename")) {
                    beginRename()
                }
                Button(l10n.s("删除配置", "Delete Profile"), role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .popover(isPresented: $showDeleteConfirm, arrowEdge: .trailing) {
            ConfirmPopover(
                title: l10n.s("删除此配置？", "Delete this profile?"),
                message: l10n.s("此操作无法撤销。", "This action cannot be undone."),
                cancelTitle: l10n.s("取消", "Cancel"),
                confirmTitle: l10n.s("删除", "Delete"),
                onCancel: { showDeleteConfirm = false },
                onConfirm: {
                    showDeleteConfirm = false
                    onDelete()
                }
            )
        }
    }

    private func beginRename() {
        draftName = profile.localizedName(isEnglish: l10n.isEnglish)
        renameError = nil
        isRenaming = true
        isNameFocused = true
    }

    private func cancelRename() {
        isRenaming = false
        isNameFocused = false
        renameError = nil
    }

    private func saveRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            renameError = l10n.s("配置名称不能为空。", "The profile name cannot be empty.")
            return
        }
        profile.name = trimmed
        profile.updatedAt = Date()
        do {
            try context.save()
            cancelRename()
        } catch {
            renameError = error.localizedDescription
        }
    }
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

    @State private var selection: SidebarItem = .profiles
    @State private var selectedProfileID: UUID?
    @State private var mode: EntryMode = .list
    @State private var didApplyDefaultMode = false
    @State private var showApply = false
    @State private var query = ""
    @State private var sourceDrafts: [UUID: String] = [:]
    @State private var operationError: String?
    @State private var showHelperGuide = false
    @State private var realtimeApplyTask: Task<Void, Never>?
    @State private var pendingScrollProfileID: UUID?
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared

    private var selectedProfile: Profile? {
        if let id = selectedProfileID, let p = profiles.first(where: { $0.id == id }) { return p }
        if let active = profiles.first(where: \.isActive) { return active }
        return profiles.first(where: { !$0.isSystem }) ?? profiles.first
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 244, ideal: 276)
        } detail: {
            detail
        }
        .navigationTitle("Hosts Manager")
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .buttonBorderShape(.capsule)
        .sheet(isPresented: $showApply) {
            if let profile = selectedProfile { ApplySheet(profile: profile) }
        }
        .sheet(isPresented: $showHelperGuide) {
            HelperGuideSheet(onClose: { showHelperGuide = false })
        }
        .alert(
            l10n.s("操作失败", "Operation Failed"),
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "")
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
            if !HostsHelperClient.isRegistered {
                showHelperGuide = true
            }
            applyAppearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if HostsHelperClient.isRegistered {
                showHelperGuide = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selection = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .performApply)) { _ in
            requestApply()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceDraftApplied)) { notification in
            if let profileID = notification.object as? UUID {
                sourceDrafts.removeValue(forKey: profileID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileEntriesChanged)) { notification in
            if let profileID = notification.object as? UUID {
                sourceDrafts.removeValue(forKey: profileID)
                // 列表视图是实时应用：条目一旦变动，立即把已启用配置的并集写回系统。
                if let profile = profiles.first(where: { $0.id == profileID }), profile.isActive {
                    scheduleRealtimeApply(for: profile)
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
    }

    private var sidebar: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(profiles) { profile in
                    ProfileSidebarRow(
                        profile: profile,
                        isSelected: selection == .profiles && selectedProfile?.id == profile.id,
                        onSelect: {
                            selection = .profiles
                            selectedProfileID = profile.id
                        },
                        onToggle: { newValue in
                            setProfileEnabled(profile, enabled: newValue)
                        },
                        onEnableActive: {
                            enableProfile(profile)
                        },
                        onDisableActive: {
                            disableActiveProfile(profile)
                        },
                        onDelete: {
                            deleteProfile(profile)
                        }
                    )
                    .id(profile.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(l10n.s("配置", "Profiles"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        createProfile()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("create-profile-button")
                    .accessibilityLabel(l10n.s("新建配置", "New Profile"))
                    .help(l10n.s("新建配置", "New Profile"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
            .safeAreaBar(edge: .bottom, alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        selection = .backups
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18))
                            .foregroundStyle(selection == .backups ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selection == .backups ? Color.accentColor.opacity(0.18) : .clear)
                            )
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.s("备份", "Backups"))

                    Button {
                        selection = .settings
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(selection == .settings ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selection == .settings ? Color.accentColor.opacity(0.18) : .clear)
                            )
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.s("设置", "Settings"))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .onChange(of: profiles.map(\.id)) { _, newIDs in
                if let targetID = pendingScrollProfileID, newIDs.contains(targetID) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(targetID, anchor: .top)
                        }
                        pendingScrollProfileID = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .profiles:
            if let profile = selectedProfile {
                ProfileDetailView(
                    profile: profile,
                    mode: $mode,
                    query: $query,
                    sourceText: sourceBinding(for: profile),
                    isSourceDirty: profile.id.map { sourceDrafts[$0] != nil } ?? false,
                    onApply: { applyProfile(profile) }
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
            BackupsView()
        case .settings:
            SettingsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selection == .profiles {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(l10n.s("搜索", "Search"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.leading, 10)
                .frame(width: 190, alignment: .leading)

                Picker("", selection: $mode) {
                    Label(l10n.s("列表", "List"), systemImage: "list.bullet").tag(EntryMode.list)
                    Label(l10n.s("编辑", "Edit"), systemImage: "pencil").tag(EntryMode.source)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Menu {
                    Button(l10n.s("导入当前 hosts", "Import Current Hosts"), systemImage: "square.and.arrow.down") {
                        importCurrentHosts()
                    }
                    Button(l10n.s("复制当前配置", "Duplicate Profile"), systemImage: "doc.on.doc") {
                        duplicateSelectedProfile()
                    }
                    Button(l10n.s("导出当前配置", "Export Profile"), systemImage: "square.and.arrow.up") {
                        exportSelectedProfile()
                    }
                    .disabled(selectedProfile?.isSystem != false)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(l10n.s("导入、复制或导出配置", "Import, duplicate, or export profile"))
            }
        }
    }

    private func createProfile() {
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = l10n.s("新配置", "New Profile")
        profile.isActive = false
        profile.isEnabled = true
        profile.createdAt = Date()
        profile.updatedAt = Date()
        do {
            try context.save()
        } catch {
            operationError = localizedError(error)
            return
        }
        selectedProfileID = profile.id
        selection = .profiles
        pendingScrollProfileID = profile.id
    }

    private func deleteProfile(_ profile: Profile) {
        guard !profile.isActive else {
            operationError = l10n.s(
                "请先停用当前配置，再删除它。",
                "Disable the active profile before deleting it."
            )
            return
        }
        context.delete(profile)
        do {
            try context.save()
        } catch {
            operationError = localizedError(error)
            return
        }
        if let profileID = profile.id {
            sourceDrafts.removeValue(forKey: profileID)
        }
        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first(where: { $0 !== profile })?.id
        }
    }

    @discardableResult
    private func saveSourceIfNeeded(for target: Profile? = nil) -> Bool {
        guard mode == .source, let profile = target ?? selectedProfile, !profile.isSystem else {
            return true
        }
        let draft = sourceText(for: profile)
        if HostsValueValidator.validate(content: draft) != nil {
            operationError = l10n.s(
                "内容包含无效的 IP、主机名或控制字符。",
                "The content contains an invalid IP address, hostname, or control character."
            )
            return false
        }
        let newEntries = HostsParser.parse(draft)
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
            operationError = localizedError(error)
            return false
        }
        if let profileID = profile.id {
            sourceDrafts[profileID] = draft
        }
        return true
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
        profiles.filter { $0.isActive && !$0.isSystem }
    }

    private func mergedContent(for profiles: [Profile]) -> String {
        HostsParser.mergedContent(entries: profiles.flatMap(parsedEntries(for:)))
    }

    private func validationIssues(for profiles: [Profile]) -> [HostIssue] {
        HostValidator.issues(entries: profiles.flatMap(parsedEntries(for:)).filter(\.isEnabled))
    }

    // 配置开关 = 系统内容总开关：打开立即把该配置已启用的条目并入 /etc/hosts，
    // 关闭则只移除该配置。可同时启用多条配置，写入内容是它们已启用条目的并集。
    // 应用（Apply）是带预览和冲突检查的重新同步入口。
    private func enableProfile(_ profile: Profile) {
        guard !profile.isSystem, !writeCoordinator.isWriting else { return }
        guard saveSourceIfNeeded(for: profile) else { return }

        let others = activeProfiles.filter { $0.id != profile.id }
        let targetProfiles = others + [profile]

        // 打开开关同样遵守冲突检查：与其它已启用配置存在冲突/重复时转入“应用”预览，
        // 让用户先处理，而不是把有冲突的内容静默写入系统。
        if !validationIssues(for: targetProfiles).isEmpty {
            profile.isEnabled = true
            profile.updatedAt = Date()
            do {
                try context.save()
            } catch {
                operationError = localizedError(error)
                return
            }
            selection = .profiles
            selectedProfileID = profile.id
            showApply = true
            return
        }

        profile.isEnabled = true
        profile.updatedAt = Date()
        do {
            try context.save()
        } catch {
            operationError = localizedError(error)
            return
        }
        let content = mergedContent(for: targetProfiles)
        Task {
            do {
                let backupURL = try await writeCoordinator.write(content)
                recordBackup(
                    at: backupURL,
                    profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                    note: l10n.s("启用配置前自动备份", "Auto backup before enabling profile")
                )
                profile.isActive = true
                profile.isEnabled = true
                profile.lastActivatedAt = Date()
                profile.updatedAt = Date()
                try context.save()
            } catch {
                operationError = localizedError(error)
            }
        }
    }

    @discardableResult
    private func applyProfile(_ profile: Profile) -> Bool {
        guard !profile.isSystem, profile.isEnabled, !writeCoordinator.isWriting else { return false }
        guard saveSourceIfNeeded(for: profile) else { return false }
        selection = .profiles
        selectedProfileID = profile.id
        showApply = true
        return true
    }

    private func setProfileEnabled(_ profile: Profile, enabled: Bool) {
        if !enabled && profile.isActive {
            return
        }
        profile.isEnabled = enabled
        profile.updatedAt = Date()
        do {
            try context.save()
        } catch {
            operationError = localizedError(error)
        }
    }

    private func disableActiveProfile(_ profile: Profile) {
        // 只移除该配置，其它已启用配置的内容继续保留在系统里。
        let remaining = activeProfiles.filter { $0.id != profile.id }
        let content = mergedContent(for: remaining)
        Task {
            do {
                let backupURL = try await writeCoordinator.write(content)
                recordBackup(
                    at: backupURL,
                    profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                    note: l10n.s("停用当前配置前自动备份", "Auto backup before disabling the active profile")
                )
                profile.isActive = false
                profile.isEnabled = false
                profile.updatedAt = Date()
                try context.save()
            } catch {
                operationError = localizedError(error)
            }
        }
    }

    /// 列表视图实时应用：条目变动后把已启用配置的并集立即写回 /etc/hosts。
    /// 用短暂防抖合并连续操作，避免频繁触发特权写入。
    private func scheduleRealtimeApply(for profile: Profile) {
        realtimeApplyTask?.cancel()
        realtimeApplyTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            applyActiveProfilesToSystem(after: profile)
        }
    }

    private func applyActiveProfilesToSystem(after profile: Profile) {
        guard !activeProfiles.isEmpty else { return }
        if writeCoordinator.isWriting {
            // 有写入在进行时稍后重试，保证最后一次编辑也会落盘。
            scheduleRealtimeApply(for: profile)
            return
        }
        if !validationIssues(for: activeProfiles).isEmpty {
            operationError = l10n.s(
                "存在主机名冲突，未写入系统。",
                "Conflicting hostnames were found; not written to the system."
            )
            return
        }
        let content = mergedContent(for: activeProfiles)
        Task {
            do {
                let backupURL = try await writeCoordinator.write(content)
                recordBackup(
                    at: backupURL,
                    profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                    note: l10n.s("列表编辑后实时应用", "Real-time apply after list edit")
                )
                try context.save()
            } catch {
                operationError = localizedError(error)
            }
        }
    }

    private func sourceText(for profile: Profile) -> String {
        if let profileID = profile.id, let draft = sourceDrafts[profileID] {
            return draft
        }
        return localizedSourceText(for: profile, isEnglish: l10n.isEnglish)
    }

    private func sourceBinding(for profile: Profile) -> Binding<String> {
        Binding(
            get: { sourceText(for: profile) },
            set: { value in
                if let profileID = profile.id {
                    sourceDrafts[profileID] = value
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

    private func importCurrentHosts() {
        do {
            let content = try HostsWriter.readContent()
            let entries = HostsParser.parse(content).filter { !$0.isSystem }
            let profile = Profile(context: context)
            profile.id = UUID()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HHmm"
            profile.name = l10n.s(
                "导入 \(formatter.string(from: Date()))",
                "Imported \(formatter.string(from: Date()))"
            )
            profile.isActive = false
            profile.isEnabled = true
            profile.createdAt = Date()
            profile.updatedAt = Date()
            addEntries(entries, to: profile)
            try context.save()
            selectedProfileID = profile.id
            selection = .profiles
        } catch {
            operationError = localizedError(error)
        }
    }

    private func duplicateSelectedProfile() {
        guard let source = selectedProfile, !source.isSystem else { return }
        let profile = Profile(context: context)
        profile.id = UUID()
        let sourceName = source.localizedName(isEnglish: l10n.isEnglish)
        profile.name = l10n.s("\(sourceName) 副本", "\(sourceName) Copy")
        profile.isActive = false
        profile.isEnabled = source.isEnabled
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

    private func recordBackup(at url: URL, profileName: String?, note: String) {
        let record = BackupRecord(context: context)
        record.id = UUID()
        record.timestamp = Date()
        record.filePath = url.path
        record.profileName = profileName
        record.note = note
        do {
            try context.save()
            try BackupMaintenance.prune(context: context)
        } catch {
            operationError = localizedError(error)
        }
    }

    private func localizedError(_ error: Error) -> String {
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
            case .alreadyInProgress:
                return l10n.s("已有写入任务正在进行。", "Another write is already in progress.")
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Sidebar row

enum ProfilePalette {
    private static let palettes: [[Color]] = [
        [.blue, .cyan],
        [.orange, .red],
        [.teal, .green],
        [.indigo, .cyan],
        [.pink, .purple],
        [.mint, .teal],
        [.red, .orange],
        [.cyan, .blue]
    ]

    static func colors(for seed: String) -> [Color] {
        guard !seed.isEmpty else { return palettes[0] }
        var hash = 0
        for scalar in seed.unicodeScalars {
            hash = (hash &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return palettes[hash % palettes.count]
    }
}

struct ProfileRow: View {
    @ObservedObject var profile: Profile
    let isSelected: Bool
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatar(profile: profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.localizedName(isEnglish: l10n.isEnglish))
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var meta: String {
        if profile.isSystem { return l10n.s("系统只读", "System") }
        if !profile.isEnabled { return l10n.s("已停用", "Disabled") }
        let on = profile.sortedEntries.filter(\.isEnabled).count
        if !profile.isActive { return l10n.s("未应用 · \(on) 条启用", "Not applied · \(on) enabled") }
        return l10n.s("已应用 · \(on) 条启用", "Applied · \(on) enabled")
    }
}

struct ProfileAvatar: View {
    @ObservedObject var profile: Profile
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(
                    colors: ProfilePalette.colors(
                        for: profile.id?.uuidString ?? profile.localizedName(isEnglish: l10n.isEnglish)
                    ),
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Text(String(profile.localizedName(isEnglish: l10n.isEnglish).prefix(1)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Profile detail

struct ProfileDetailView: View {
    @ObservedObject var profile: Profile
    @Binding var mode: EntryMode
    @Binding var query: String
    @Binding var sourceText: String
    let isSourceDirty: Bool
    let onApply: () -> Void
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if profile.isSystem {
                SystemHostsView(mode: mode, query: query)
            } else if mode == .list {
                EntriesListView(profile: profile, query: query, isAdding: $isAdding)
            } else {
                SourceEditorView(
                    profile: profile,
                    text: $sourceText,
                    isDirty: isSourceDirty,
                    onApply: onApply,
                    toolbarQuery: query
                )
            }
        }
        .padding(22)
        .onAppear {
            if sourceText.isEmpty {
                sourceText = localizedSourceText(for: profile, isEnglish: l10n.isEnglish)
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .source && sourceText.isEmpty {
                sourceText = localizedSourceText(for: profile, isEnglish: l10n.isEnglish)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(profile.localizedName(isEnglish: l10n.isEnglish))
                        .font(.system(size: 27, weight: .bold))
                    badge
                }
                Text(meta)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !profile.isSystem && mode == .list {
                HStack(spacing: 8) {
                    Button(l10n.s("添加", "Add"), systemImage: "plus") {
                        isAdding = true
                    }
                    .buttonStyle(.glass)
                    .frame(minWidth: 64)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if profile.isSystem {
            Text(l10n.s("系统只读", "System"))
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(.quaternary))
                .foregroundStyle(.secondary)
        } else if profile.isActive {
            Text(l10n.s("当前", "Active"))
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.green.opacity(0.16)))
                .overlay(Capsule().stroke(.green.opacity(0.4)))
                .foregroundStyle(.green)
        } else {
            Text(l10n.s("未应用", "Not applied"))
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.ultraThinMaterial))
                .foregroundStyle(.secondary)
        }
    }

    private var meta: String {
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

}

// MARK: - System (read-only live view)

struct SystemHostsView: View {
    let mode: EntryMode
    let query: String
    @EnvironmentObject private var l10n: Localization
    @State private var revision = 0

    private var live: [ParsedHostEntry] {
        _ = revision
        return HostsParser.parse(HostsWriter.currentContent())
    }

    private var raw: String {
        _ = revision
        return HostsWriter.currentContent()
    }

    private var filtered: [ParsedHostEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return live }
        return live.filter {
            $0.ip.lowercased().contains(q) ||
            $0.hostnames.joined(separator: " ").lowercased().contains(q) ||
            localizedSeedDescription($0.desc, isEnglish: l10n.isEnglish).lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if mode == .list {
                if live.isEmpty {
                    ContentUnavailableView(l10n.s("无法读取 /etc/hosts", "Could not read /etc/hosts"), systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView(l10n.s("没有匹配的条目", "No matching entries"), systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.isEnabled ? "circle.fill" : "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(entry.isEnabled ? .green : .secondary)
                            Text(entry.ip)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                ForEach(entry.hostnames, id: \.self) { host in
                                    Text(host)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(.thinMaterial))
                                        .overlay(Capsule().stroke(.quaternary))
                                }
                            }
                            Spacer(minLength: 8)
                            Text(localizedSeedDescription(entry.desc, isEnglish: l10n.isEnglish))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .opacity(entry.isEnabled ? 1 : 0.6)
                    .listRowSeparator(.hidden)
                    }
                    .listStyle(.inset)
                .alternatingRowBackgrounds(.enabled)
                    .scrollContentBackground(.hidden)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.s("/etc/hosts（系统只读）", "/etc/hosts (system, read-only)"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ReadOnlyHostsTextView(content: raw, query: query)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .onAppear {
            revision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .hostsContentChanged)) { _ in
            revision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            revision += 1
        }
    }
}

struct ReadOnlyHostsTextView: NSViewRepresentable {
    let content: String
    let query: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = content
        scrollView.documentView = textView
        Self.apply(content: content, query: query, to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != content {
            tv.string = content
        }
        Self.apply(content: content, query: query, to: tv)
    }

    private static func apply(content: String, query: String, to tv: NSTextView) {
        SourceTextEditor.applyHighlighting(to: tv)
        guard !query.isEmpty else { return }
        let ns = content as NSString
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.location != NSNotFound {
            let found = ns.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            tv.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: found
            )
            searchRange = NSRange(location: NSMaxRange(found), length: ns.length - NSMaxRange(found))
        }
    }
}

// MARK: - Entries list

struct EntriesListView: View {
    @ObservedObject var profile: Profile
    let query: String
    @Binding var isAdding: Bool
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization
    @State private var deleteError: String?
    @State private var editingID: UUID?
    @State private var draftIP = "127.0.0.1"
    @State private var draftHosts = ""
    @State private var draftDesc = ""
    @State private var draftEnabled = true
    @State private var draftError: String?

    private var filtered: [HostEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let entries = profile.sortedEntries
        guard !q.isEmpty else { return entries }
        return entries.filter {
            ($0.ip ?? "").lowercased().contains(q) ||
            $0.hostList.joined(separator: " ").lowercased().contains(q) ||
            localizedSeedDescription($0.desc, isEnglish: l10n.isEnglish).lowercased().contains(q)
        }
    }

    var body: some View {
        if filtered.isEmpty && !isAdding {
            VStack(spacing: 14) {
                if profile.sortedEntries.isEmpty {
                    ContentUnavailableView(
                        l10n.s("此配置暂无条目", "No entries in this profile"),
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text(l10n.s("点击“新增条目”开始添加", "Click “New Entry” to get started."))
                    )
                    Button(l10n.s("新增条目", "New Entry"), systemImage: "plus") { isAdding = true }
                        .buttonStyle(.glassProminent)
                } else {
                    ContentUnavailableView(
                        l10n.s("没有匹配的条目", "No matching entries"),
                        systemImage: "magnifyingglass"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List {
                    if isAdding {
                        newEntryEditor
                            .id("new-entry-editor")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filtered) { entry in
                        EntryRow(
                            entry: entry,
                            isEditing: editingID == entry.id,
                            isDimmed: (isAdding || editingID != nil) && editingID != entry.id,
                            onBeginEdit: { editingID = entry.id },
                            onEndEdit: { editingID = nil }
                        )
                        .id(entry.id)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.enabled)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .onChange(of: isAdding) { _, adding in
                    if adding {
                        DispatchQueue.main.async {
                            proxy.scrollTo("new-entry-editor", anchor: .top)
                        }
                    }
                }
                .onChange(of: editingID) { _, id in
                    if let id {
                        DispatchQueue.main.async {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .alert(
                l10n.s("删除失败", "Delete Failed"),
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private var newEntryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.s("新增条目", "New Entry"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
            EntryInlineEditor(
                ip: $draftIP,
                hosts: $draftHosts,
                desc: $draftDesc,
                enabled: $draftEnabled,
                error: draftError,
                saveTitle: l10n.s("确认", "Confirm"),
                onCancel: { cancelAdd() },
                onSave: { saveAdd() }
            )
        }
        .padding(.vertical, 6)
    }

    private func cancelAdd() {
        isAdding = false
        draftError = nil
    }

    private func saveAdd() {
        let rawIP = draftIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostList = draftHosts
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .map(String.init)
        guard let normalizedIP = HostsValueValidator.normalizedIP(rawIP), !hostList.isEmpty else {
            draftError = l10n.s("请填写 IP 和至少一个主机名", "Enter an IP and at least one hostname")
            return
        }
        guard hostList.allSatisfy(HostsValueValidator.isValidHostname) else {
            draftError = l10n.s(
                "主机名不能包含空格、井号、斜杠或控制字符。",
                "Hostnames cannot contain whitespace, #, slashes, or control characters."
            )
            return
        }
        guard HostsValueValidator.isValidDescription(draftDesc) else {
            draftError = l10n.s("描述不能包含换行或控制字符。", "The description cannot contain newlines or control characters.")
            return
        }

        let otherEntries = profile.sortedEntries.map {
            ParsedHostEntry(ip: $0.ip ?? "", hostnames: $0.hostList, isEnabled: $0.isEnabled)
        }
        let candidate = ParsedHostEntry(ip: normalizedIP, hostnames: hostList)
        let hostSet = Set(hostList.map { $0.lowercased() })
        if let issue = HostValidator.issues(entries: otherEntries + [candidate])
            .first(where: { hostSet.contains($0.hostname) }) {
            draftError = issue.kind == .conflict
                ? l10n.s("此主机名已指向另一个 IP。", "This hostname already points to a different IP.")
                : l10n.s("此条目已存在。", "This entry already exists.")
            return
        }

        let entry = HostEntry(context: context)
        entry.id = UUID()
        entry.sortIndex = Int64(profile.sortedEntries.count)
        entry.profile = profile
        entry.ip = normalizedIP
        entry.hostnames = hostList
        entry.desc = draftDesc
        entry.isEnabled = draftEnabled
        entry.isSystem = false
        entry.createdAt = Date()
        do {
            try context.save()
            if let profileID = profile.id {
                NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
            }
            isAdding = false
            draftIP = "127.0.0.1"
            draftHosts = ""
            draftDesc = ""
            draftEnabled = true
            draftError = nil
        } catch {
            draftError = error.localizedDescription
        }
    }
}

struct EntryRow: View {
    @ObservedObject var entry: HostEntry
    let isEditing: Bool
    let isDimmed: Bool
    let onBeginEdit: () -> Void
    let onEndEdit: () -> Void
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization
    @State private var editIP = ""
    @State private var editHosts = ""
    @State private var editDesc = ""
    @State private var editEnabled = true
    @State private var saveError: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                row
            }
        }
        .padding(.vertical, 4)
        .opacity(entry.isEnabled || isEditing ? 1 : 0.6)
        .opacity(isDimmed ? 0.35 : 1)
        .alert(
            l10n.s("保存失败", "Save Failed"),
            isPresented: Binding(
                get: { saveError != nil && !isEditing },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { newValue in
                    let previous = entry.isEnabled
                    entry.isEnabled = newValue
                    do {
                        try context.save()
                        if let profileID = entry.profile?.id {
                            NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
                        }
                    } catch {
                        entry.isEnabled = previous
                        saveError = error.localizedDescription
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .disabled(entry.isSystem)

            Text(entry.ip ?? "")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)

            HStack(spacing: 5) {
                ForEach(entry.hostList, id: \.self) { host in
                    Text(host)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.thinMaterial))
                        .overlay(Capsule().stroke(.quaternary))
                }
            }
            .frame(minWidth: 120, alignment: .leading)

            Spacer(minLength: 8)

            Text(localizedSeedDescription(entry.desc, isEnglish: l10n.isEnglish))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            flagBadge

            iconActionButton(systemName: "pencil", help: l10n.s("编辑", "Edit")) {
                beginEdit()
            }
            .disabled(entry.isSystem)

            iconActionButton(systemName: "trash", help: l10n.s("删除", "Delete")) {
                showDeleteConfirm = true
            }
            .disabled(entry.isSystem)
            .popover(isPresented: $showDeleteConfirm, arrowEdge: .bottom) {
                ConfirmPopover(
                    title: l10n.s("删除此条目？", "Delete this entry?"),
                    message: l10n.s("此操作无法撤销。", "This action cannot be undone."),
                    cancelTitle: l10n.s("取消", "Cancel"),
                    confirmTitle: l10n.s("删除", "Delete"),
                    onCancel: { showDeleteConfirm = false },
                    onConfirm: {
                        showDeleteConfirm = false
                        delete()
                    }
                )
            }
        }
    }

    private func iconActionButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 32, height: 20)
                .contentShape(Rectangle())
        }
        .controlSize(.mini)
        .buttonBorderShape(.capsule)
        .buttonStyle(.glass)
        .frame(width: 32, height: 20)
        .help(help)
    }

    private var editor: some View {
        EntryInlineEditor(
            ip: $editIP,
            hosts: $editHosts,
            desc: $editDesc,
            enabled: $editEnabled,
            error: saveError,
            saveTitle: l10n.s("确认", "Confirm"),
            onCancel: { cancelEdit() },
            onSave: { saveEdit() }
        )
    }

    @ViewBuilder
    private var flagBadge: some View {
        let entryHosts = Set(entry.hostList.map { $0.lowercased() })
        if let profile = entry.profile {
            let issues = HostValidator.issues(entries: profile.sortedEntries.map {
                ParsedHostEntry(ip: $0.ip ?? "", hostnames: $0.hostList, isEnabled: $0.isEnabled, isSystem: $0.isSystem)
            }).filter { entryHosts.contains($0.hostname) }
            if let issue = issues.first {
                Image(systemName: issue.kind == .conflict ? "exclamationmark.triangle.fill" : "doc.on.doc.fill")
                    .foregroundStyle(issue.kind == .conflict ? .orange : .green)
                    .help(issue.kind == .conflict ? l10n.s("冲突", "Conflict") : l10n.s("重复", "Duplicate"))
            }
        }
    }

    private func beginEdit() {
        editIP = entry.ip ?? ""
        editHosts = entry.hostList.joined(separator: " ")
        editDesc = entry.desc ?? ""
        editEnabled = entry.isEnabled
        saveError = nil
        onBeginEdit()
    }

    private func cancelEdit() {
        saveError = nil
        onEndEdit()
    }

    private func saveEdit() {
        let rawIP = editIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostList = editHosts
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .map(String.init)
        guard let normalizedIP = HostsValueValidator.normalizedIP(rawIP), !hostList.isEmpty else {
            saveError = l10n.s("请填写 IP 和至少一个主机名", "Enter an IP and at least one hostname")
            return
        }
        guard hostList.allSatisfy(HostsValueValidator.isValidHostname) else {
            saveError = l10n.s(
                "主机名不能包含空格、井号、斜杠或控制字符。",
                "Hostnames cannot contain whitespace, #, slashes, or control characters."
            )
            return
        }
        guard HostsValueValidator.isValidDescription(editDesc) else {
            saveError = l10n.s("描述不能包含换行或控制字符。", "The description cannot contain newlines or control characters.")
            return
        }
        guard let profile = entry.profile else {
            saveError = l10n.s("无法定位所属配置。", "Unable to locate the owning profile.")
            return
        }

        let otherEntries = profile.sortedEntries
            .filter { $0.objectID != entry.objectID }
            .map {
                ParsedHostEntry(
                    ip: $0.ip ?? "",
                    hostnames: $0.hostList,
                    isEnabled: $0.isEnabled
                )
            }
        let candidate = ParsedHostEntry(ip: normalizedIP, hostnames: hostList)
        let hostSet = Set(hostList.map { $0.lowercased() })
        if let issue = HostValidator.issues(entries: otherEntries + [candidate])
            .first(where: { hostSet.contains($0.hostname) }) {
            saveError = issue.kind == .conflict
                ? l10n.s("此主机名已指向另一个 IP。", "This hostname already points to a different IP.")
                : l10n.s("此条目已存在。", "This entry already exists.")
            return
        }

        entry.ip = normalizedIP
        entry.hostnames = hostList
        entry.desc = editDesc
        entry.isEnabled = editEnabled
        do {
            try context.save()
            if let profileID = profile.id {
                NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
            }
            onEndEdit()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete() {
        guard !entry.isSystem else { return }
        let profileID = entry.profile?.id
        context.delete(entry)
        do {
            try context.save()
            if let profileID {
                NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Inline confirmation popover

struct ConfirmPopover: View {
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(cancelTitle, role: .cancel) {
                    onCancel()
                }
                .controlSize(.small)
                .buttonStyle(.glass)
                Button(confirmTitle, role: .destructive) {
                    onConfirm()
                }
                .controlSize(.small)
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

typealias DeleteConfirmPopover = ConfirmPopover

// MARK: - Inline entry editor

struct EntryInlineEditor: View {
    @Binding var ip: String
    @Binding var hosts: String
    @Binding var desc: String
    @Binding var enabled: Bool
    let error: String?
    let saveTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("127.0.0.1 / ::1", text: $ip)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                TextField("example.com www.example.com", text: $hosts)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                TextField(l10n.s("描述", "Description"), text: $desc)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text(l10n.s("启用", "Enabled"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button(l10n.s("取消", "Cancel")) { onCancel() }
                    .buttonStyle(.glass)
                Button(saveTitle) { onSave() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

// MARK: - Source editor

struct SourceStatus: Equatable {
    var line = 1
    var column = 1
    var totalLines = 1
    var enabledEntries = 0
    var totalEntries = 0
    var validationMessage: String?
    var findMatches = 0
    var findIndex = 0
}

final class SourceEditorProxy: ObservableObject {
    @Published var status = SourceStatus()
    weak var textView: NSTextView?
    private var findRanges: [NSRange] = []
    private var findQuery = ""

    func refreshStatus() {
        guard let tv = textView else { return }
        let string = tv.string
        let ns = string as NSString
        let location = min(tv.selectedRange().location, ns.length)
        let lineStart = ns.lineRange(for: NSMakeRange(location, 0)).location
        let line = ns.substring(to: lineStart).components(separatedBy: "\n").count + 1
        let column = location - lineStart + 1
        let entries = HostsParser.parse(string)
        let newStatus = SourceStatus(
            line: line,
            column: column,
            totalLines: string.isEmpty ? 1 : max(1, ns.components(separatedBy: "\n").count),
            enabledEntries: entries.filter(\.isEnabled).count,
            totalEntries: entries.count,
            validationMessage: HostsValueValidator.validate(content: string),
            findMatches: findRanges.count,
            findIndex: findRanges.isEmpty ? 0 : status.findIndex
        )
        guard newStatus != status else { return }
        status = newStatus
        if let ruler = tv.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            ruler.needsDisplay = true
        }
    }

    func applyFindHighlight(query: String) {
        guard let tv = textView else { return }
        let string = tv.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
        findRanges.removeAll()
        guard !query.isEmpty else {
            findQuery = ""
            status.findMatches = 0
            status.findIndex = 0
            return
        }
        findQuery = query
        var searchRange = NSRange(location: 0, length: string.length)
        while searchRange.location != NSNotFound {
            let found = string.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            findRanges.append(found)
            searchRange = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
        }
        for range in findRanges {
            tv.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: range
            )
        }
        status.findMatches = findRanges.count
        status.findIndex = findRanges.isEmpty ? 0 : 1
        objectWillChange.send()
    }

    func prepareFind(query: String) {
        applyFindHighlight(query: query)
    }

    func reapplyFindHighlight() {
        applyFindHighlight(query: findQuery)
    }

    @discardableResult
    func findNext() -> Int {
        guard textView != nil, !findRanges.isEmpty else { return 0 }
        let current = status.findIndex
        let nextIndex = current >= findRanges.count ? 0 : current
        selectMatch(at: nextIndex)
        return nextIndex + 1
    }

    @discardableResult
    func findPrevious() -> Int {
        guard textView != nil, !findRanges.isEmpty else { return 0 }
        let current = status.findIndex
        let previousIndex = current <= 1 ? findRanges.count - 1 : current - 2
        selectMatch(at: previousIndex)
        return previousIndex + 1
    }

    func replaceAll(query: String, replacement: String) -> Int {
        guard let tv = textView, !query.isEmpty else { return 0 }
        let string = tv.string
        let replaced = string.replacingOccurrences(
            of: query,
            with: replacement,
            options: [.caseInsensitive]
        )
        guard replaced != string else {
            prepareFind(query: query)
            return 0
        }
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard tv.shouldChangeText(in: fullRange, replacementString: replaced) else {
            prepareFind(query: query)
            return 0
        }
        tv.textStorage?.replaceCharacters(in: fullRange, with: replaced)
        tv.didChangeText()
        prepareFind(query: query)
        return (string as NSString).components(separatedBy: query).count - 1
    }

    func toggleCommentOnSelection() {
        guard let tv = textView else { return }
        let full = tv.string as NSString
        guard full.length > 0 else { return }

        let selected = tv.selectedRange()
        let location = min(selected.location, full.length)
        let end = selected.length == 0
            ? location
            : min(selected.location + selected.length - 1, max(0, full.length - 1))
        let combined = NSUnionRange(
            full.lineRange(for: NSMakeRange(location, 0)),
            full.lineRange(for: NSMakeRange(end, 0))
        )
        let block = full.substring(with: combined)
        let firstNonEmpty = block.components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "#"
        let shouldComment = !firstNonEmpty.hasPrefix("#")
        let toggled = block.components(separatedBy: "\n").map { line -> String in
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { return line }
            return shouldComment ? "# " + line : String(stripped.dropFirst()).trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")

        guard tv.shouldChangeText(in: combined, replacementString: toggled) else { return }
        tv.textStorage?.replaceCharacters(in: combined, with: toggled)
        tv.didChangeText()
        tv.setSelectedRange(NSMakeRange(combined.location, 0))
    }

    private func selectMatch(at index: Int) {
        guard let tv = textView, findRanges.indices.contains(index) else { return }
        let range = findRanges[index]
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        status.findIndex = index + 1
        objectWillChange.send()
    }
}

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.textView = textView
        ruleThickness = 42
        clientView = textView
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView,
              let layoutManager = tv.layoutManager,
              let textContainer = tv.textContainer else { return }

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(rect: NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height)).fill()

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: tv.visibleRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        let string = tv.string as NSString
        guard string.length > 0 else { return }

        var lineRange = string.lineRange(for: NSMakeRange(visibleCharacterRange.location, 0))
        var lineNumber = string.substring(to: lineRange.location)
            .components(separatedBy: "\n").count + 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        while lineRange.location < NSMaxRange(visibleCharacterRange) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let convertedPoint = convert(
                NSPoint(x: 0, y: lineRect.minY + tv.textContainerOrigin.y),
                from: tv
            )
            let labelPoint = NSPoint(x: 6, y: convertedPoint.y + 2)
            NSString(string: "\(lineNumber)").draw(at: labelPoint, withAttributes: attributes)
            lineNumber += 1

            let next = string.lineRange(for: NSMakeRange(NSMaxRange(lineRange), 0))
            if next.location == lineRange.location { break }
            lineRange = next
        }
    }
}

struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    var proxy: SourceEditorProxy

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, proxy: proxy) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
        proxy.textView = textView
        Self.applyHighlighting(to: textView)
        proxy.refreshStatus()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        let changed = tv.string != text
        if changed {
            tv.string = text
            Self.applyHighlighting(to: tv)
            proxy.refreshStatus()
            proxy.reapplyFindHighlight()
        }
        proxy.textView = tv
    }

    static func applyHighlighting(to tv: NSTextView) {
        let full = tv.string
        let ns = full as NSString
        let baseRange = NSRange(location: 0, length: ns.length)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let storage = tv.textStorage
        tv.undoManager?.disableUndoRegistration()
        storage?.beginEditing()
        storage?.addAttribute(.font, value: mono, range: baseRange)
        storage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: baseRange)
        storage?.removeAttribute(.backgroundColor, range: baseRange)
        if ns.length > 0 {
            ns.enumerateSubstrings(in: baseRange, options: [.byLines]) { substring, lineRange, _, _ in
                guard let line = substring else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return }
                if trimmed.hasPrefix("#") {
                    storage?.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                } else if HostsParser.parse(line).isEmpty {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemRed, range: lineRange)
                } else {
                    applyTokenColors(line: line, lineRange: lineRange, storage: storage)
                }
            }
        }
        storage?.endEditing()
        tv.undoManager?.enableUndoRegistration()
    }

    private static func applyTokenColors(line: String, lineRange: NSRange, storage: NSTextStorage?) {
        let nsLine = line as NSString
        let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
        var scanLocation = 0
        var isFirst = true

        while scanLocation < nsLine.length {
            let remaining = NSRange(location: scanLocation, length: nsLine.length - scanLocation)
            let found = nsLine.rangeOfCharacter(from: nonWhitespace, options: [], range: remaining)
            if found.location == NSNotFound { break }

            var end = found.location + found.length
            while end < nsLine.length,
                  let scalar = Unicode.Scalar(nsLine.character(at: end)),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                end += 1
            }
            let tokenRange = NSRange(location: found.location, length: end - found.location)
            let token = nsLine.substring(with: tokenRange)
            let absoluteRange = NSRange(location: lineRange.location + tokenRange.location, length: tokenRange.length)

            if token.hasPrefix("#") {
                storage?.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: absoluteRange)
                break
            } else if isFirst {
                storage?.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: absoluteRange)
                isFirst = false
            } else {
                storage?.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: absoluteRange)
            }
            scanLocation = end
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let proxy: SourceEditorProxy

        init(text: Binding<String>, proxy: SourceEditorProxy) {
            self.text = text
            self.proxy = proxy
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            SourceTextEditor.applyHighlighting(to: tv)
            proxy.refreshStatus()
            proxy.reapplyFindHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            proxy.refreshStatus()
        }
    }
}

struct SourceEditorView: View {
    @ObservedObject var profile: Profile
    @Binding var text: String
    let isDirty: Bool
    let onApply: () -> Void
    let toolbarQuery: String
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization
    @StateObject private var proxy = SourceEditorProxy()
    @State private var showFind = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var validationMessage: String?
    @FocusState private var isReplaceFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(l10n.s("编辑", "Edit"), systemImage: "pencil")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                if isDirty {
                    Text(l10n.s("未应用", "Unapplied"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if validationMessage == nil {
                    Label(l10n.s("校验通过", "Valid"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(validationMessage ?? "")
                }
                
                Button(l10n.s("校验", "Validate")) {
                    validate()
                }
                .buttonStyle(.glass)
                
                Button {
                    showFind.toggle()
                    isReplaceFieldFocused = showFind
                } label: {
                    Label(l10n.s("替换", "Replace"), systemImage: "arrow.2.squarepath")
                }
                .buttonStyle(.glass)
                .help(l10n.s("查找与替换", "Find and Replace"))

                Button {
                    onApply()
                } label: {
                    Label(l10n.s("应用", "Apply"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.glassProminent)
                .disabled(validationMessage != nil || !profile.isEnabled)
                .accessibilityIdentifier("apply-profile-button")
                .help(l10n.s("预览后写入 /etc/hosts", "Preview, then write to /etc/hosts"))
            }

            if showFind {
                HStack(spacing: 8) {
                    TextField(l10n.s("查找", "Find"), text: $findText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    Button {
                        _ = proxy.findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 24, height: 16)
                    }
                    .buttonStyle(.glass)
                    Button {
                        _ = proxy.findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 24, height: 16)
                    }
                    .buttonStyle(.glass)
                    TextField(l10n.s("替换", "Replace"), text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .focused($isReplaceFieldFocused)
                    Button(l10n.s("全部替换", "Replace All")) {
                        _ = proxy.replaceAll(query: findText, replacement: replaceText)
                    }
                    .buttonStyle(.glass)
                    Button(l10n.s("完成", "Done")) {
                        showFind = false
                        isReplaceFieldFocused = false
                    }
                    .buttonStyle(.glass)
                }
                .font(.system(size: 12))
                .onChange(of: findText) { _, newValue in
                    proxy.prepareFind(query: newValue)
                }
            }

            SourceTextEditor(text: $text, proxy: proxy)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                Text("\(proxy.status.line):\(proxy.status.column)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !findText.isEmpty {
                    Text("\(proxy.status.findIndex)/\(proxy.status.findMatches)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(l10n.s("\(proxy.status.totalLines) 行", "\(proxy.status.totalLines) lines"))
                Text(l10n.s(
                    "启用 \(proxy.status.enabledEntries) / 共 \(proxy.status.totalEntries)",
                    "Enabled \(proxy.status.enabledEntries) of \(proxy.status.totalEntries)"
                ))
                Text(l10n.s("写入前自动备份", "Backup before write"))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .onAppear {
            validate()
            proxy.refreshStatus()
            proxy.applyFindHighlight(query: toolbarQuery)
        }
        .onChange(of: toolbarQuery) { _, newValue in
            proxy.applyFindHighlight(query: newValue)
        }
        .onChange(of: text) { _, _ in
            validate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceFind)) { _ in
            showFind = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceToggleComment)) { _ in
            proxy.toggleCommentOnSelection()
            validate()
        }
    }

    private func validate() {
        validationMessage = HostsValueValidator.validate(content: text)
    }
}

// MARK: - Backups

struct BackupsView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BackupRecord.timestamp, ascending: false)])
    private var backups: FetchedResults<BackupRecord>
    @EnvironmentObject private var l10n: Localization
    @Environment(\.managedObjectContext) private var context
    @State private var previewBackup: BackupRecord?
    @State private var restoreBackup: BackupRecord?
    @State private var restoreMessage: String?
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n.s("备份", "Backups"))
                .font(.system(size: 26, weight: .bold))
            Text(l10n.s("每次写入前自动生成时间戳备份，可查看并还原。", "Timestamped backups are created before each write. View or restore anytime."))
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)

            if backups.isEmpty {
                ContentUnavailableView(l10n.s("暂无备份", "No backups"), systemImage: "clock.arrow.circlepath")
            } else {
                List(backups) { backup in
                    BackupRow(
                        backup: backup,
                        onView: { previewBackup = backup },
                        onDelete: { delete(backup) }
                    )
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.enabled)
                .scrollContentBackground(.hidden)
                .background(.clear)
            }
        }
        .padding(22)
        .sheet(item: $previewBackup) { backup in
            BackupPreviewSheet(backup: backup) {
                previewBackup = nil
                restoreBackup = backup
            }
        }
        .onAppear {
            do {
                try BackupMaintenance.prune(context: context)
            } catch {
                restoreMessage = error.localizedDescription
            }
        }
        .confirmationDialog(l10n.s("还原此备份？", "Restore this backup?"), isPresented: restoreBinding, titleVisibility: .visible) {
            Button(l10n.s("覆盖 /etc/hosts", "Overwrite /etc/hosts")) { restore(asNewProfile: false) }
            Button(l10n.s("恢复为新配置", "Restore as New Profile")) { restore(asNewProfile: true) }
            Button(l10n.s("取消", "Cancel"), role: .cancel) { restoreBackup = nil }
        } message: {
            Text(l10n.s("将用备份内容覆盖 /etc/hosts，覆盖前会先备份当前文件。", "The backup will overwrite /etc/hosts. The current file is backed up first."))
        }
        .alert(l10n.s("还原结果", "Restore Result"), isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { restoreBackup != nil }, set: { if !$0 { restoreBackup = nil } })
    }

    private func restore(asNewProfile: Bool) {
        guard let backup = restoreBackup, let path = backup.filePath,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            restoreMessage = l10n.s("备份文件不存在或无法读取。", "The backup file is missing or unreadable.")
            restoreBackup = nil
            return
        }
        restoreBackup = nil
        if asNewProfile {
            let profile = Profile(context: context)
            profile.id = UUID()
            profile.name = l10n.s(
                "从备份恢复 \(Date().formatted(date: .abbreviated, time: .shortened))",
                "Restored \(Date().formatted(date: .abbreviated, time: .shortened))"
            )
            profile.isActive = false
            profile.isEnabled = true
            profile.createdAt = Date()
            profile.updatedAt = Date()
            for (index, item) in HostsParser.parse(content).filter({ !$0.isSystem }).enumerated() {
                let entry = HostEntry(context: context)
                entry.id = UUID()
                entry.profile = profile
                entry.ip = item.ip
                entry.hostnames = item.hostnames
                entry.desc = item.desc
                entry.isEnabled = item.isEnabled
                entry.isSystem = false
                entry.sortIndex = Int64(index)
                entry.createdAt = Date()
            }
            do {
                try context.save()
                restoreMessage = l10n.s("已恢复为新配置。", "Restored as a new profile.")
            } catch {
                restoreMessage = error.localizedDescription
            }
            return
        }
        Task {
            do {
                let backupURL = try await writeCoordinator.write(content)
                let record = BackupRecord(context: context)
                record.id = UUID()
                record.timestamp = Date()
                record.filePath = backupURL.path
                record.note = l10n.s("还原备份前自动备份", "Auto backup before restore")
                try context.save()
                try BackupMaintenance.prune(context: context)
                await MainActor.run { restoreMessage = l10n.s("已还原备份", "Backup restored") }
            } catch {
                await MainActor.run { restoreMessage = error.localizedDescription }
            }
        }
    }

    private func delete(_ backup: BackupRecord) {
        if let path = backup.filePath {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    restoreMessage = l10n.s(
                        "无法删除备份文件，记录已保留。",
                        "Unable to delete the backup file; its record was kept."
                    )
                    return
                }
            }
        }
        context.delete(backup)
        do {
            try context.save()
        } catch {
            restoreMessage = error.localizedDescription
        }
    }
}

struct BackupRow: View {
    @ObservedObject var backup: BackupRecord
    let onView: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var l10n: Localization
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text((backup.filePath as NSString?)?.lastPathComponent ?? "")
                    .font(.system(.body, design: .monospaced))
                Text(localizedBackupNote(backup.note, isEnglish: l10n.isEnglish))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button(l10n.s("查看", "View"), systemImage: "eye") {
                onView()
            }
            .buttonStyle(.glass)

            Button(l10n.s("删除", "Delete"), systemImage: "trash") {
                showDeleteConfirm = true
            }
            .buttonStyle(.glass)
            .popover(isPresented: $showDeleteConfirm, arrowEdge: .bottom) {
                ConfirmPopover(
                    title: l10n.s("删除此备份？", "Delete this backup?"),
                    message: l10n.s("此操作无法撤销。", "This action cannot be undone."),
                    cancelTitle: l10n.s("取消", "Cancel"),
                    confirmTitle: l10n.s("删除", "Delete"),
                    onCancel: { showDeleteConfirm = false },
                    onConfirm: {
                        showDeleteConfirm = false
                        onDelete()
                    }
                )
            }
        }
        .listRowSeparator(.hidden)
    }
}

struct BackupPreviewSheet: View {
    let backup: BackupRecord
    let onRestore: () -> Void
    @EnvironmentObject private var l10n: Localization
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((backup.filePath as NSString?)?.lastPathComponent ?? "")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
            Divider()
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Spacer()
                Button(l10n.s("还原", "Restore"), systemImage: "arrow.uturn.backward") {
                    onRestore()
                }
                .buttonStyle(.glassProminent)
                .disabled(backup.filePath == nil)
                Button(l10n.s("关闭", "Close")) { dismiss() }.buttonStyle(.glass)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .buttonBorderShape(.capsule)
    }

    private var content: String {
        guard let path = backup.filePath else { return "" }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}

// MARK: - Helper guide

struct HelperGuideSheet: View {
    @EnvironmentObject private var l10n: Localization
    @State private var message: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s("启用后台写入助手", "Enable the Background Writer Helper"))
                        .font(.system(size: 20, weight: .bold))
                    Text(l10n.s("后台功能需要启用后才能使用。", "This background feature only works while it's enabled."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                guideRow(
                    icon: "bolt.fill",
                    title: l10n.s("静默写入 /etc/hosts", "Silent writes to /etc/hosts"),
                    detail: l10n.s("修改 hosts 时不再每次输入管理员密码。", "Hosts changes are written without asking for your admin password each time.")
                )
                guideRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: l10n.s("自动应用配置", "Automatic profile apply"),
                    detail: l10n.s("切换配置、实时应用都会在后台自动完成。", "Profile switches and real-time applies complete automatically in the background.")
                )
                guideRow(
                    icon: "lock.shield",
                    title: l10n.s("仅本应用可用", "Only this app can call it"),
                    detail: l10n.s("助手只接受本应用签名调用，安全可靠。", "The helper only accepts calls from this signed app.")
                )
            }

            Divider()

            Text(l10n.s("如何启用", "How to enable"))
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                guideStep(1, l10n.s("点击下方“立即启用”。", "Tap Enable Now below."))
                guideStep(2, l10n.s(
                    "在弹出的系统设置 → 通用 → 登录项与扩展中，找到 Hosts Manager 并打开助手。",
                    "In System Settings > General > Login Items & Extensions, find Hosts Manager and turn on the helper."
                ))
            }

            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(l10n.s("暂不启用", "Not Now")) {
                    onClose()
                }
                .buttonStyle(.glass)

                Button(l10n.s("立即启用", "Enable Now")) {
                    let error = HostsHelperClient.enable(isEnglish: l10n.isEnglish)
                    if let error {
                        message = error
                    } else if HostsHelperClient.isRegistered {
                        onClose()
                    } else {
                        message = l10n.s(
                            "已请求启用，请在系统设置中允许后返回。",
                            "Enable requested. Allow it in System Settings, then come back."
                        )
                        HostsHelperClient.openSystemSettingsLoginItems()
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12.5))
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @FetchRequest private var settings: FetchedResults<AppSettings>
    @EnvironmentObject private var l10n: Localization
    @AppStorage("appearance") private var appearance = "system"
    @State private var retention = 30
    @State private var defaultView = EntryMode.list.rawValue
    @State private var helperStatus = ""
    @State private var installMessage: String?
    @State private var settingsError: String?
    init() {
        _settings = FetchRequest(sortDescriptors: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.s("设置", "Settings"))
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                SettingsRow(label: l10n.s("默认视图", "Default view")) {
                    Picker("", selection: $defaultView) {
                        Label(l10n.s("列表", "List"), systemImage: "list.bullet").tag(EntryMode.list.rawValue)
                        Label(l10n.s("编辑", "Edit"), systemImage: "pencil").tag(EntryMode.source.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                Divider()
                SettingsRow(label: l10n.s("备份保留数量", "Backup retention")) {
                    Stepper("\(retention)", value: $retention, in: 1...100)
                }
                Divider()
                SettingsRow(label: l10n.s("界面语言", "Interface language")) {
                    Picker("", selection: $l10n.language) {
                        Text(l10n.s("跟随系统", "Follow system")).tag("system")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                Divider()
                SettingsRow(label: l10n.s("外观", "Appearance")) {
                    Picker("", selection: $appearance) {
                        Text(l10n.s("跟随系统", "Follow system")).tag("system")
                        Text(l10n.s("浅色", "Light")).tag("light")
                        Text(l10n.s("深色", "Dark")).tag("dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary.opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(.blue)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.s("后台写入助手：\(helperStatus)", "Background Writer Helper: \(helperStatus)"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Text(l10n.s(
                        "启用后可静默写入 /etc/hosts，无需每次输入管理员密码，切换配置与实时应用都会在后台自动完成。助手仅接受本应用的签名调用。",
                        "When enabled, hosts changes are written silently without asking for your admin password each time, and profile switches and real-time applies complete automatically in the background. The helper only accepts calls signed by this app."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    if let installMessage {
                        installMessageView(installMessage)
                    }
                    if !HostsHelperClient.isRegistered {
                        Button(l10n.s("启用助手", "Enable Helper")) {
                            let error = HostsHelperClient.enable(isEnglish: l10n.isEnglish)
                            if let error {
                                installMessage = error
                            } else if HostsHelperClient.isRegistered {
                                installMessage = l10n.s("助手已启用。", "Helper is enabled.")
                            } else {
                                installMessage = l10n.s(
                                    "已请求启用，请在系统设置中允许后返回。",
                                    "Enable requested. Allow it in System Settings, then come back."
                                )
                                HostsHelperClient.openSystemSettingsLoginItems()
                            }
                            refreshHelperStatus()
                        }
                        .buttonStyle(.glass)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary.opacity(0.4)))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshHelperStatus()
            if let s = settings.first {
                retention = Int(s.backupRetention)
                defaultView = s.defaultView ?? EntryMode.list.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshHelperStatus()
        }
        .onChange(of: defaultView) { _, newValue in
            settings.first?.defaultView = newValue
            saveSettings()
            NotificationCenter.default.post(name: .defaultEntryModeChanged, object: newValue)
        }
        .onChange(of: retention) { _, newValue in
            settings.first?.backupRetention = Int64(newValue)
            saveSettings()
            if let context = settings.first?.managedObjectContext,
               (try? BackupMaintenance.prune(context: context)) == nil {
                settingsError = l10n.s("无法清理旧备份。", "Unable to prune old backups.")
            }
        }
        .alert(
            l10n.s("保存设置失败", "Unable to Save Settings"),
            isPresented: Binding(
                get: { settingsError != nil },
                set: { if !$0 { settingsError = nil } }
            )
        ) {
            Button("OK") { settingsError = nil }
        } message: {
            Text(settingsError ?? "")
        }
    }

    private func refreshHelperStatus() {
        helperStatus = HostsHelperClient.statusLabel(isEnglish: l10n.isEnglish)
    }

    private func installMessageView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.orange)
    }

    private func saveSettings() {
        guard let context = settings.first?.managedObjectContext else { return }
        do {
            try context.save()
        } catch {
            settingsError = error.localizedDescription
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 170, alignment: .leading)
            Spacer()
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// MARK: - Apply flow

struct ApplySheet: View {
    let profile: Profile
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: Localization
    @State private var phase: Phase = .preview
    @State private var writeError: String?
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared

    enum Phase { case preview, writing, done }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case .preview: preview
            case .writing: writing
            case .done: result
            }
        }
        .frame(width: 620, height: 500)
        .padding(22)
        .buttonBorderShape(.capsule)
    }

    private var otherActiveProfiles: [Profile] {
        let all = (try? context.fetch(Profile.fetchRequest())) ?? []
        return all.filter { $0.isActive && !$0.isSystem && $0.id != profile.id }
    }

    private var target: String {
        HostsParser.mergedContent(entries: parsed)
    }

    private var parsed: [ParsedHostEntry] {
        // 应用时把其它已启用配置的条目一并合并，预览和冲突检查都以并集为准。
        (otherActiveProfiles + [profile]).flatMap { p in
            p.sortedEntries.map {
                ParsedHostEntry(
                    ip: $0.ip ?? "",
                    hostnames: $0.hostList,
                    desc: localizedSeedDescription($0.desc, isEnglish: l10n.isEnglish),
                    isEnabled: $0.isEnabled,
                    isSystem: $0.isSystem
                )
            }
        }
    }

    private var validationIssues: [HostIssue] {
        HostValidator.issues(entries: parsed.filter(\.isEnabled))
    }

    private var duplicateIssues: [HostIssue] {
        validationIssues.filter { $0.kind == .duplicate }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.s(
                "应用“\(profile.localizedName(isEnglish: l10n.isEnglish))”",
                "Apply “\(profile.localizedName(isEnglish: l10n.isEnglish))”"
            ))
                .font(.system(size: 20, weight: .bold))
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.green)
                Text(l10n.s("写入前将自动备份当前 /etc/hosts 到备份目录，可随时还原。", "The current /etc/hosts will be backed up before writing and can be restored anytime."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.green.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.green.opacity(0.3)))

            if !validationIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        l10n.s("存在主机名冲突或重复条目", "Hostname conflicts or duplicates must be resolved"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.orange)
                    Text(validationIssues.map(\.hostname).joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !duplicateIssues.isEmpty {
                        Button(l10n.s("移除完全重复条目", "Remove Exact Duplicates")) {
                            removeExactDuplicates()
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.1)))
            }

            diffView
            Spacer()
            HStack {
                Spacer()
                Button(l10n.s("取消", "Cancel")) { dismiss() }.buttonStyle(.glass)
                Button(l10n.s("确认应用", "Confirm Apply")) { startWrite() }.buttonStyle(.glassProminent)
                    .disabled(!validationIssues.isEmpty || writeCoordinator.isWriting)
                    .accessibilityIdentifier("confirm-apply-button")
            }
        }
    }

    private var writing: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(l10n.s("正在写入 /etc/hosts…", "Writing to /etc/hosts…"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 14) {
            if writeError == nil {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                    Text(l10n.s(
                        "已应用“\(profile.localizedName(isEnglish: l10n.isEnglish))”到 /etc/hosts",
                        "Applied “\(profile.localizedName(isEnglish: l10n.isEnglish))” to /etc/hosts"
                    ))
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(l10n.s("备份已保存到备份目录。", "A backup was saved to the backup folder."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                    Text(l10n.s("写入失败", "Write failed"))
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(writeError ?? "")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            diffView
            Spacer()
            HStack {
                Spacer()
                Button(l10n.s("完成", "Done")) { dismiss() }.buttonStyle(.glassProminent)
            }
        }
    }

    private var diffView: some View {
        let before = HostsParser.serialize(HostsParser.parse(HostsWriter.currentContent()))
        let after = target
        let diff = lineDiff(before, after)
        return VStack(alignment: .leading, spacing: 4) {
            Text(l10n.s("预览", "Preview"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                if diff.isEmpty {
                    Text(l10n.s("内容无变化", "No changes"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(diff.indices, id: \.self) { i in
                            let item = diff[i]
                            Text(item.kind == 0 ? "− \(item.line)" : "+ \(item.line)")
                                .foregroundStyle(item.kind == 0 ? .red : .green)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxHeight: 220)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        }
    }

    private struct DiffLine {
        let kind: Int // 0 = removed, 1 = added
        let line: String
    }

    private func lineDiff(_ before: String, _ after: String) -> [DiffLine] {
        let b = before.components(separatedBy: "\n")
        let a = after.components(separatedBy: "\n")
        let m = b.count, n = a.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in stride(from: m - 1, through: 0, by: -1) {
            for j in stride(from: n - 1, through: 0, by: -1) {
                dp[i][j] = b[i] == a[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < m && j < n {
            if b[i] == a[j] {
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                result.append(DiffLine(kind: 0, line: b[i])); i += 1
            } else {
                result.append(DiffLine(kind: 1, line: a[j])); j += 1
            }
        }
        while i < m { result.append(DiffLine(kind: 0, line: b[i])); i += 1 }
        while j < n { result.append(DiffLine(kind: 1, line: a[j])); j += 1 }
        return result
    }

    private func startWrite() {
        guard validationIssues.isEmpty, !writeCoordinator.isWriting else { return }
        phase = .writing
        Task {
            do {
                let backupURL = try await writeCoordinator.write(target)
                try recordBackup(at: backupURL)
                profile.isActive = true
                profile.isEnabled = true
                profile.lastActivatedAt = Date()
                profile.updatedAt = Date()
                try context.save()
                sourceDraftCleanup()
                await MainActor.run { phase = .done }
            } catch {
                await MainActor.run {
                    writeError = localizedError(error)
                    phase = .done
                }
            }
        }
    }

    private func removeExactDuplicates() {
        var seen = Set<String>()
        for entry in profile.sortedEntries {
            let key = (entry.ip ?? "") + "|" + entry.hostList.joined(separator: ",")
            if seen.insert(key).inserted {
                continue
            }
            context.delete(entry)
        }
        do {
            try context.save()
            NotificationCenter.default.post(name: .profileEntriesChanged, object: profile.id)
        } catch {
            writeError = error.localizedDescription
        }
    }

    private func recordBackup(at url: URL) throws {
        let record = BackupRecord(context: context)
        record.id = UUID()
        record.timestamp = Date()
        record.filePath = url.path
        record.profileName = profile.localizedName(isEnglish: l10n.isEnglish)
        record.note = l10n.s(
            "应用“\(profile.localizedName(isEnglish: l10n.isEnglish))”前自动备份",
            "Auto backup before applying “\(profile.localizedName(isEnglish: l10n.isEnglish))”"
        )
        try context.save()
        try BackupMaintenance.prune(context: context)
    }

    private func sourceDraftCleanup() {
        NotificationCenter.default.post(name: .sourceDraftApplied, object: profile.id)
    }

    private func localizedError(_ error: Error) -> String {
        if let writeError = error as? HostsWriteError {
            switch writeError {
            case .invalidContent(_):
                return l10n.s("内容无效，无法写入。", "The hosts content is invalid.")
            case .authorizationFailed:
                return l10n.s("后台写入助手拒绝了授权。", "The background writer helper rejected authorization.")
            case .helperUnavailable:
                return l10n.s(
                    "后台写入助手不可用，请先在设置中启用并批准。",
                    "The background writer helper is unavailable. Enable and approve it in Settings first."
                )
            case .writeFailed:
                return l10n.s("写入 /etc/hosts 失败。", "Failed to write /etc/hosts.")
            case .readFailed:
                return l10n.s("无法读取 /etc/hosts。", "Unable to read /etc/hosts.")
            case .verificationFailed:
                return l10n.s("写入后校验失败。", "Verification failed after writing.")
            case .timedOut:
                return l10n.s("后台写入助手响应超时。", "The background writer helper timed out.")
            case .alreadyInProgress:
                return l10n.s("已有写入任务正在进行。", "Another write is already in progress.")
            }
        }
        return error.localizedDescription
    }
}

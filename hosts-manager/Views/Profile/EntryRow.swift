import SwiftUI
import CoreData

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
                    entry.isEnabled = newValue
                    do {
                        entry.profile?.updatedAt = Date()
                        try context.save()
                        if let profileID = entry.profile?.id {
                            NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
                        }
                    } catch {
                        context.rollback()
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

            RowIconButton(systemName: "pencil", help: l10n.s("编辑", "Edit")) {
                beginEdit()
            }
            .disabled(entry.isSystem)

            RowIconButton(systemName: "trash", help: l10n.s("删除", "Delete")) {
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
            profile.updatedAt = Date()
            try context.save()
            if let profileID = profile.id {
                NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
            }
            onEndEdit()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }

    private func delete() {
        guard !entry.isSystem else { return }
        let profileID = entry.profile?.id
        let profile = entry.profile
        context.delete(entry)
        do {
            profile?.updatedAt = Date()
            try context.save()
            if let profileID {
                NotificationCenter.default.post(name: .profileEntriesChanged, object: profileID)
            }
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}

#Preview("Entry Row") {
    EntryRow(
        entry: PreviewFixtures.entry,
        isEditing: false,
        isDimmed: false,
        onBeginEdit: {},
        onEndEdit: {}
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .padding()
    .frame(width: 820)
}

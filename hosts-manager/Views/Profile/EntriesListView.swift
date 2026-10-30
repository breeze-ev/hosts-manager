import SwiftUI
import CoreData

// MARK: - Entries list

struct EntriesListView: View {
    @ObservedObject var profile: Profile
    let query: String
    @Binding var isAdding: Bool
    let header: AnyView
    let isHeaderCollapsed: Bool
    let onScrollOffsetChange: (CGFloat) -> Void
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
            VStack(alignment: .leading, spacing: 14) {
                if !isHeaderCollapsed {
                    header
                }
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
            }
        } else {
            ScrollViewReader { proxy in
                List {
                    if isAdding {
                        newEntryEditor
                            .id("new-entry-editor")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                        #if DEBUG
                        if isRunningInXcodePreview {
                            // See NavigationSidebarView: work around the macOS
                            // Preview List/ForEach custom-row crash.
                            AnyView(EmptyView())
                        }
                        #endif
                        EntryRow(
                            entry: entry,
                            isEditing: editingID == entry.id,
                            isDimmed: (isAdding || editingID != nil) && editingID != entry.id,
                            onBeginEdit: { editingID = entry.id },
                            onEndEdit: { editingID = nil }
                        )
                        .id(entry.id)
                        .listRowSeparator(.hidden)
                        .zebraRowBackground(index)
                    }
                }
                .listStyle(.inset)
                .detailListSafeAreaHeader(isCollapsed: isHeaderCollapsed) {
                    header
                }
                .background(.clear)
                .detailHeaderScrollTracking(onScrollOffsetChange)
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
            profile.updatedAt = Date()
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
            context.rollback()
            draftError = error.localizedDescription
        }
    }
}

#Preview("Entries List") {
    @Previewable @State var isAdding = false

    EntriesListView(
        profile: PreviewFixtures.userProfile,
        query: "",
        isAdding: $isAdding,
        header: AnyView(
            DetailPageHeader(
                title: "预览配置",
                subtitle: "2 条启用 · 1 条停用",
                badge: AnyView(
                    Text("未应用")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .foregroundStyle(.secondary)
                ),
                trailing: AnyView(
                    Button("添加", systemImage: "plus") { isAdding = true }
                        .buttonStyle(.glass)
                )
            )
        ),
        isHeaderCollapsed: false,
        onScrollOffsetChange: { _ in }
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .frame(width: 860, height: 620)
}

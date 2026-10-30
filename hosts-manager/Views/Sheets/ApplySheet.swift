import SwiftUI
import CoreData

// MARK: - Apply flow

struct ApplySheet: View {
    @ObservedObject var profile: Profile
    let draftText: String?
    let managedHostnamesBaseline: Set<String>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: Localization
    @State private var phase: Phase = .preview
    @State private var writeError: String?
    @State private var baselineContent: String?
    @State private var removeDuplicatesOnApply = false
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared
    @FetchRequest(sortDescriptors: []) private var allProfiles: FetchedResults<Profile>

    enum Phase { case preview, writing, done }

    init(
        profile: Profile,
        draftText: String? = nil,
        managedHostnamesBaseline: Set<String> = []
    ) {
        self.profile = profile
        self.draftText = draftText
        self.managedHostnamesBaseline = managedHostnamesBaseline
    }

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
        .onAppear {
            captureBaselineIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hostsContentChanged)) { _ in
            if phase == .preview {
                refreshBaseline()
            }
        }
    }

    private var otherActiveProfiles: [Profile] {
        allProfiles.filter {
            $0.isAppliedForSystem && $0.id != profile.id && !$0.isDeleted
        }
    }

    private var target: String {
        mergedContent(entries: parsed, liveContent: HostsWriter.currentContent())
    }

    private var ownedHostnames: Set<String> {
        Set(
            allProfiles
                .filter { !$0.isSystem }
                .flatMap(\.sortedEntries)
                .flatMap(\.hostList)
                .map { $0.lowercased() }
        ).union(managedHostnamesBaseline)
    }

    private var managedHostnamesAfterWrite: Set<String> {
        let otherHostnames = allProfiles
            .filter {
                !$0.isSystem && $0.objectID != profile.objectID
            }
            .flatMap(\.sortedEntries)
            .flatMap(\.hostList)
        let targetHostnames = draftText.map {
            HostsParser.parse($0).flatMap(\.hostnames)
        } ?? profile.sortedEntries.flatMap(\.hostList)
        return Set(
            (otherHostnames + targetHostnames).map { $0.lowercased() }
        )
    }

    private func mergedContent(
        entries: [ParsedHostEntry],
        liveContent: String
    ) -> String {
        HostsContentMerger.merge(
            liveContent: liveContent,
            managedEntries: entries,
            ownedHostnames: ownedHostnames
        )
    }

    private var exactDuplicateObjectIDs: Set<NSManagedObjectID> {
        var seen = Set<String>()
        var duplicates = Set<NSManagedObjectID>()
        for entry in (otherActiveProfiles + [profile]).flatMap(\.sortedEntries) {
            let key = entryKey(entry)
            if !seen.insert(key).inserted {
                duplicates.insert(entry.objectID)
            }
        }
        return duplicates
    }

    private func entryKey(_ entry: HostEntry) -> String {
        (entry.ip ?? "") + "|" + entry.hostList.joined(separator: ",")
    }

    private var parsed: [ParsedHostEntry] {
        // 应用时把其它已启用配置的条目一并合并，预览和冲突检查都以并集为准。
        let profiles = otherActiveProfiles + [profile]
        let duplicateToDelete = removeDuplicatesOnApply
            ? exactDuplicateObjectIDs
            : Set<NSManagedObjectID>()
        return profiles.flatMap { p in
            p.sortedEntries.map {
                if duplicateToDelete.contains($0.objectID) {
                    return nil
                }
                return ParsedHostEntry(
                    ip: $0.ip ?? "",
                    hostnames: $0.hostList,
                    desc: localizedSeedDescription($0.desc, isEnglish: l10n.isEnglish),
                    isEnabled: $0.isEnabled,
                    isSystem: $0.isSystem
                )
            }
        }.compactMap { $0 }
    }

    private func parsedForWrite(
        targets: [Profile],
        draftEntries: [ParsedHostEntry]?,
        duplicateObjectIDs: Set<NSManagedObjectID>
    ) -> [ParsedHostEntry] {
        let profiles = targets.filter { $0.id != profile.id } + [profile]
        return profiles.flatMap { target in
            if target.id == profile.id, let draftEntries {
                return draftEntries
            }
            return target.sortedEntries.compactMap { entry -> ParsedHostEntry? in
                guard !duplicateObjectIDs.contains(entry.objectID) else {
                    return nil
                }
                return ParsedHostEntry(
                    ip: entry.ip ?? "",
                    hostnames: entry.hostList,
                    desc: localizedSeedDescription(
                        entry.desc,
                        isEnglish: l10n.isEnglish
                    ),
                    isEnabled: entry.isEnabled,
                    isSystem: entry.isSystem
                )
            }
        }
    }

    private var validationIssues: [HostIssue] {
        HostValidator.issues(entries: parsed.filter(\.isEnabled))
    }

    private var conflictIssues: [HostIssue] {
        validationIssues.filter { $0.kind == .conflict }
    }

    private var duplicateIssues: [HostIssue] {
        validationIssues.filter { $0.kind == .duplicate }
    }

    private var hasExactDuplicatesInTargets: Bool {
        guard !removeDuplicatesOnApply else { return false }
        var seen = Set<String>()
        return (otherActiveProfiles + [profile]).flatMap(\.sortedEntries).contains { entry in
            let key = (entry.ip ?? "") + "|" + entry.hostList.joined(separator: ",")
            return !seen.insert(key).inserted
        }
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
                        conflictIssues.isEmpty
                            ? l10n.s("存在完全重复条目", "Exact duplicates found")
                            : l10n.s("存在主机名冲突", "Hostname conflict found"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(conflictIssues.isEmpty ? .green : .orange)
                    Text(validationIssues.map(\.hostname).joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !conflictIssues.isEmpty {
                        Text(l10n.s(
                            "这些主机名分别指向了不同 IP；修复前不会写入系统。",
                            "These hostnames point to different IPs; nothing will be written until they are fixed."
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    } else if !duplicateIssues.isEmpty {
                        Text(l10n.s(
                            "完全重复条目会在写入时自动去重，不会阻止应用。",
                            "Exact duplicates are removed automatically when applying and do not block the write."
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    if hasExactDuplicatesInTargets {
                        Button(l10n.s("清理应用范围内的完全重复条目", "Remove Exact Duplicates in Applied Profiles")) {
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
                    .disabled(!conflictIssues.isEmpty)
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
        let before = baselineContent ?? normalizedCurrentHosts()
        let after = target
        let diff = lineDiff(before, after)
        return VStack(alignment: .leading, spacing: 4) {
            Text(diffTitle)
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

    private var diffTitle: String {
        guard phase == .done else { return l10n.s("预览", "Preview") }
        return writeError == nil
            ? l10n.s("已应用更改", "Applied changes")
            : l10n.s("待应用更改", "Pending changes")
    }

    private func normalizedCurrentHosts() -> String {
        HostsParser.serialize(HostsParser.parse(HostsWriter.currentContent()))
    }

    private func captureBaselineIfNeeded() {
        if baselineContent == nil {
            refreshBaseline()
        }
    }

    private func refreshBaseline() {
        let current = normalizedCurrentHosts()
        baselineContent = current
        guard let draftText else { return }
        let draftEntries = HostsParser.parse(draftText)
        if HostsParser.entriesEquivalent(draftEntries, parsedWithoutDraft()) {
            NotificationCenter.default.post(
                name: .sourceDraftApplied,
                object: profile.id
            )
        }
    }

    private func parsedWithoutDraft() -> [ParsedHostEntry] {
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
        guard conflictIssues.isEmpty else { return }
        // Capture the exact duplicate set that the previewed target was based
        // on. It must not be recalculated after a background model change.
        let duplicateObjectIDs = removeDuplicatesOnApply
            ? exactDuplicateObjectIDs
            : []
        refreshBaseline()
        phase = .writing
        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let draftEntries = draftText.map { HostsParser.parse($0) }
                _ = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        // Re-read at the queue head so a profile applied or
                        // disabled while this sheet was open cannot be omitted.
                        guard !self.profile.isDeleted, !self.profile.isSystem else {
                            throw HostsWriteAbortedError()
                        }
                        let targets = self.otherActiveProfiles + [self.profile]
                        let entries = self.parsedForWrite(
                            targets: targets,
                            draftEntries: draftEntries,
                            duplicateObjectIDs: duplicateObjectIDs
                        )
                        if HostValidator.issues(entries: entries.filter(\.isEnabled))
                            .contains(where: { $0.kind == .conflict }) {
                            throw HostsWriteConflictError(profileID: self.profile.id ?? UUID())
                        }
                        appliedProfileIDs = targets.compactMap(\.id)
                        return HostsWriteRequest(
                            content: self.mergedContent(
                                entries: entries,
                                liveContent: liveContent
                            ),
                            appliedProfileIDs: targets.compactMap(\.id),
                            managedHostnames: Array(
                                self.managedHostnamesAfterWrite
                            ).sorted()
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: context,
                            profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                            note: l10n.s(
                                "应用“\(profile.localizedName(isEnglish: l10n.isEnglish))”前自动备份",
                                "Auto backup before applying “\(profile.localizedName(isEnglish: l10n.isEnglish))”"
                            ),
                            appliedProfileIDs: appliedProfileIDs
                        ) {
                            if let draftEntries,
                               !HostsParser.entriesEquivalent(
                                draftEntries,
                                profile.sortedEntries.map {
                                    ParsedHostEntry(
                                        ip: $0.ip ?? "",
                                        hostnames: $0.hostList,
                                        desc: $0.desc ?? "",
                                        isEnabled: $0.isEnabled,
                                        isSystem: $0.isSystem
                                    )
                                }
                               ) {
                                for entry in profile.sortedEntries {
                                    context.delete(entry)
                                }
                                for (index, item) in draftEntries.enumerated() {
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
                                profile.updatedAt = Date()
                            }
                            if removeDuplicatesOnApply {
                                removeDuplicateEntries(matching: duplicateObjectIDs)
                            }
                            profile.updatedAt = Date()
                            try setAppliedProfileSelection(
                                appliedProfileIDs,
                                lastActivatedProfileID: profile.id,
                                context: context
                            )
                        }
                    }
                )
                sourceDraftCleanup()
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .hostsStateReconciled,
                        object: nil
                    )
                    phase = .done
                }
            } catch {
                await MainActor.run {
                    writeError = localizedError(error)
                    phase = .done
                }
            }
        }
    }

    private func removeExactDuplicates() {
        removeDuplicatesOnApply = true
    }

    private func removeDuplicateEntries(matching objectIDs: Set<NSManagedObjectID>) {
        for entry in allProfiles.flatMap(\.sortedEntries)
        where objectIDs.contains(entry.objectID) {
            if let owner = entry.profile {
                owner.updatedAt = Date()
            }
            context.delete(entry)
        }
    }

    private func sourceDraftCleanup() {
        NotificationCenter.default.post(
            name: .profileEntriesChanged,
            object: profile.id,
            userInfo: [HostsStateNotificationKey.skipRealtimeApply: true]
        )
        NotificationCenter.default.post(name: .sourceDraftApplied, object: profile.id)
    }

    private func localizedError(_ error: Error) -> String {
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
            }
        }
        return error.localizedDescription
    }
}

#Preview("Apply Sheet") {
    ApplySheet(
        profile: PreviewFixtures.userProfile,
        managedHostnamesBaseline: Set(
            PreviewFixtures.userProfile.sortedEntries.flatMap(\.hostList)
        )
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
}

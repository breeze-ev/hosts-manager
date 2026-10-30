import CoreData
import SwiftUI

struct ApplySheet: View {
    @ObservedObject var profile: Profile
    let draftText: String?
    let managedHostnamesBaseline: Set<String>
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var l10n: Localization
    @State private var phase: Phase = .preview
    @State private var writeError: String?
    @State private var baselineContent = ""
    @State private var liveContent = ""
    @State private var resultBaselineContent: String?
    @State private var resultTargetContent: String?
    @State private var removeDuplicatesOnApply = false
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared
    @FetchRequest(sortDescriptors: []) private var allProfiles: FetchedResults<Profile>

    enum Phase {
        case preview
        case writing
        case done
    }

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
            case .preview:
                ApplyPreviewView(
                    profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                    plan: plan,
                    baselineContent: baselineContent,
                    onRemoveDuplicates: { removeDuplicatesOnApply = true },
                    onCancel: { dismiss() },
                    onConfirm: startWrite
                )
            case .writing:
                ApplyProgressView()
            case .done:
                ApplyResultView(
                    profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                    errorMessage: writeError,
                    baselineContent: resultBaselineContent ?? baselineContent,
                    targetContent: resultTargetContent ?? plan.targetContent,
                    onDone: { dismiss() }
                )
            }
        }
        .frame(width: 620, height: 500)
        .padding(22)
        .buttonBorderShape(.capsule)
        .onAppear(perform: captureBaselineIfNeeded)
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

    private var plan: ApplyPlan {
        ApplyPlanBuilder.makePlan(
            profile: profile,
            allProfiles: Array(allProfiles),
            draftText: draftText,
            managedHostnamesBaseline: managedHostnamesBaseline,
            liveContent: liveContent,
            removeDuplicates: removeDuplicatesOnApply,
            isEnglish: l10n.isEnglish
        )
    }

    private func captureBaselineIfNeeded() {
        if baselineContent.isEmpty && liveContent.isEmpty {
            refreshBaseline()
        }
    }

    private func refreshBaseline() {
        liveContent = HostsWriter.currentContent()
        baselineContent = HostsParser.serialize(HostsParser.parse(liveContent))
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

    private func startWrite() {
        let approvedPlan = plan
        guard approvedPlan.canApply else { return }

        resultBaselineContent = baselineContent
        resultTargetContent = approvedPlan.targetContent
        let approvedDraftText = draftText
        let duplicateObjectIDs = removeDuplicatesOnApply
            ? approvedPlan.exactDuplicateObjectIDs
            : []
        refreshBaseline()
        phase = .writing

        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let draftEntries = approvedDraftText.map(HostsParser.parse)
                _ = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        guard !self.profile.isDeleted, !self.profile.isSystem else {
                            throw HostsWriteAbortedError()
                        }
                        let targets = self.otherActiveProfiles + [self.profile]
                        let currentPlan = ApplyPlanBuilder.makePlan(
                            targets: targets,
                            profile: self.profile,
                            allProfiles: Array(self.allProfiles),
                            draftText: approvedDraftText,
                            managedHostnamesBaseline: self.managedHostnamesBaseline,
                            liveContent: liveContent,
                            removeDuplicates: self.removeDuplicatesOnApply,
                            forcedDuplicateObjectIDs: duplicateObjectIDs,
                            isEnglish: self.l10n.isEnglish
                        )
                        guard currentPlan.canApply else {
                            throw HostsWriteConflictError(
                                profileID: self.profile.id ?? UUID()
                            )
                        }
                        appliedProfileIDs = currentPlan.appliedProfileIDs
                        return HostsWriteRequest(
                            content: currentPlan.targetContent,
                            appliedProfileIDs: currentPlan.appliedProfileIDs,
                            managedHostnames: currentPlan.managedHostnames.sorted()
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: context,
                            profileName: profile.localizedName(isEnglish: l10n.isEnglish),
                            note: applyBackupNote,
                            appliedProfileIDs: appliedProfileIDs
                        ) {
                            try applyStateChanges(
                                draftEntries: draftEntries,
                                duplicateObjectIDs: duplicateObjectIDs,
                                appliedProfileIDs: appliedProfileIDs
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

    private var applyBackupNote: String {
        l10n.s(
            "应用“\(profile.localizedName(isEnglish: l10n.isEnglish))”前自动备份",
            "Auto backup before applying “\(profile.localizedName(isEnglish: l10n.isEnglish))”"
        )
    }

    private func applyStateChanges(
        draftEntries: [ParsedHostEntry]?,
        duplicateObjectIDs: Set<NSManagedObjectID>,
        appliedProfileIDs: [UUID]
    ) throws {
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
            ProfileRepository(context: context).replaceEntries(
                of: profile,
                with: draftEntries
            )
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
        if error is HostsStateRecoveryRequiredError {
            return l10n.s(
                "配置状态尚未恢复，写入已暂停。请先完成恢复操作。",
                "Profile state recovery is pending and writes are paused. Complete recovery first."
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
            case .invalidContent:
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

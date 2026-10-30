import CoreData
import Foundation

extension HostsWorkspaceModel {
    func reconcileSystemHosts() {
        showStateRecoveryWarning = stateCommitFailed
    }

    func reconcileOnLaunch() {
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
            managedHostnamesBaseline = configuredHostnames(
                in: currentProfilesForRecovery()
            )
        }
        refreshReconciliationBaselineFromLiveFile()
    }

    func handleStateNeedsReconciliation(_ notification: Notification) {
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

    func noteSynchronizedHostsContent(
        _ content: String,
        appliedProfileIDs: [UUID]? = nil,
        managedHostnames: [String]? = nil
    ) {
        lastKnownHostsFingerprint = HostsReconciliation.canonical(content)
        managedHostnamesBaseline = managedHostnames.map(Set.init)
            ?? configuredHostnames(in: currentProfilesForRecovery())
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

    func resetReconciliationBaseline(
        to content: String,
        appliedProfileIDs: [UUID]? = nil
    ) {
        noteSynchronizedHostsContent(
            content,
            appliedProfileIDs: appliedProfileIDs
        )
    }

    /// Resolve a failed state commit by keeping the system file and clearing
    /// every user profile's applied switch in Core Data.
    func keepCurrentHostsContent() {
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

    /// Resolve a failed state commit by applying the selection that was pending
    /// when the file write succeeded.
    func reapplyActiveProfiles() {
        let profiles = currentProfilesForRecovery()
        let targetIDs = stateCommitFailed && hasPendingAppliedProfileSelection
            ? pendingAppliedProfileIDs
            : activeProfiles(in: profiles).compactMap(\.id)
        let sourceProfiles = stateCommitFailed && hasPendingAppliedProfileSelection
            ? pendingApplyTargetProfiles(in: profiles)
            : activeProfiles(in: profiles)
        let first = sourceProfiles.first {
            $0.id.map(targetIDs.contains) == true
        }
        let primaryProfile = first ?? selectedProfile(in: profiles)
        let targets = profiles.filter {
            $0.id.map(targetIDs.contains) == true && !$0.isDeleted
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
                let result = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        let currentProfiles = self.currentProfilesForRecovery()
                        let targets = currentProfiles.filter {
                            $0.id.map(targetIDs.contains) == true
                        }
                        guard !self.hasWriteConflict(in: targets) else {
                            guard let profileID = targets.first?.id else {
                                throw HostsWriteAbortedError()
                            }
                            throw HostsWriteConflictError(profileID: profileID)
                        }
                        appliedProfileIDs = targets.compactMap(\.id)
                        return HostsWriteRequest(
                            content: self.mergedContent(
                                for: targets,
                                liveContent: liveContent,
                                profiles: currentProfiles
                            ),
                            appliedProfileIDs: appliedProfileIDs,
                            managedHostnames: Array(
                                self.configuredHostnames(in: currentProfiles)
                            ).sorted()
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: self.context,
                            profileName: primaryProfile?.localizedName(
                                isEnglish: self.l10n.isEnglish
                            ),
                            note: self.l10n.s(
                                "重新同步配置前自动备份",
                                "Auto backup before resynchronizing profiles"
                            ),
                            appliedProfileIDs: appliedProfileIDs,
                            checkStateIntegrity: {
                                self.recoveryStateIsConsistent(
                                    appliedProfileIDs: appliedProfileIDs,
                                    content: result.content
                                )
                            }
                        ) {
                            try setAppliedProfileSelection(
                                appliedProfileIDs,
                                context: self.context
                            )
                        }
                    }
                )
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
                let result = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        let currentProfiles = self.currentProfilesForRecovery()
                        appliedProfileIDs = []
                        return HostsWriteRequest(
                            content: self.mergedContent(
                                for: [],
                                liveContent: liveContent,
                                profiles: currentProfiles
                            ),
                            appliedProfileIDs: [],
                            managedHostnames: Array(
                                self.configuredHostnames(in: currentProfiles)
                            ).sorted()
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: self.context,
                            profileName: nil,
                            note: self.l10n.s(
                                "重新同步配置前自动备份",
                                "Auto backup before resynchronizing profiles"
                            ),
                            appliedProfileIDs: []
                        ) {
                            try setAppliedProfileSelection([], context: self.context)
                        }
                    }
                )
                resetReconciliationBaseline(
                    to: result.content,
                    appliedProfileIDs: appliedProfileIDs
                )
            } catch {
                handleWriteFailure(error, profileID: nil)
            }
        }
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

    func persistReconciliationBaseline() {
        guard let fingerprint = lastKnownHostsFingerprint else {
            HostsReconciliationBaselineStore.clear()
            return
        }
        let profiles = currentProfilesForRecovery()
        HostsReconciliationBaselineStore.save(
            HostsReconciliationBaseline(
                fingerprint: fingerprint,
                appliedProfileIDs: activeProfiles(in: profiles).compactMap(\.id),
                pendingAppliedProfileIDs: hasPendingAppliedProfileSelection
                    ? pendingAppliedProfileIDs
                    : nil,
                managedHostnames: managedHostnamesBaseline.sorted(),
                stateCommitFailed: stateCommitFailed
            )
        )
    }

    private func recoveryStateIsConsistent(
        appliedProfileIDs: [UUID],
        content: String
    ) -> Bool {
        let profiles = currentProfilesForRecovery()
        let targets = profiles.filter {
            $0.id.map(appliedProfileIDs.contains) == true
        }
        let finalContent = mergedContent(
            for: targets,
            liveContent: content,
            profiles: profiles
        )
        return HostsReconciliation.canonical(finalContent)
            == HostsReconciliation.canonical(content)
    }

    private func currentProfilesForRecovery() -> [Profile] {
        (try? fetchProfiles()) ?? []
    }
}

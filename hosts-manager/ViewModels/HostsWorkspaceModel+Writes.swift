import CoreData
import Foundation

extension HostsWorkspaceModel {
    func requestApply(in profiles: [Profile]) {
        // Apply belongs to the source editor; list mode has no apply action.
        guard mode == .source,
              selection == .profiles,
              let profile = selectedProfile(in: profiles) else {
            return
        }
        guard !stateCommitFailed else {
            showStateRecoveryWarning = true
            return
        }
        applyProfile(profile, in: profiles)
    }

    @discardableResult
    func applyProfile(_ profile: Profile, in profiles: [Profile]) -> Bool {
        // Applying an inactive profile also enables it after the confirmation.
        guard !profile.isSystem else { return false }
        guard !stateCommitFailed else {
            showStateRecoveryWarning = true
            return false
        }
        guard !writeCoordinator.requiresStateRecovery else {
            stateCommitFailed = true
            showStateRecoveryWarning = true
            return false
        }
        guard validateSourceDraftIfNeeded(for: profile) else { return false }
        if let profileID = profile.id,
           let draft = sourceDrafts[profileID],
           sourceDraftMatchesStored(draft, profile: profile) {
            clearDraft(for: profileID)
        }
        selection = .profiles
        selectedProfileID = profile.id
        applyDraftText = profile.id.flatMap { sourceDrafts[$0] }
        showApply = true
        return true
    }

    func enableProfile(_ profile: Profile, in profiles: [Profile]) {
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
        guard saveSourceIfNeeded(for: profile, in: profiles),
              let profileID = profile.id else {
            return
        }
        let profileName = profile.localizedName(isEnglish: l10n.isEnglish)

        let targets = activeProfiles(in: profiles).filter {
            $0.id != profileID
        } + [profile]
        guard !hasWriteConflict(in: targets) else {
            selection = .profiles
            selectedProfileID = profileID
            applyDraftText = nil
            showApply = true
            return
        }

        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        // Re-read at the queue head because an earlier write may
                        // have changed selections while this request was queued.
                        let currentProfiles = self.currentProfilesForWrite()
                        guard let target = currentProfiles.first(where: {
                            $0.id == profileID && !$0.isDeleted
                        }) else {
                            throw HostsWriteAbortedError()
                        }
                        let targets = self.activeProfiles(in: currentProfiles).filter {
                            $0.id != profileID
                        } + [target]
                        guard !self.hasWriteConflict(in: targets) else {
                            throw HostsWriteConflictError(profileID: profileID)
                        }
                        appliedProfileIDs = targets.compactMap(\.id)
                        return self.makeWriteRequest(
                            targets: targets,
                            allProfiles: currentProfiles,
                            liveContent: liveContent
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: self.context,
                            profileName: profileName,
                            note: self.l10n.s(
                                "启用配置前自动备份",
                                "Auto backup before enabling profile"
                            ),
                            appliedProfileIDs: appliedProfileIDs,
                            checkStateIntegrity: {
                                self.stateIsConsistent(
                                    appliedProfileIDs: appliedProfileIDs,
                                    content: result.content
                                )
                            }
                        ) {
                            try setAppliedProfileSelection(
                                appliedProfileIDs,
                                lastActivatedProfileID: profileID,
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
                handleWriteFailure(error, profileID: profileID)
            }
        }
    }

    func disableActiveProfile(_ profile: Profile) {
        guard let profileID = profile.id else { return }
        guard !stateCommitFailed else {
            showStateRecoveryWarning = true
            return
        }
        let profileName = profile.localizedName(isEnglish: l10n.isEnglish)

        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        let currentProfiles = self.currentProfilesForWrite()
                        let remaining = self.activeProfiles(in: currentProfiles).filter {
                            $0.id != profileID
                        }
                        // A preceding queued enable may already have written this
                        // profile, so disabling it still requires a write.
                        appliedProfileIDs = remaining.compactMap(\.id)
                        return self.makeWriteRequest(
                            targets: remaining,
                            allProfiles: currentProfiles,
                            liveContent: liveContent
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: self.context,
                            profileName: profileName,
                            note: self.l10n.s(
                                "停用当前配置前自动备份",
                                "Auto backup before disabling the active profile"
                            ),
                            appliedProfileIDs: appliedProfileIDs,
                            checkStateIntegrity: {
                                self.stateIsConsistent(
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
                handleWriteFailure(error, profileID: profileID)
            }
        }
    }

    /// Debounces list edits per profile, then writes the union of all active
    /// profiles. It deliberately waits for an already-running write rather than
    /// cancelling it, so the last durable content always reflects the newer edit.
    func scheduleRealtimeApply(for profile: Profile) {
        guard let profileID = profile.id else { return }
        let revision = realtimeApplyRevisions[profileID, default: 0] + 1
        realtimeApplyRevisions[profileID] = revision
        let existing = realtimeApplyTasks[profileID]
        realtimeApplyTasks[profileID] = Task { @MainActor in
            defer {
                if self.realtimeApplyRevisions[profileID] == revision {
                    self.realtimeApplyTasks.removeValue(forKey: profileID)
                    self.realtimeApplyRevisions.removeValue(forKey: profileID)
                }
            }
            _ = await existing?.value
            guard !Task.isCancelled,
                  self.realtimeApplyRevisions[profileID] == revision else {
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.realtimeApplyRevisions[profileID] == revision,
                  let current = self.currentProfilesForWrite().first(where: {
                      $0.id == profileID
                  }),
                  !current.isDeleted else {
                return
            }
            guard !self.stateCommitFailed else {
                self.showStateRecoveryWarning = true
                return
            }
            self.realtimeApplyTasks.removeValue(forKey: profileID)
            self.applyActiveProfilesToSystem(for: current)
        }
    }

    private func applyActiveProfilesToSystem(for profile: Profile) {
        // A switch being off means the profile is not system content, even if
        // list edits are still being saved to Core Data.
        guard !profile.isSystem, profile.isAppliedForSystem else { return }
        guard let profileID = profile.id else { return }
        let profileName = profile.localizedName(isEnglish: l10n.isEnglish)

        Task {
            do {
                var appliedProfileIDs: [UUID] = []
                let result = try await writeCoordinator.perform(
                    makeContent: { liveContent in
                        // A restore or queued operation may have disabled this
                        // profile after the debounce fired.
                        let currentProfiles = self.currentProfilesForWrite()
                        guard let current = currentProfiles.first(where: {
                            $0.id == profileID
                        }), current.isAppliedForSystem else {
                            throw HostsWriteAbortedError()
                        }
                        let targets = self.activeProfiles(in: currentProfiles)
                        guard !targets.isEmpty else {
                            throw HostsWriteAbortedError()
                        }
                        guard !self.hasWriteConflict(in: targets) else {
                            throw HostsWriteConflictError(profileID: profileID)
                        }
                        appliedProfileIDs = targets.compactMap(\.id)
                        return self.makeWriteRequest(
                            targets: targets,
                            allProfiles: currentProfiles,
                            liveContent: liveContent
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: self.context,
                            profileName: profileName,
                            note: self.l10n.s(
                                "列表编辑后实时应用",
                                "Real-time apply after list edit"
                            ),
                            appliedProfileIDs: appliedProfileIDs,
                            checkStateIntegrity: {
                                self.stateIsConsistent(
                                    appliedProfileIDs: appliedProfileIDs,
                                    content: result.content
                                )
                            }
                        ) {
                            try setAppliedProfileSelection(
                                appliedProfileIDs,
                                lastActivatedProfileID: profileID,
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
                handleWriteFailure(error, profileID: profileID)
            }
        }
    }

    private func makeWriteRequest(
        targets: [Profile],
        allProfiles: [Profile],
        liveContent: String
    ) -> HostsWriteRequest {
        HostsWriteRequest(
            content: mergedContent(
                for: targets,
                liveContent: liveContent,
                profiles: allProfiles
            ),
            appliedProfileIDs: targets.compactMap(\.id),
            managedHostnames: Array(configuredHostnames(in: allProfiles)).sorted()
        )
    }

    private func stateIsConsistent(
        appliedProfileIDs: [UUID],
        content: String
    ) -> Bool {
        let allProfiles = currentProfilesForWrite()
        let targets = allProfiles.filter {
            $0.id.map(appliedProfileIDs.contains) == true
        }
        let finalContent = mergedContent(
            for: targets,
            liveContent: content,
            profiles: allProfiles
        )
        return HostsReconciliation.canonical(finalContent)
            == HostsReconciliation.canonical(content)
    }

    private func currentProfilesForWrite() -> [Profile] {
        (try? fetchProfiles()) ?? []
    }
}

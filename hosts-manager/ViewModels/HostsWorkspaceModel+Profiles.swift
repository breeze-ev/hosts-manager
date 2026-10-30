import CoreData
import Foundation

extension HostsWorkspaceModel {
    func createProfile() {
        let repository = ProfileRepository(context: context)
        let profile = repository.create(
            name: l10n.s("新配置", "New Profile")
        )
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

    func deleteProfile(_ profile: Profile, in profiles: [Profile]) {
        guard !profile.isAppliedForSystem else {
            operationError = l10n.s(
                "请先停用当前配置，再删除它。",
                "Disable the active profile before deleting it."
            )
            return
        }

        // Capture identity before deleting because the managed object may no
        // longer be safe to inspect after the save.
        let profileID = profile.id
        let wasSelected = selectedProfileID == profileID
        ProfileRepository(context: context).delete(profile)
        do {
            try context.save()
        } catch {
            context.rollback()
            operationError = localizedError(error)
            return
        }

        if let profileID {
            cancelRealtimeApply(for: profileID)
            clearDraft(for: profileID)
        }
        if wasSelected {
            let remaining = (try? fetchProfiles())
                ?? profiles.filter { $0.id != profileID }
            selectedProfileID = remaining.first?.id
        }
        NotificationCenter.default.post(name: .hostsStateReconciled, object: nil)
    }

    @discardableResult
    func saveSourceIfNeeded(
        for target: Profile? = nil,
        in profiles: [Profile]
    ) -> Bool {
        guard mode == .source,
              let profile = target ?? selectedProfile(in: profiles),
              !profile.isSystem else {
            return true
        }
        // A generated source view is not a draft. Replacing all entries in that
        // case would change object IDs and localize descriptions unexpectedly.
        guard let profileID = profile.id,
              let draft = sourceDrafts[profileID] else {
            return true
        }
        guard HostsValueValidator.validate(content: draft) == nil else {
            operationError = l10n.s(
                "内容包含无效的 IP、主机名或控制字符。",
                "The content contains an invalid IP address, hostname, or control character."
            )
            return false
        }

        let newEntries = HostsParser.parse(draft)
        if HostsParser.entriesEquivalent(newEntries, parsedEntries(for: profile)) {
            clearDraft(for: profileID)
            return true
        }

        ProfileRepository(context: context).replaceEntries(
            of: profile,
            with: newEntries
        )
        do {
            try context.save()
        } catch {
            // The repository has already queued entry deletions in the context.
            // Roll back so an unrelated later save cannot commit a partial edit.
            context.rollback()
            operationError = localizedError(error)
            return false
        }
        sourceDrafts[profileID] = draft
        sourceDraftValidations[profileID] = draft
        conflictingDrafts.remove(profileID)
        return true
    }

    /// Called only after the user explicitly chooses to discard their draft.
    func discardSourceDraft(for profile: Profile) {
        guard let profileID = profile.id else { return }
        clearDraft(for: profileID)
    }

    func handleSourceDraftApplied(_ profileID: UUID) {
        cancelRealtimeApply(for: profileID)
        clearDraft(for: profileID)
    }

    func handleProfileEntriesChanged(
        for profileID: UUID,
        skipRealtimeApply: Bool,
        in profiles: [Profile]
    ) {
        // A list edit can race with an unapplied source draft. Keep the draft and
        // make the conflict explicit instead of silently discarding user input.
        if let draft = sourceDrafts[profileID],
           let profile = profiles.first(where: { $0.id == profileID }),
           sourceDraftMatchesStored(draft, profile: profile) {
            clearDraft(for: profileID)
        } else if sourceDrafts[profileID] != nil {
            conflictingDrafts.insert(profileID)
            sourceDraftValidations.removeValue(forKey: profileID)
        }

        guard !skipRealtimeApply,
              let profile = profiles.first(where: { $0.id == profileID }),
              profile.isAppliedForSystem else {
            return
        }
        if stateCommitFailed {
            showStateRecoveryWarning = true
        } else {
            scheduleRealtimeApply(for: profile)
        }
    }

    func importProfile(from url: URL) {
        do {
            let imported = try HostsImport.load(from: url)
            let profile = ProfileRepository(context: context).create(
                name: l10n.s(
                    "导入 \(imported.suggestedProfileName)",
                    "Imported \(imported.suggestedProfileName)"
                ),
                entries: imported.entries
            )
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

    func duplicateSelectedProfile(in profiles: [Profile]) {
        guard let source = selectedProfile(in: profiles), !source.isSystem else {
            return
        }
        let sourceName = source.localizedName(isEnglish: l10n.isEnglish)
        let entries = source.sortedEntries.map {
            ParsedHostEntry(
                ip: $0.ip ?? "",
                hostnames: $0.hostList,
                desc: $0.desc ?? "",
                isEnabled: $0.isEnabled,
                isSystem: $0.isSystem
            )
        }
        let profile = ProfileRepository(context: context).create(
            name: l10n.s("\(sourceName) 副本", "\(sourceName) Copy"),
            entries: entries
        )
        do {
            try context.save()
            selectedProfileID = profile.id
        } catch {
            context.rollback()
            operationError = localizedError(error)
        }
    }

    func exportSelectedProfile(to url: URL, in profiles: [Profile]) {
        guard let profile = selectedProfile(in: profiles), !profile.isSystem else {
            return
        }
        do {
            try sourceText(for: profile).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        } catch {
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
            return l10n.s(
                "文件中没有可导入的用户条目。",
                "The file does not contain any user entries to import."
            )
        }
    }

    private func cancelRealtimeApply(for profileID: UUID) {
        realtimeApplyTasks[profileID]?.cancel()
        realtimeApplyTasks.removeValue(forKey: profileID)
        realtimeApplyRevisions.removeValue(forKey: profileID)
    }
}

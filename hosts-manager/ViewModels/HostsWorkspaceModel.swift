import CoreData
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class HostsWorkspaceModel {
    @ObservationIgnored let context: NSManagedObjectContext
    @ObservationIgnored let l10n: Localization
    @ObservationIgnored let writeCoordinator: HostsWriteCoordinator

    var selection: SidebarItem = .profiles
    var selectedProfileID: UUID?
    var mode: EntryMode = .list
    var didApplyDefaultMode = false
    var showApply = false
    var applyDraftText: String?
    var sourceDrafts: [UUID: String] = [:]
    var conflictingDrafts: Set<UUID> = []
    var sourceDraftValidations: [UUID: String] = [:]
    var realtimeApplyRevisions: [UUID: Int] = [:]
    var operationError: String?
    var showStateRecoveryWarning = false
    var stateCommitFailed = false
    var pendingAppliedProfileIDs: [UUID] = []
    var hasPendingAppliedProfileSelection = false
    var lastKnownHostsFingerprint: String?
    var managedHostnamesBaseline: Set<String> = []
    var pendingScrollProfileID: UUID?
    @ObservationIgnored var realtimeApplyTasks: [UUID: Task<Void, Never>] = [:]

    init(
        context: NSManagedObjectContext,
        localization: Localization,
        writeCoordinator: HostsWriteCoordinator = .shared
    ) {
        self.context = context
        self.l10n = localization
        self.writeCoordinator = writeCoordinator
    }

    func selectedProfile(in profiles: [Profile]) -> Profile? {
        if let id = selectedProfileID,
           let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        if let active = profiles.first(where: \.isAppliedForSystem) {
            return active
        }
        return profiles.first(where: { !$0.isSystem }) ?? profiles.first
    }

    func applyDefaultModeIfNeeded() {
        guard !didApplyDefaultMode else { return }
        if let stored = try? context.fetch(AppSettings.fetchRequest()).first?.defaultView {
            mode = EntryMode(rawValue: stored) ?? .list
        }
        didApplyDefaultMode = true
    }

    func selectProfile(_ profile: Profile) {
        selection = .profiles
        selectedProfileID = profile.id
    }

    func initialProfileID(in profiles: [Profile]) -> UUID? {
        let candidates = profiles.filter { !$0.isSystem }
        if let last = candidates.max(by: {
            ($0.lastActivatedAt ?? $0.updatedAt ?? $0.createdAt ?? .distantPast)
                < ($1.lastActivatedAt ?? $1.updatedAt ?? $1.createdAt ?? .distantPast)
        }) {
            return last.id
        }
        return selectedProfile(in: profiles)?.id
    }

    func parsedEntries(for profile: Profile) -> [ParsedHostEntry] {
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

    func activeProfiles(in profiles: [Profile]) -> [Profile] {
        profiles.filter(\.isAppliedForSystem)
    }

    func pendingApplyTargetProfiles(in profiles: [Profile]) -> [Profile] {
        guard hasPendingAppliedProfileSelection else {
            return activeProfiles(in: profiles)
        }
        let ids = Set(pendingAppliedProfileIDs)
        return profiles.filter { $0.id.map(ids.contains) == true }
    }

    func configuredHostnames(in profiles: [Profile]) -> Set<String> {
        Set(
            profiles
                .filter { !$0.isSystem }
                .flatMap(\.sortedEntries)
                .flatMap(\.hostList)
                .map { $0.lowercased() }
        )
    }

    func ownedHostnames(in profiles: [Profile]) -> Set<String> {
        configuredHostnames(in: profiles).union(managedHostnamesBaseline)
    }

    func mergedContent(
        for targets: [Profile],
        liveContent: String,
        profiles: [Profile]
    ) -> String {
        HostsContentMerger.merge(
            liveContent: liveContent,
            managedEntries: targets.flatMap(parsedEntries(for:)),
            ownedHostnames: ownedHostnames(in: profiles)
        )
    }

    func validationIssues(for profiles: [Profile]) -> [HostIssue] {
        HostValidator.issues(
            entries: profiles
                .flatMap(parsedEntries(for:))
                .filter(\.isEnabled)
        )
    }

    func hasWriteConflict(in profiles: [Profile]) -> Bool {
        validationIssues(for: profiles).contains { $0.kind == .conflict }
    }

    func fetchProfiles() throws -> [Profile] {
        let request = Profile.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Profile.isSystem, ascending: false),
            NSSortDescriptor(keyPath: \Profile.createdAt, ascending: true)
        ]
        return try context.fetch(request)
    }

    func sourceText(for profile: Profile) -> String {
        if let profileID = profile.id, let draft = sourceDrafts[profileID] {
            return draft
        }
        return localizedSourceText(for: profile, isEnglish: l10n.isEnglish)
    }

    func sourceDraftMatchesStored(_ draft: String, profile: Profile) -> Bool {
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

    func validateSourceDraftIfNeeded(for profile: Profile) -> Bool {
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

    func sourceBinding(for profile: Profile) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.sourceText(for: profile) ?? ""
            },
            set: { [weak self] value in
                self?.updateSourceDraft(value, for: profile)
            }
        )
    }

    func updateSourceDraft(_ value: String, for profile: Profile) {
        guard let profileID = profile.id else { return }
        let stored = parsedEntries(for: profile)
        if HostsParser.entriesEquivalent(HostsParser.parse(value), stored) {
            clearDraft(for: profileID)
            return
        }
        if sourceDraftValidations[profileID] == value {
            clearDraft(for: profileID)
        } else {
            sourceDrafts[profileID] = value
        }
    }

    func clearDraft(for profileID: UUID) {
        sourceDrafts.removeValue(forKey: profileID)
        conflictingDrafts.remove(profileID)
        sourceDraftValidations.removeValue(forKey: profileID)
    }
}

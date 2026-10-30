import CoreData
import Foundation

@MainActor
func clearAppliedStateForUserProfiles(in context: NSManagedObjectContext) throws {
    let profiles = try context.fetch(Profile.fetchRequest())
    let now = Date()
    for profile in profiles where !profile.isSystem {
        profile.setApplied(false)
        profile.updatedAt = now
    }
}

/// Applies an exact selection. Profiles absent from `profileIDs` are marked
/// unapplied so the database can represent an empty applied set.
@MainActor
func setAppliedProfileSelection(
    _ profileIDs: [UUID],
    lastActivatedProfileID: UUID? = nil,
    context: NSManagedObjectContext
) throws {
    let selected = Set(profileIDs)
    let profiles = try context.fetch(Profile.fetchRequest())
    let now = Date()
    for profile in profiles where !profile.isSystem {
        let applied = profile.id.map(selected.contains) ?? false
        profile.setApplied(applied)
        profile.updatedAt = now
        if applied && profile.id == lastActivatedProfileID {
            profile.lastActivatedAt = now
        }
    }
}

nonisolated enum HostsRecoveryAction: Equatable {
    case keepSystemFile
    case reapplyProfiles([UUID])

    var appliedProfileIDs: [UUID] {
        switch self {
        case .keepSystemFile:
            return []
        case .reapplyProfiles(let ids):
            return ids
        }
    }
}

nonisolated enum HostsRecoveryPlanner {
    static func resolve(
        baseline: HostsReconciliationBaseline?
    ) -> HostsRecoveryAction? {
        guard let baseline, baseline.stateCommitFailed else { return nil }
        return .reapplyProfiles(
            baseline.pendingAppliedProfileIDs ?? baseline.appliedProfileIDs
        )
    }
}

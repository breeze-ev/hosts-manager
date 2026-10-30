import CoreData
import Foundation

/// Commits the backup record and profile state in one Core Data transaction.
/// The hosts file has already been written when this runs. If the transaction
/// fails, the caller must retain the pending file state for recovery.
@MainActor
@discardableResult
func commitHostsWrite(
    result: HostsWriteResult,
    context: NSManagedObjectContext,
    profileName: String?,
    note: String,
    appliedProfileIDs: [UUID],
    checkStateIntegrity: () -> Bool = { true },
    stateChanges: () throws -> Void
) throws -> Bool {
    let record = BackupRecord(context: context)
    record.id = UUID()
    record.timestamp = Date()
    record.filePath = result.backupURL.path
    record.profileName = profileName
    record.note = note

    do {
        try stateChanges()
        guard checkStateIntegrity() else {
            throw HostsWriteStateReconciliationError()
        }
        try context.save()
    } catch {
        context.rollback()
        NotificationCenter.default.post(
            name: .hostsStateNeedsReconciliation,
            object: result.content,
            userInfo: [
                HostsStateNotificationKey.appliedProfileIDs: appliedProfileIDs
            ]
        )
        throw error
    }

    do {
        try BackupMaintenance.prune(context: context)
    } catch {
        // Cleanup is outside the write transaction. Roll back any queued record
        // deletions so an unrelated save cannot commit a partial cleanup.
        context.rollback()
    }
    return true
}

import Foundation

nonisolated struct HostsWriteConflictError: Error {
    let profileID: UUID
}

nonisolated struct HostsWriteAbortedError: Error {}

/// The file was written, but the corresponding Core Data state could not be saved.
nonisolated struct HostsWriteCommitError: Error {
    let result: HostsWriteResult
    let underlying: any Error
}

nonisolated struct HostsWriteStateReconciliationError: Error {}

nonisolated struct HostsStateRecoveryRequiredError: Error {}

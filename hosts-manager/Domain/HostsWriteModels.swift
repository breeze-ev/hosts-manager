import Foundation

nonisolated struct HostsWriteResult: Equatable, Sendable {
    let content: String
    let backupURL: URL
}

nonisolated struct HostsWriteRequest: Sendable {
    let content: String
    /// Exact profile selection represented by `content`. Persisting this before
    /// the Core Data commit makes an interrupted write recoverable after relaunch.
    let appliedProfileIDs: [UUID]?
    /// Hostnames generated from profile definitions. The previous set lets a
    /// later edit remove renamed or deleted profile rows.
    let managedHostnames: [String]

    init(
        content: String,
        appliedProfileIDs: [UUID]? = nil,
        managedHostnames: [String] = []
    ) {
        self.content = content
        self.appliedProfileIDs = appliedProfileIDs
        self.managedHostnames = managedHostnames
    }
}

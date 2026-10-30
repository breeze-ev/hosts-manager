import Foundation

nonisolated struct HostsReconciliationBaseline: Equatable {
    let fingerprint: String
    let appliedProfileIDs: [UUID]
    let pendingAppliedProfileIDs: [UUID]?
    let managedHostnames: [String]
    let stateCommitFailed: Bool
}

nonisolated enum HostsReconciliationBaselineStore {
    private static let fingerprintKey = "hostsReconciliation.fingerprint"
    private static let appliedProfileIDsKey = "hostsReconciliation.appliedProfileIDs"
    private static let pendingAppliedProfileIDsKey = "hostsReconciliation.pendingAppliedProfileIDs"
    private static let managedHostnamesKey = "hostsReconciliation.managedHostnames"
    private static let stateCommitFailedKey = "hostsReconciliation.stateCommitFailed"

    static func load(from defaults: UserDefaults = .standard) -> HostsReconciliationBaseline? {
        guard let fingerprint = defaults.string(forKey: fingerprintKey) else {
            return nil
        }
        let rawIDs = defaults.stringArray(forKey: appliedProfileIDsKey) ?? []
        let pendingRawIDs = defaults.object(forKey: pendingAppliedProfileIDsKey) as? [String]
        return HostsReconciliationBaseline(
            fingerprint: fingerprint,
            appliedProfileIDs: rawIDs.compactMap(UUID.init(uuidString:)),
            pendingAppliedProfileIDs: pendingRawIDs?.compactMap(UUID.init(uuidString:)),
            managedHostnames: defaults.stringArray(forKey: managedHostnamesKey) ?? [],
            stateCommitFailed: defaults.bool(forKey: stateCommitFailedKey)
        )
    }

    static func save(
        _ baseline: HostsReconciliationBaseline,
        to defaults: UserDefaults = .standard
    ) {
        write(baseline, to: defaults)
        defaults.synchronize()
    }

    private static func write(
        _ baseline: HostsReconciliationBaseline,
        to defaults: UserDefaults
    ) {
        defaults.set(baseline.fingerprint, forKey: fingerprintKey)
        defaults.set(
            baseline.appliedProfileIDs.map(\.uuidString),
            forKey: appliedProfileIDsKey
        )
        if let pending = baseline.pendingAppliedProfileIDs {
            defaults.set(
                pending.map(\.uuidString),
                forKey: pendingAppliedProfileIDsKey
            )
        } else {
            defaults.removeObject(forKey: pendingAppliedProfileIDsKey)
        }
        defaults.set(
            baseline.managedHostnames,
            forKey: managedHostnamesKey
        )
        defaults.set(baseline.stateCommitFailed, forKey: stateCommitFailedKey)
    }

    /// Persist the intended selection before touching the system file. If the
    /// process crashes between the file write and the Core Data save, launch
    /// reconciliation can still restore the exact selection that was written.
    static func setPendingAppliedProfileIDs(
        _ profileIDs: [UUID],
        from defaults: UserDefaults = .standard
    ) {
        defaults.set(
            profileIDs.map(\.uuidString),
            forKey: pendingAppliedProfileIDsKey
        )
    }

    /// Record the exact file/state selection immediately after the system file
    /// changes and before Core Data is saved.
    static func markPendingWrite(
        fingerprint: String,
        appliedProfileIDs: [UUID],
        managedHostnames: [String],
        from defaults: UserDefaults = .standard
    ) {
        save(
            HostsReconciliationBaseline(
                fingerprint: fingerprint,
                appliedProfileIDs: appliedProfileIDs,
                pendingAppliedProfileIDs: appliedProfileIDs,
                managedHostnames: managedHostnames,
                stateCommitFailed: true
            ),
            to: defaults
        )
    }

    static func clearPendingAppliedProfileIDs(
        from defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: pendingAppliedProfileIDsKey)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: fingerprintKey)
        defaults.removeObject(forKey: appliedProfileIDsKey)
        defaults.removeObject(forKey: pendingAppliedProfileIDsKey)
        defaults.removeObject(forKey: managedHostnamesKey)
        defaults.removeObject(forKey: stateCommitFailedKey)
    }
}

nonisolated enum HostsReconciliation {
    static func canonical(_ content: String) -> String {
        var mappings = Set<String>()
        for entry in HostsParser.parse(content) where entry.isEnabled {
            for hostname in entry.hostnames {
                mappings.insert("\(entry.ip)|\(hostname.lowercased())")
            }
        }
        return mappings.sorted().joined(separator: "\n")
    }
}

import Foundation
import Testing
@testable import hosts_manager

@MainActor
struct WriteCoordinatorRecoveryTests {
    @Test func persistedRecoveryStateIsDetected() throws {
        let suiteName = "WriteCoordinatorRecoveryTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        HostsReconciliationBaselineStore.markPendingWrite(
            fingerprint: "fingerprint",
            appliedProfileIDs: [UUID()],
            managedHostnames: ["one.local"],
            from: defaults
        )

        #expect(
            HostsWriteCoordinator.persistedStateRecoveryIsRequired(
                from: defaults
            )
        )
    }

    @Test func coordinatorCreatedAfterCommitFailureRejectsWrites() async throws {
        let access = RecoveryTestHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(
            access: access,
            requiresStateRecovery: true
        )

        do {
            _ = try await coordinator.write(
                "127.0.0.1 localhost\n10.0.0.1 blocked.local\n"
            )
            Issue.record("Expected writes to remain blocked after relaunch")
        } catch is HostsStateRecoveryRequiredError {
            // Expected.
        }
    }
}

@MainActor
private final class RecoveryTestHostsAccess: HostsFileAccess {
    var content: String

    init(content: String) {
        self.content = content
    }

    func read() throws -> String {
        content
    }

    func write(_ content: String) async throws {
        self.content = content
    }
}

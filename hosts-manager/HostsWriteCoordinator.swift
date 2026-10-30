import Combine
import Foundation

/// 串行化所有对 /etc/hosts 的写入。
///
/// 旧实现用一个 `isWriting` 标志让并发请求直接失败，由配置开关、应用面板、
/// 实时应用三处各自重试：快速连续操作时会出现“文件其实写成功了、
/// 界面却弹写入失败并把状态回滚”的割裂。
///
/// 每个请求都会执行。`perform` 在队列轮到自己时读取最新文件并生成目标内容，
/// 在下一次写入开始前完成状态提交，因此后一个请求能看到前一个请求提交后的配置状态。
@MainActor
final class HostsWriteCoordinator: ObservableObject {
    static let shared = HostsWriteCoordinator(
        access: SystemHostsFileAccess(),
        requiresStateRecovery: persistedStateRecoveryIsRequired()
    )

    @Published private(set) var isWriting = false

    private let access: any HostsFileAccess
    private let backupDirectory: URL?

    private var tail: Task<Void, Never>?
    private var pendingOperationCount = 0
    /// Writes stay blocked only when a successful file write could not commit
    /// its matching Core Data state. External file edits never set this flag.
    private(set) var requiresStateRecovery: Bool

    init(
        access: any HostsFileAccess,
        backupDirectory: URL? = nil,
        requiresStateRecovery: Bool = false
    ) {
        self.access = access
        self.backupDirectory = backupDirectory
        self.requiresStateRecovery = requiresStateRecovery
    }

    static func persistedStateRecoveryIsRequired(
        from defaults: UserDefaults = .standard
    ) -> Bool {
        HostsRecoveryPlanner.resolve(
            baseline: HostsReconciliationBaselineStore.load(from: defaults)
        ) != nil
    }

    func write(_ content: String) async throws -> HostsWriteResult {
        try await perform(
            makeContent: { _ in HostsWriteRequest(content: content) },
            commit: { _ in }
        )
    }

    /// Serializes content generation, the privileged file write, and state commit.
    /// `makeContent` runs at the queue head and receives the current system file,
    /// allowing profile writes to merge external edits automatically.
    func perform(
        makeContent: @escaping @MainActor (String) throws -> HostsWriteRequest,
        commit: @escaping @MainActor (HostsWriteResult) throws -> Void
    ) async throws -> HostsWriteResult {
        let previous = tail
        pendingOperationCount += 1
        isWriting = true

        let operation = Task { @MainActor [weak self] () -> Result<HostsWriteResult, Error> in
            await previous?.value
            guard let self else { return .failure(CancellationError()) }
            defer { self.finishOperation() }

            do {
                guard !self.requiresStateRecovery else {
                    throw HostsStateRecoveryRequiredError()
                }
                let current = try self.access.read()
                let request = try makeContent(current)
                if let validationError = HostsValueValidator.validate(content: request.content) {
                    throw HostsWriteError.invalidContent(validationError)
                }
                let result = try await self.performWrite(request, current: current)
                do {
                    try commit(result)
                } catch {
                    self.requiresStateRecovery = true
                    if let appliedProfileIDs = request.appliedProfileIDs {
                        self.requiresStateRecoveryAfterCommitFailure(
                            content: result.content,
                            appliedProfileIDs: appliedProfileIDs,
                            managedHostnames: request.managedHostnames
                        )
                    }
                    return .failure(HostsWriteCommitError(result: result, underlying: error))
                }
                if let appliedProfileIDs = request.appliedProfileIDs {
                    HostsReconciliationBaselineStore.save(
                        HostsReconciliationBaseline(
                            fingerprint: HostsReconciliation.canonical(result.content),
                            appliedProfileIDs: appliedProfileIDs,
                            pendingAppliedProfileIDs: nil,
                            managedHostnames: request.managedHostnames,
                            stateCommitFailed: false
                        )
                    )
                }
                var userInfo: [AnyHashable: Any] = [
                    HostsStateNotificationKey.managedHostnames: request.managedHostnames
                ]
                if let appliedProfileIDs = request.appliedProfileIDs {
                    userInfo[HostsStateNotificationKey.appliedProfileIDs] = appliedProfileIDs
                }
                NotificationCenter.default.post(
                    name: .hostsStateSynchronized,
                    object: result.content,
                    userInfo: userInfo
                )
                return .success(result)
            } catch {
                return .failure(error)
            }
        }

        tail = Task { @MainActor in
            _ = await operation.value
        }
        return try await operation.value.get()
    }

    private func finishOperation() {
        pendingOperationCount = max(0, pendingOperationCount - 1)
        if pendingOperationCount == 0 {
            isWriting = false
        }
    }

    private func performWrite(
        _ request: HostsWriteRequest,
        current: String
    ) async throws -> HostsWriteResult {
        if requiresStateRecovery {
            throw HostsStateRecoveryRequiredError()
        }
        let backupURL = try BackupManager.createBackup(of: current, in: backupDirectory)
        try await access.write(request.content)
        let verifiedContent = try access.read()
        guard verifiedContent == request.content else {
            requiresStateRecovery = true
            if let appliedProfileIDs = request.appliedProfileIDs {
                HostsReconciliationBaselineStore.markPendingWrite(
                    fingerprint: HostsReconciliation.canonical(verifiedContent),
                    appliedProfileIDs: appliedProfileIDs,
                    managedHostnames: request.managedHostnames
                )
            }
            throw HostsWriteError.verificationFailed
        }
        if let appliedProfileIDs = request.appliedProfileIDs {
            HostsReconciliationBaselineStore.markPendingWrite(
                fingerprint: HostsReconciliation.canonical(verifiedContent),
                appliedProfileIDs: appliedProfileIDs,
                managedHostnames: request.managedHostnames
            )
        }
        NotificationCenter.default.post(name: .hostsContentChanged, object: request.content)
        return HostsWriteResult(content: request.content, backupURL: backupURL)
    }

    /// Clears the write block after the user resolves a failed state commit.
    func clearStateRecovery() {
        requiresStateRecovery = false
    }

    /// Leave the queue blocked and persist the exact state that existed when a
    /// file write succeeded but its Core Data commit failed.
    func requiresStateRecoveryAfterCommitFailure(
        content: String,
        appliedProfileIDs: [UUID],
        managedHostnames: [String]
    ) {
        let fingerprint = HostsReconciliation.canonical(content)
        requiresStateRecovery = true
        HostsReconciliationBaselineStore.markPendingWrite(
            fingerprint: fingerprint,
            appliedProfileIDs: appliedProfileIDs,
            managedHostnames: managedHostnames
        )
    }
}

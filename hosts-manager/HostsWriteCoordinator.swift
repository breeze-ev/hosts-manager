import Combine
import Foundation

extension Notification.Name {
    static let hostsContentChanged = Notification.Name("hostsManager.hostsContentChanged")
}

protocol HostsFileAccess {
    func read() throws -> String
    func write(_ content: String) async throws
}

struct HostsWriteResult: Equatable, Sendable {
    let content: String
    let backupURL: URL
}

struct HostsWriteRequest: Sendable {
    let content: String
    /// Fingerprint of the file the caller believes is still current. `nil`
    /// explicitly allows an overwrite, such as restoring a backup.
    let expectedCurrentFingerprint: String?
    /// Exact profile selection represented by `content`. Persisting this before
    /// the Core Data commit makes an interrupted write recoverable after relaunch.
    let appliedProfileIDs: [UUID]?

    init(
        content: String,
        expectedCurrentFingerprint: String? = nil,
        appliedProfileIDs: [UUID]? = nil
    ) {
        self.content = content
        self.expectedCurrentFingerprint = expectedCurrentFingerprint
        self.appliedProfileIDs = appliedProfileIDs
    }
}

/// The file was written, but the corresponding Core Data state could not be saved.
struct HostsWriteCommitError: Error {
    let result: HostsWriteResult
    let underlying: Error
}

struct HostsWriteStateReconciliationError: Error {}

struct HostsReconciliationRequiredError: Error {}

struct SystemHostsFileAccess: HostsFileAccess {
    func read() throws -> String {
        try HostsWriter.readContent()
    }

    func write(_ content: String) async throws {
        try await HostsWriter.write(content)
    }
}

/// 串行化所有对 /etc/hosts 的写入。
///
/// 旧实现用一个 `isWriting` 标志让并发请求直接失败，由配置开关、应用面板、
/// 实时应用三处各自重试：快速连续操作时会出现“文件其实写成功了、
/// 界面却弹写入失败并把状态回滚”的割裂。
///
/// 每个请求都会执行，不合并内容。`perform` 在队列轮到自己时才计算目标内容，
/// 并在下一次写入开始前完成状态提交，因此后一个请求能看到前一个请求提交后的配置状态。
@MainActor
final class HostsWriteCoordinator: ObservableObject {
    static let shared = HostsWriteCoordinator(access: SystemHostsFileAccess())

    @Published private(set) var isWriting = false

    private let access: any HostsFileAccess
    private let backupDirectory: URL?

    private var tail: Task<Void, Never>?
    private var pendingOperationCount = 0
    /// The file content written by this coordinator. A queued request may
    /// carry a fingerprint from before an earlier internal write completed;
    /// matching this value proves the intervening change was not external.
    private var lastWrittenFingerprint: String?
    /// The file must not be overwritten until the app has surfaced a
    /// reconciliation choice for an external edit or a failed state commit.
    private var requiresReconciliation = false

    init(access: any HostsFileAccess, backupDirectory: URL? = nil) {
        self.access = access
        self.backupDirectory = backupDirectory
    }

    func write(
        _ content: String,
        expectedCurrentFingerprint: String?
    ) async throws -> HostsWriteResult {
        try await perform(
            makeContent: {
                HostsWriteRequest(
                    content: content,
                    expectedCurrentFingerprint: expectedCurrentFingerprint
                )
            },
            commit: { _ in }
        )
    }

    /// Serializes content generation, the privileged file write, and state commit.
    /// `makeContent` runs only after all previously queued operations have committed.
    func perform(
        makeContent: @escaping @MainActor () throws -> HostsWriteRequest,
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
                guard !self.requiresReconciliation else {
                    throw HostsReconciliationRequiredError()
                }
                let request = try makeContent()
                if let validationError = HostsValueValidator.validate(content: request.content) {
                    throw HostsWriteError.invalidContent(validationError)
                }
                let result = try await self.performWrite(request)
                do {
                    try commit(result)
                } catch {
                    self.requiresReconciliation = true
                    if let appliedProfileIDs = request.appliedProfileIDs {
                        self.requiresReconciliationAfterStateCommitFailure(
                            content: result.content,
                            appliedProfileIDs: appliedProfileIDs
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
                            stateCommitFailed: false
                        )
                    )
                }
                NotificationCenter.default.post(
                    name: .hostsStateSynchronized,
                    object: result.content,
                    userInfo: request.appliedProfileIDs.map {
                        [HostsStateNotificationKey.appliedProfileIDs: $0]
                    }
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

    private func performWrite(_ request: HostsWriteRequest) async throws -> HostsWriteResult {
        let current = try access.read()
        let currentFingerprint = HostsReconciliation.canonical(current)
        if requiresReconciliation {
            throw HostsReconciliationRequiredError()
        }
        if let expected = request.expectedCurrentFingerprint {
            let internalFingerprint = lastWrittenFingerprint
            guard currentFingerprint == expected || currentFingerprint == internalFingerprint else {
                requiresReconciliation = true
                throw HostsReconciliationRequiredError()
            }
        }
        let backupURL = try BackupManager.createBackup(of: current, in: backupDirectory)
        try await access.write(request.content)
        let verifiedContent = try access.read()
        guard verifiedContent == request.content else {
            requiresReconciliation = true
            if let appliedProfileIDs = request.appliedProfileIDs {
                HostsReconciliationBaselineStore.markPendingWrite(
                    fingerprint: HostsReconciliation.canonical(verifiedContent),
                    appliedProfileIDs: appliedProfileIDs
                )
            }
            throw HostsWriteError.verificationFailed
        }
        if let appliedProfileIDs = request.appliedProfileIDs {
            HostsReconciliationBaselineStore.markPendingWrite(
                fingerprint: HostsReconciliation.canonical(verifiedContent),
                appliedProfileIDs: appliedProfileIDs
            )
        }
        lastWrittenFingerprint = HostsReconciliation.canonical(verifiedContent)
        requiresReconciliation = false
        NotificationCenter.default.post(name: .hostsContentChanged, object: request.content)
        return HostsWriteResult(content: request.content, backupURL: backupURL)
    }

    /// Clears an external-edit block after the user explicitly chose to keep
    /// the live file or overwrite it with the current applied selection.
    func reconcile(currentContent: String) {
        lastWrittenFingerprint = HostsReconciliation.canonical(currentContent)
        requiresReconciliation = false
    }

    /// Leave the queue blocked and persist the exact state that existed when a
    /// file write succeeded but its Core Data commit failed.
    func requiresReconciliationAfterStateCommitFailure(
        content: String,
        appliedProfileIDs: [UUID]
    ) {
        let fingerprint = HostsReconciliation.canonical(content)
        lastWrittenFingerprint = fingerprint
        requiresReconciliation = true
        HostsReconciliationBaselineStore.markPendingWrite(
            fingerprint: fingerprint,
            appliedProfileIDs: appliedProfileIDs
        )
    }
}

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
}

/// The file was written, but the corresponding Core Data state could not be saved.
struct HostsWriteCommitError: Error {
    let result: HostsWriteResult
    let underlying: Error
}

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

    init(access: any HostsFileAccess, backupDirectory: URL? = nil) {
        self.access = access
        self.backupDirectory = backupDirectory
    }

    func write(_ content: String) async throws -> HostsWriteResult {
        try await perform(makeContent: { HostsWriteRequest(content: content) }, commit: { _ in })
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
                let request = try makeContent()
                if let validationError = HostsValueValidator.validate(content: request.content) {
                    throw HostsWriteError.invalidContent(validationError)
                }
                let result = try await self.performWrite(request.content)
                do {
                    try commit(result)
                } catch {
                    return .failure(HostsWriteCommitError(result: result, underlying: error))
                }
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

    private func performWrite(_ content: String) async throws -> HostsWriteResult {
        let current = try access.read()
        let backupURL = try BackupManager.createBackup(of: current, in: backupDirectory)
        try await access.write(content)
        let verifiedContent = try access.read()
        guard verifiedContent == content else {
            throw HostsWriteError.verificationFailed
        }
        NotificationCenter.default.post(name: .hostsContentChanged, object: nil)
        return HostsWriteResult(content: content, backupURL: backupURL)
    }
}

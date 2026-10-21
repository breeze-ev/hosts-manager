import Combine
import Foundation

extension Notification.Name {
    static let hostsContentChanged = Notification.Name("hostsManager.hostsContentChanged")
}

protocol HostsFileAccess {
    func read() throws -> String
    func write(_ content: String) async throws
}

struct SystemHostsFileAccess: HostsFileAccess {
    func read() throws -> String {
        try HostsWriter.readContent()
    }

    func write(_ content: String) async throws {
        try await HostsWriter.write(content)
    }
}

@MainActor
final class HostsWriteCoordinator: ObservableObject {
    static let shared = HostsWriteCoordinator(access: SystemHostsFileAccess())

    @Published private(set) var isWriting = false

    private let access: any HostsFileAccess
    private let backupDirectory: URL?

    init(access: any HostsFileAccess, backupDirectory: URL? = nil) {
        self.access = access
        self.backupDirectory = backupDirectory
    }

    func write(_ content: String) async throws -> URL {
        guard !isWriting else {
            throw HostsWriteError.alreadyInProgress
        }
        if let validationError = HostsValueValidator.validate(content: content) {
            throw HostsWriteError.invalidContent(validationError)
        }

        isWriting = true
        defer { isWriting = false }

        let current = try access.read()
        let backupURL = try BackupManager.createBackup(of: current, in: backupDirectory)
        let verifiedContent: String
        do {
            try await access.write(content)
            verifiedContent = try access.read()
        } catch {
            throw error
        }

        guard verifiedContent == content else {
            throw HostsWriteError.verificationFailed
        }
        NotificationCenter.default.post(name: .hostsContentChanged, object: nil)
        return backupURL
    }
}

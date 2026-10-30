import Foundation

// MARK: - Privileged write via Authorization Services

enum HostsWriteError: LocalizedError {
    case invalidContent(String)
    case authorizationFailed
    case helperUnavailable
    case writeFailed
    case readFailed
    case verificationFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case let .invalidContent(message): return message
        case .authorizationFailed: return "Unable to establish administrator authorization."
        case .helperUnavailable: return "The background writer helper is unavailable. Enable and approve it in Settings."
        case .writeFailed: return "Failed to write /etc/hosts."
        case .readFailed: return "Unable to read /etc/hosts."
        case .verificationFailed: return "Verification failed after writing /etc/hosts."
        case .timedOut: return "The background writer helper timed out."
        }
    }
}

enum HostsWriter {
    static let hostsPath = "/etc/hosts"

    static func readContent() throws -> String {
        do {
            return try String(contentsOfFile: hostsPath, encoding: .utf8)
        } catch {
            throw HostsWriteError.readFailed
        }
    }

    static func currentContent() -> String {
        (try? readContent()) ?? ""
    }

    /// Write the given content to /etc/hosts with elevated privileges.
    /// Writes through the privileged LaunchDaemon helper exclusively (silent,
    /// app-attributed). No admin-password prompt is used.
    static func write(_ content: String) async throws {
        if let validationError = HostsValueValidator.validate(content: content) {
            throw HostsWriteError.invalidContent(validationError)
        }

        HostsHelperClient.registerIfNeeded()
        guard HostsHelperClient.isRegistered else {
            throw HostsWriteError.helperUnavailable
        }
        guard await HostsHelperClient.ensureResponding() else {
            throw HostsWriteError.helperUnavailable
        }
        switch await HostsHelperClient.write(content) {
        case .success:
            return
        case .invalidContent:
            throw HostsWriteError.invalidContent("The helper rejected the hosts content.")
        case .writeFailed:
            throw HostsWriteError.writeFailed
        case .unauthorized:
            throw HostsWriteError.authorizationFailed
        case .unavailable:
            throw HostsWriteError.helperUnavailable
        case .timedOut:
            throw HostsWriteError.timedOut
        }
    }
}

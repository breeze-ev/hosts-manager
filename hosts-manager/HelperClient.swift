import Foundation
import ServiceManagement

enum HostsHelperClientResult {
    case success
    case invalidContent
    case writeFailed
    case unauthorized
    case unavailable
    case timedOut
}

enum HostsHelperClient {
    private static let responseTimeout: TimeInterval = 20

    static let serviceName = HostsHelperConstants.serviceName
    static let daemonPlistName = HostsHelperConstants.daemonPlistName

    static var isRegistered: Bool {
        SMAppService.daemon(plistName: daemonPlistName).status == .enabled
    }

    static func statusLabel(isEnglish: Bool) -> String {
        let status = SMAppService.daemon(plistName: daemonPlistName).status
        switch status {
        case .enabled:
            return isEnglish ? "Enabled (silent writes)" : "已启用（静默写入）"
        case .requiresApproval:
            return isEnglish
                ? "Waiting for approval in System Settings > General > Login Items & Extensions"
                : "待批准：请在系统设置 → 通用 → 登录项与扩展中允许"
        case .notRegistered:
            return isEnglish ? "Not installed" : "未安装"
        case .notFound:
            return isEnglish ? "Helper is not embedded" : "未找到助手（助手未嵌入）"
        @unknown default:
            return isEnglish ? "Unknown status" : "未知状态"
        }
    }

    static func install() -> String? {
        let service = SMAppService.daemon(plistName: daemonPlistName)
        do {
            try service.register()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func repair() -> String? {
        let service = SMAppService.daemon(plistName: daemonPlistName)
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            try service.register()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func registerIfNeeded() {
        let service = SMAppService.daemon(plistName: daemonPlistName)
        guard service.status == .notRegistered || service.status == .requiresApproval else { return }
        try? service.register()
    }

    static func write(_ content: String) async -> HostsHelperClientResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<HostsHelperClientResult, Never>) in
            let gate = XPCReplyGate(continuation)
            let connection = NSXPCConnection(machServiceName: serviceName)
            let connectionBox = XPCConnectionBox(connection)
            connection.remoteObjectInterface = NSXPCInterface(with: HostsHelperServiceProtocol.self)
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                connectionBox.invalidate()
                gate.finish(.unavailable)
            } as? HostsHelperServiceProtocol
            guard let proxy else {
                connectionBox.invalidate()
                gate.finish(.unavailable)
                return
            }
            proxy.writeHosts(content) { code, _ in
                connectionBox.invalidate()
                switch HostsHelperErrorCode(rawValue: code) {
                case .success:
                    gate.finish(.success)
                case .invalidContent:
                    gate.finish(.invalidContent)
                case .writeFailed:
                    gate.finish(.writeFailed)
                case .unauthorized:
                    gate.finish(.unauthorized)
                case .unavailable, .none:
                    gate.finish(.unavailable)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + responseTimeout) {
                connectionBox.invalidate()
                gate.finish(.timedOut)
            }
        }
    }
}

private final class XPCConnectionBox: @unchecked Sendable {
    nonisolated(unsafe) private let connection: NSXPCConnection

    nonisolated init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    nonisolated func invalidate() {
        connection.invalidate()
    }
}

private final class XPCReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<HostsHelperClientResult, Never>?

    nonisolated init(_ continuation: CheckedContinuation<HostsHelperClientResult, Never>) {
        self.continuation = continuation
    }

    nonisolated func finish(_ result: HostsHelperClientResult) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

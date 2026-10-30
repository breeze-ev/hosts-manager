import Foundation
import ServiceManagement

enum HostsHelperClientResult: Sendable {
    case success
    case invalidContent
    case writeFailed
    case unauthorized
    case unavailable
    case timedOut
}

enum HostsHelperClient {
    private static let responseTimeout: TimeInterval = 20
    private static let pingTimeout: TimeInterval = 3

    static let serviceName = HostsHelperConstants.serviceName
    static let daemonPlistName = HostsHelperConstants.daemonPlistName

    private static var daemon: SMAppService {
        SMAppService.daemon(plistName: daemonPlistName)
    }

    static var status: SMAppService.Status {
        daemon.status
    }

    static var isRegistered: Bool {
        status == .enabled
    }

    static func statusLabel(isEnglish: Bool) -> String {
        statusLabel(for: status, isEnglish: isEnglish)
    }

    nonisolated static func statusLabel(
        for status: SMAppService.Status,
        isEnglish: Bool
    ) -> String {
        switch status {
        case .enabled:
            return isEnglish ? "Enabled" : "已启用"
        case .requiresApproval:
            return isEnglish ? "Not enabled (pending approval)" : "未启用（待批准）"
        case .notRegistered, .notFound:
            return isEnglish ? "Not enabled" : "未启用"
        @unknown default:
            return isEnglish ? "Not enabled" : "未启用"
        }
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Enables the background write helper. When a previous registration is stuck
    /// waiting for approval, clears it first: once the app is re-signed, calling
    /// register() over the old registration fails with
    /// SMAppServiceError.notPermitted ("Operation not permitted").
    static func enable(isEnglish: Bool) -> String? {
        let service = daemon
        if service.status == .enabled {
            return nil
        }
        if service.status == .requiresApproval || service.status == .notFound {
            try? service.unregister()
        }
        return register(service, isEnglish: isEnglish)
    }

    private static func register(_ service: SMAppService, isEnglish: Bool) -> String? {
        do {
            try service.register()
            return nil
        } catch {
            return localizedRegistrationError(error, isEnglish: isEnglish)
        }
    }

    static func registerIfNeeded() {
        let service = daemon
        switch service.status {
        case .enabled:
            return
        case .requiresApproval, .notFound:
            try? service.unregister()
        case .notRegistered:
            break
        @unknown default:
            break
        }
        try? service.register()
    }

    /// Re-registers the helper when an existing registration is stale or the
    /// launchd service no longer resolves inside the current app bundle.
    static func repair() {
        let service = daemon
        try? service.unregister()
        try? service.register()
    }

    static func isResponding() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = XPCReplyGate(continuation)
            let connection = NSXPCConnection(machServiceName: serviceName)
            let connectionBox = XPCConnectionBox(connection)
            connection.remoteObjectInterface = NSXPCInterface(with: HostsHelperServiceProtocol.self)
            connection.resume()
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                connectionBox.invalidate()
                gate.finish(false)
            } as? HostsHelperServiceProtocol
            guard let proxy else {
                connectionBox.invalidate()
                gate.finish(false)
                return
            }
            proxy.ping { code in
                connectionBox.invalidate()
                gate.finish(code == HostsHelperErrorCode.success.rawValue)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + pingTimeout) {
                connectionBox.invalidate()
                gate.finish(false)
            }
        }
    }

    static func ensureResponding() async -> Bool {
        if await isResponding() {
            return true
        }
        repair()
        guard isRegistered else { return false }
        return await isResponding()
    }

    private static func localizedRegistrationError(_ error: Error, isEnglish: Bool) -> String {
        let nsError = error as NSError
        let isSMError = nsError.domain == SMAppServiceErrorDomain
        let description = nsError.localizedDescription
        let deniedBySystem = isSMError
            && (nsError.code == 2 || description.localizedCaseInsensitiveContains("Operation not permitted"))

        if deniedBySystem {
            return isEnglish
                ? "The system denied the registration (Operation not permitted). Tap Enable Helper to clear the old entry, then allow it in System Settings > General > Login Items & Extensions."
                : "系统拒绝了注册（Operation not permitted）。请点“启用助手”清理旧注册，再在“系统设置 → 通用 → 登录项与扩展”中允许本应用。"
        }
        if isSMError && nsError.code == 1 {
            return isEnglish
                ? "The app signature is invalid. The helper requires a build signed with an Apple Development or Developer ID identity."
                : "应用签名无效，无法安装后台写入助手。请使用 Apple Development 或 Developer ID 签名构建。"
        }
        if isSMError && [3, 8, 9].contains(nsError.code) {
            return isEnglish
                ? "The helper or its launchd plist isn't embedded in the app bundle. Rebuild and run the latest build."
                : "应用包内未找到助手或其配置，请重新构建并运行最新版本。"
        }
        if isSMError && nsError.code == 4 {
            return isEnglish
                ? "An entitlement required to install the helper is missing. Check the app's signing and capabilities."
                : "缺少安装助手所需的授权（entitlement），请检查应用的签名与能力配置。"
        }
        if isSMError && [5, 10].contains(nsError.code) {
            return isEnglish
                ? "Helper registration failed. Tap Enable Helper to try again, or remove the old entry in System Settings first."
                : "助手注册失败。请点击“启用助手”重试，或先在系统设置中移除旧注册。"
        }
        return isEnglish
            ? "Registration failed: \(description)"
            : "注册失败：\(description)"
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

private final class XPCReplyGate<Result: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Result, Never>?

    nonisolated init(_ continuation: CheckedContinuation<Result, Never>) {
        self.continuation = continuation
    }

    nonisolated func finish(_ result: Result) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

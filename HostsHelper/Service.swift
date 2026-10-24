import Foundation
import Security

final class HostsHelperService: NSObject, HostsHelperServiceProtocol {
    private static let writeQueue = DispatchQueue(label: "com.breeze.hostsmanager.helper.write")
    private let hostsURL = URL(fileURLWithPath: "/etc/hosts")

    func writeHosts(
        _ content: String,
        withReply reply: @escaping (Int32, String?) -> Void
    ) {
        Self.writeQueue.async {
            do {
                try HostsAtomicFileWriter.write(content, to: self.hostsURL)
                reply(HostsHelperErrorCode.success.rawValue, nil)
            } catch HostsAtomicFileWriteError.invalidContent(let message) {
                reply(HostsHelperErrorCode.invalidContent.rawValue, message)
            } catch {
                reply(HostsHelperErrorCode.writeFailed.rawValue, error.localizedDescription)
            }
        }
    }

    func ping(
        withReply reply: @escaping (Int32) -> Void
    ) {
        reply(HostsHelperErrorCode.success.rawValue)
    }
}

final class HostsHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HostsHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard HostsHelperAuthorization.accepts(newConnection) else {
            NSLog("Rejected unauthorized XPC client with pid %d", newConnection.processIdentifier)
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: HostsHelperServiceProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

private enum HostsHelperAuthorization {
    static func accepts(_ connection: NSXPCConnection) -> Bool {
        guard connection.processIdentifier > 0 else { return false }

        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
        ] as CFDictionary
        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
              let guestCode else {
            return false
        }

        guard let teamIdentifier = ownTeamIdentifier() else {
            return false
        }
        let codeRequirement = HostsHelperConstants.clientCodeRequirement(teamIdentifier: teamIdentifier)

        guard !codeRequirement.isEmpty else {
            return false
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            codeRequirement as CFString,
            [],
            &requirement
        ) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(guestCode, [], requirement) == errSecSuccess
    }

    private static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let information,
              let teamIdentifier = (information as NSDictionary)[kSecCodeInfoTeamIdentifier] as? String,
              !teamIdentifier.isEmpty else {
            return nil
        }
        return teamIdentifier
    }
}

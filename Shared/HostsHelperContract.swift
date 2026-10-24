import Foundation

enum HostsHelperConstants {
    static let serviceName = "io.github.breeze-ev.hostsmanager.helper"
    static let daemonPlistName = "io.github.breeze-ev.hostsmanager.helper.plist"
    static let clientBundleIdentifier = "io.github.breeze-ev.hostsmanager"

    static func clientCodeRequirement(teamIdentifier: String) -> String {
        """
        anchor apple generic
        and identifier "\(clientBundleIdentifier)"
        and certificate leaf[subject.OU] = "\(teamIdentifier)"
        """
    }
}

enum HostsHelperErrorCode: Int32 {
    case success = 0
    case invalidContent = 1
    case writeFailed = 2
    case unauthorized = 3
    case unavailable = 4
}

@objc protocol HostsHelperServiceProtocol {
    func writeHosts(
        _ content: String,
        withReply reply: @escaping (Int32, String?) -> Void
    )
}

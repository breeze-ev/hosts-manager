import Foundation

enum HostsHelperConstants {
    static let serviceName = "com.breeze.hostsmanager.helper"
    static let daemonPlistName = "com.breeze.hostsmanager.helper.plist"
    static let clientBundleIdentifier = "personal.hosts-manager"
    static let teamIdentifier = "Y724PV6L7L"
    static let clientCodeRequirement = """
    anchor apple generic
    and identifier "\(clientBundleIdentifier)"
    and certificate leaf[subject.OU] = "\(teamIdentifier)"
    """
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
    func ping(
        withReply reply: @escaping (Int32) -> Void
    )
}

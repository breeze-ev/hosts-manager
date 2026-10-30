import Foundation

// MARK: - Parsed host entry

nonisolated struct ParsedHostEntry: Identifiable, Equatable {
    let id = UUID()
    var ip: String
    var hostnames: [String]
    var desc: String
    var isEnabled: Bool
    var isSystem: Bool

    init(ip: String, hostnames: [String], desc: String = "", isEnabled: Bool = true, isSystem: Bool = false) {
        self.ip = ip
        self.hostnames = hostnames
        self.desc = desc
        self.isEnabled = isEnabled
        self.isSystem = isSystem
    }
}

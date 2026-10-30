import Foundation

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

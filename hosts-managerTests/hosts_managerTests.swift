import Testing
import Foundation
import CoreData
@testable import hosts_manager

struct HostsParserTests {
    @Test func parsesCommentsReservedAndIPv6() {
        let text = """
        # a whole line comment
        127.0.0.1   localhost   # loopback
        ::1         localhost
        # 10.0.0.5  disabled.example.com
        10.0.0.1 # only comment, no host
        """
        let entries = HostsParser.parse(text)

        #expect(entries.count == 3)
        #expect(entries[0].ip == "127.0.0.1")
        #expect(entries[0].hostnames == ["localhost"])
        #expect(entries[0].desc == "loopback")
        #expect(entries[0].isEnabled)
        #expect(entries[0].isSystem)
        #expect(entries[1].ip == "::1")
        #expect(entries[1].isEnabled)
        #expect(entries[1].isSystem)
        #expect(entries[2].ip == "10.0.0.5")
        #expect(entries[2].hostnames == ["disabled.example.com"])
        #expect(!entries[2].isEnabled)
    }

    @Test func mergePreservesSystemAndEnabled() {
        let entries = [
            ParsedHostEntry(ip: "127.0.0.1", hostnames: ["localhost"], isSystem: true),
            ParsedHostEntry(ip: "::1", hostnames: ["localhost"], isSystem: true),
            ParsedHostEntry(ip: "127.0.0.1", hostnames: ["api.local"], isEnabled: true),
            ParsedHostEntry(ip: "10.0.0.9", hostnames: ["old.local"], isEnabled: false)
        ]
        let content = HostsParser.mergedContent(entries: entries)
        #expect(content.contains("# --- System ---"))
        #expect(content.contains("# --- User ---"))
        #expect(content.contains("127.0.0.1"))
        #expect(content.contains("::1"))
        #expect(content.contains("api.local"))
        #expect(!content.contains("old.local"))
    }

    @Test func dedupeRemovesExactDuplicates() {
        let entries = [
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"]),
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"])
        ]
        #expect(HostsParser.dedupe(entries).count == 1)
    }

    @Test func roundTripSerialization() {
        let entries = [
            ParsedHostEntry(ip: "127.0.0.1", hostnames: ["localhost"], desc: "loop"),
            ParsedHostEntry(ip: "9.9.9.9", hostnames: ["off.local"], isEnabled: false)
        ]
        let text = HostsParser.serialize(entries)
        #expect(text.contains("127.0.0.1"))
        #expect(text.contains("# 9.9.9.9"))
    }

    @Test func loopbackUserEntryIsNotSystem() {
        let entries = HostsParser.parse("127.0.0.1 account.jetbrains.com")
        #expect(entries.count == 1)
        #expect(!entries[0].isSystem)
    }

    @Test func rejectsMalformedIPAddresses() {
        let entries = HostsParser.parse("""
        123abc bad.local
        1:evil broken.local
        10.0.0.1 valid.local
        """)
        #expect(entries.count == 1)
        #expect(entries[0].ip == "10.0.0.1")
    }

    @Test func preservesLongIPv6AddressAndScope() {
        let entries = [
            ParsedHostEntry(
                ip: "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
                hostnames: ["long.local"]
            ),
            ParsedHostEntry(ip: "fe80::1%lo0", hostnames: ["link.local"])
        ]
        let text = HostsParser.serialize(entries)
        #expect(text.contains("2001:0db8:85a3:0000:0000:8a2e:0370:7334 long.local"))
        #expect(text.contains("fe80::1%lo0"))
        #expect(HostsValueValidator.validate(content: text) == nil)
    }

    @Test func rejectsUnsafeHostnameCharacters() {
        #expect(!HostsValueValidator.isValidHostname("bad host"))
        #expect(!HostsValueValidator.isValidHostname("bad#host"))
        #expect(!HostsValueValidator.isValidHostname("bad/host"))
        #expect(HostsValueValidator.isValidHostname("api_dev.local"))
    }
}

struct HostValidatorTests {
    @Test func detectsConflictWhenSameHostDifferentIP() {
        let entries = [
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"]),
            ParsedHostEntry(ip: "2.2.2.2", hostnames: ["a.com"])
        ]
        let issues = HostValidator.issues(entries: entries)
        #expect(issues.count == 1)
        #expect(issues.first?.hostname == "a.com")
        #expect(issues.first?.kind == .conflict)
    }

    @Test func detectsDuplicateWhenSameHostSameIP() {
        let entries = [
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"]),
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"])
        ]
        let issues = HostValidator.issues(entries: entries)
        #expect(issues.count == 1)
        #expect(issues.first?.kind == .duplicate)
    }
}

struct HelperContractTests {
    @Test func xpcInterfaceAndClientRequirementAreConfigured() {
        let interface = NSXPCInterface(with: HostsHelperServiceProtocol.self)
        _ = interface
        #expect(HostsHelperConstants.clientCodeRequirement.contains("personal.hosts-manager"))
        #expect(HostsHelperConstants.clientCodeRequirement.contains("Y724PV6L7L"))
        #expect(HostsHelperConstants.clientCodeRequirement.contains("anchor apple generic"))
    }
}

struct BackupManagerTests {
    @Test func createsAndListsAndPrunes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try BackupManager.createBackup(of: "a", in: dir)
        _ = try BackupManager.createBackup(of: "b", in: dir)
        _ = try BackupManager.createBackup(of: "c", in: dir)

        #expect(BackupManager.listBackups(in: dir).count == 3)
        BackupManager.prune(keeping: 1, in: dir)
        #expect(BackupManager.listBackups(in: dir).count == 1)
    }
}

struct AtomicWriterTests {
    @Test func writesAtomicallyAndPreservesMode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("hosts")
        try "127.0.0.1 old.local\n".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)

        let content = "127.0.0.1 localhost\n2001:0db8:85a3:0000:0000:8a2e:0370:7334 long.local\n"
        try HostsAtomicFileWriter.write(content, to: target)

        #expect(try String(contentsOf: target, encoding: .utf8) == content)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".hosts-manager-") }
        #expect(leftovers.isEmpty)
    }

    @Test func rejectsInvalidContentWithoutTouchingTarget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: target, atomically: true, encoding: .utf8)

        #expect(throws: HostsAtomicFileWriteError.self) {
            try HostsAtomicFileWriter.write("123abc bad.local\n", to: target)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "127.0.0.1 localhost\n")
    }
}

@MainActor
struct WriteCoordinatorTests {
    @Test func createsBackupAndVerifiesWrittenContent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let content = "127.0.0.1 localhost\n10.0.0.1 api.local\n"

        let backupURL = try await coordinator.write(content)
        #expect(try String(contentsOf: backupURL, encoding: .utf8) == "127.0.0.1 localhost\n")
        #expect(access.content == content)
        #expect(!coordinator.isWriting)
    }

    @Test func rejectsConcurrentWrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = DelayedHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let content = "127.0.0.1 localhost\n10.0.0.1 api.local\n"
        let firstWrite = Task { try await coordinator.write(content) }

        while !access.started {
            await Task.yield()
        }

        do {
            _ = try await coordinator.write(content)
            Issue.record("A concurrent write should not start")
        } catch HostsWriteError.alreadyInProgress {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        _ = try await firstWrite.value
    }
}

@MainActor
private final class InMemoryHostsAccess: HostsFileAccess {
    var content: String

    init(content: String) {
        self.content = content
    }

    func read() throws -> String {
        content
    }

    func write(_ content: String) async throws {
        self.content = content
    }
}

@MainActor
private final class DelayedHostsAccess: HostsFileAccess {
    var content: String
    private(set) var started = false

    init(content: String) {
        self.content = content
    }

    func read() throws -> String {
        content
    }

    func write(_ content: String) async throws {
        started = true
        try await Task.sleep(for: .milliseconds(50))
        self.content = content
    }
}

@MainActor
struct PersistenceTests {
    @Test func createsDefaultProfilesAndSettings() throws {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)

        let profiles = try controller.container.viewContext.fetch(Profile.fetchRequest())
        #expect(profiles.count == 2)
        #expect(profiles.filter(\.isSystem).count == 1)
        #expect(profiles.contains { $0.isActive })

        let settings = try controller.container.viewContext.fetch(AppSettings.fetchRequest())
        #expect(settings.count == 1)
        #expect(settings.first?.backupRetention == 30)
        #expect(settings.first?.defaultView == "list")
    }
}

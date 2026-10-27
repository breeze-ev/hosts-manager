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

    @Test func mergeUnionsMultipleProfilesAndDedupes() {
        // Simulates two profiles active at once: their enabled entries are
        // flattened into one list before merging, exact duplicates collapse,
        // and disabled entries never appear.
        let profileA = [
            ParsedHostEntry(ip: "10.0.0.1", hostnames: ["api.local"], isEnabled: true),
            ParsedHostEntry(ip: "10.0.0.2", hostnames: ["db.local"], isEnabled: false)
        ]
        let profileB = [
            ParsedHostEntry(ip: "10.0.0.1", hostnames: ["api.local"], isEnabled: true),
            ParsedHostEntry(ip: "10.0.0.3", hostnames: ["cache.local"], isEnabled: true)
        ]
        let content = HostsParser.mergedContent(entries: profileA + profileB)

        let apiCount = content.components(separatedBy: "api.local").count - 1
        #expect(apiCount == 1)
        #expect(content.contains("cache.local"))
        #expect(!content.contains("db.local"))
    }

    @Test func dedupeRemovesExactDuplicates() {
        let entries = [
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"]),
            ParsedHostEntry(ip: "1.1.1.1", hostnames: ["a.com"])
        ]
        #expect(HostsParser.dedupe(entries).count == 1)
    }

    @Test func entriesEquivalentIncludesOrderFieldsAndDisabledState() {
        let base = [
            ParsedHostEntry(ip: "10.0.0.1", hostnames: ["api.local"], desc: "api", isEnabled: true),
            ParsedHostEntry(ip: "10.0.0.2", hostnames: ["db.local"], isEnabled: false)
        ]
        #expect(HostsParser.entriesEquivalent(base, base))
        #expect(!HostsParser.entriesEquivalent(base, Array(base.reversed())))
        #expect(!HostsParser.entriesEquivalent(
            base,
            [
                ParsedHostEntry(ip: "10.0.0.1", hostnames: ["api.local"], desc: "api", isEnabled: false),
                base[1]
            ]
        ))
        #expect(!HostsParser.entriesEquivalent(
            base,
            [
                ParsedHostEntry(ip: "10.0.0.1", hostnames: ["api.local"], desc: "changed"),
                base[1]
            ]
        ))
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

struct HostsReconciliationTests {
    @Test func canonicalComparisonIgnoresFormattingAndOrdering() {
        let live = """
        10.0.0.2   DB.LOCAL api.local # database
        10.0.0.1   api.local # local API
        """
        let expected = """
        # managed by the app
        10.0.0.2 api.local db.local # database
        10.0.0.1 api.local # local API
        """

        #expect(
            HostsReconciliation.inspect(
                liveContent: live,
                expectedContent: expected,
                hasActiveProfiles: true
            ) == .inSync
        )
    }

    @Test func detectsExternalContentAndUnreadableFile() {
        let expected = "10.0.0.1 api.local\n"
        #expect(
            HostsReconciliation.inspect(
                liveContent: "10.0.0.2 api.local\n",
                expectedContent: expected,
                hasActiveProfiles: true
            ) == .externalContent
        )
        #expect(
            HostsReconciliation.inspect(
                liveContent: nil,
                expectedContent: expected,
                hasActiveProfiles: true
            ) == .unreadable
        )
    }

    @Test func noActiveProfilesSkipsReconciliationWarning() {
        #expect(
            HostsReconciliation.inspect(
                liveContent: "10.0.0.9 external.local\n",
                expectedContent: "",
                hasActiveProfiles: false
            ) == .noActiveProfiles
        )
    }

    @Test func reconciliationRequiresTrustedBaselineOrMatchingFile() {
        let content = "10.0.0.1 api.local\n"
        let fingerprint = HostsReconciliation.canonical(content)

        #expect(
            HostsReconciliation.requiresReconciliation(
                liveContent: content,
                lastKnownFingerprint: fingerprint,
                stateCommitFailed: false
            ) == false
        )
        #expect(
            HostsReconciliation.requiresReconciliation(
                liveContent: content,
                lastKnownFingerprint: nil,
                stateCommitFailed: false
            )
        )
        #expect(
            HostsReconciliation.requiresReconciliation(
                liveContent: content,
                lastKnownFingerprint: fingerprint,
                stateCommitFailed: true
            )
        )
    }

    @Test func persistedBaselineRecoversEmptyPendingSelection() {
        let suiteName = "hosts-manager-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected an isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profileID = UUID()

        HostsReconciliationBaselineStore.markPendingWrite(
            fingerprint: HostsReconciliation.canonical("10.0.0.1 api.local\n"),
            appliedProfileIDs: [],
            from: defaults
        )
        let baseline = HostsReconciliationBaselineStore.load(from: defaults)

        #expect(baseline?.pendingAppliedProfileIDs == [])
        #expect(baseline?.stateCommitFailed == true)
        #expect(
            HostsRecoveryPlanner.resolve(
                baseline: baseline,
                liveContent: "10.0.0.2 changed.local\n"
            ) == .reapplyProfiles([])
        )

        HostsReconciliationBaselineStore.save(
            HostsReconciliationBaseline(
                fingerprint: HostsReconciliation.canonical("10.0.0.1 api.local\n"),
                appliedProfileIDs: [profileID],
                pendingAppliedProfileIDs: nil,
                stateCommitFailed: false
            ),
            to: defaults
        )
        #expect(
            HostsRecoveryPlanner.resolve(
                baseline: HostsReconciliationBaselineStore.load(from: defaults),
                liveContent: "10.0.0.2 changed.local\n"
            ) == .keepSystemFile
        )
    }

    @Test func persistedBaselineSupportsAnEmptyFingerprint() {
        let suiteName = "hosts-manager-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected an isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        HostsReconciliationBaselineStore.save(
            HostsReconciliationBaseline(
                fingerprint: "",
                appliedProfileIDs: [],
                pendingAppliedProfileIDs: nil,
                stateCommitFailed: false
            ),
            to: defaults
        )

        #expect(HostsReconciliationBaselineStore.load(from: defaults)?.fingerprint == "")
    }
}

@MainActor
struct ProfileAppliedStateTests {
    @Test func setAppliedKeepsCompatibilityMirrorInSync() throws {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)
        guard let profile = try controller.container.viewContext
            .fetch(Profile.fetchRequest())
            .first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile")
            return
        }

        profile.setApplied(false)
        #expect(!profile.isActive)
        #expect(!profile.isEnabled)
        #expect(!profile.isAppliedForSystem)

        profile.setApplied(true)
        #expect(profile.isActive)
        #expect(profile.isEnabled)
        #expect(profile.isAppliedForSystem)
    }

    @Test func appliedStateRequiresBothCompatibilityFields() throws {
        let controller = PersistenceController(inMemory: true)
        guard let profile = try controller.container.viewContext
            .fetch(Profile.fetchRequest())
            .first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile")
            return
        }

        profile.isActive = true
        profile.isEnabled = false
        #expect(!profile.isAppliedForSystem)

        profile.synchronizeAppliedMirror()
        #expect(profile.isAppliedForSystem)
    }

    @Test func clearingAppliedStateLeavesSystemProfileDisabled() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let profiles = try context.fetch(Profile.fetchRequest())
        guard let custom = profiles.first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile")
            return
        }
        custom.setApplied(true)
        try context.save()

        try clearAppliedStateForUserProfiles(in: context)
        try context.save()

        #expect(!custom.isAppliedForSystem)
        #expect(profiles.filter(\.isSystem).allSatisfy { !$0.isAppliedForSystem })
    }

    @Test func exactAppliedSelectionClearsUnselectedAndSupportsEmpty() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let profiles = try context.fetch(Profile.fetchRequest())
            .filter { !$0.isSystem }
        guard let first = profiles.first,
              let second = profiles.dropFirst().first ?? makeProfile(in: context) else {
            Issue.record("Expected two user profiles")
            return
        }
        first.setApplied(true)
        second.setApplied(true)
        try context.save()

        try setAppliedProfileSelection([first.id!], context: context)
        try context.save()
        #expect(first.isAppliedForSystem)
        #expect(!second.isAppliedForSystem)

        try setAppliedProfileSelection([], context: context)
        try context.save()
        #expect(profiles.allSatisfy { !$0.isAppliedForSystem })
    }

    private func makeProfile(in context: NSManagedObjectContext) -> Profile? {
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = "Test"
        profile.createdAt = Date()
        profile.updatedAt = Date()
        return profile
    }
}

struct HelperContractTests {
    @Test func xpcInterfaceAndClientRequirementAreConfigured() {
        let interface = NSXPCInterface(with: HostsHelperServiceProtocol.self)
        _ = interface
        let requirement = HostsHelperConstants.clientCodeRequirement
        #expect(requirement.contains("personal.hosts-manager"))
        #expect(requirement.contains("Y724PV6L7L"))
        #expect(requirement.contains("anchor apple generic"))
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

    @Test func pruneKeepsProtectedBackupPaths() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldest = try BackupManager.createBackup(of: "a", in: dir)
        _ = try BackupManager.createBackup(of: "b", in: dir)
        _ = try BackupManager.createBackup(of: "c", in: dir)

        BackupManager.prune(
            keeping: 1,
            in: dir,
            excluding: [oldest.path]
        )

        let remaining = BackupManager.listBackups(in: dir)
        #expect(remaining.count == 2)
        #expect(
            remaining.contains {
                $0.standardizedFileURL.path == oldest.standardizedFileURL.path
            }
        )
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

struct HostsImportTests {
    @Test func importsUserEntriesAndSuggestsFileName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("project.hosts")
        try """
        127.0.0.1 localhost
        10.0.0.8 imported.local # imported
        # 10.0.0.9 disabled.local
        """.write(to: file, atomically: true, encoding: .utf8)

        let result = try HostsImport.load(from: file)

        #expect(result.suggestedProfileName == "project")
        #expect(result.entries.count == 2)
        #expect(result.entries[0].hostnames == ["imported.local"])
        #expect(result.entries[0].desc == "imported")
        #expect(!result.entries[1].isEnabled)
    }

    @Test func importsUTF8BOMFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("windows.hosts")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: "10.0.0.10 bom.local\n".utf8)
        try data.write(to: file)

        let result = try HostsImport.load(from: file)

        #expect(result.entries.count == 1)
        #expect(result.entries[0].hostnames == ["bom.local"])
    }

    @Test func rejectsInvalidEncodingAndOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalidUTF8 = directory.appendingPathComponent("invalid.hosts")
        try Data([0xFF, 0xFE]).write(to: invalidUTF8)
        #expect(throws: HostsImportError.self) {
            try HostsImport.load(from: invalidUTF8)
        }

        let oversized = directory.appendingPathComponent("oversized.hosts")
        try Data(count: HostsImport.maximumFileSize + 1).write(to: oversized)
        #expect(throws: HostsImportError.self) {
            try HostsImport.load(from: oversized)
        }
    }

    @Test func rejectsInvalidContentAndFilesWithoutUserEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalid = directory.appendingPathComponent("invalid-content.hosts")
        try "123abc bad.local\n".write(to: invalid, atomically: true, encoding: .utf8)
        #expect(throws: HostsImportError.self) {
            try HostsImport.load(from: invalid)
        }

        let systemOnly = directory.appendingPathComponent("system-only.hosts")
        try "127.0.0.1 localhost\n".write(to: systemOnly, atomically: true, encoding: .utf8)
        #expect(throws: HostsImportError.self) {
            try HostsImport.load(from: systemOnly)
        }
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

        let result = try await coordinator.write(
            content,
            expectedCurrentFingerprint: HostsReconciliation.canonical(access.content)
        )
        #expect(try String(contentsOf: result.backupURL, encoding: .utf8) == "127.0.0.1 localhost\n")
        #expect(result.content == content)
        #expect(access.content == content)
        #expect(!coordinator.isWriting)
    }

    @Test func queuesConcurrentWritesInsteadOfFailing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = DelayedHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let firstContent = "127.0.0.1 localhost\n10.0.0.1 api.local\n"
        let secondContent = "127.0.0.1 localhost\n10.0.0.2 db.local\n"

        let firstWrite = Task {
            try await coordinator.write(
                firstContent,
                expectedCurrentFingerprint: HostsReconciliation.canonical(access.content)
            )
        }
        while !access.started {
            await Task.yield()
        }

        // 第二次写入不再因并发而失败，而是排队执行。
        let secondResult = try await coordinator.write(
            secondContent,
            expectedCurrentFingerprint: HostsReconciliation.canonical(access.content)
        )
        let firstResult = try await firstWrite.value

        #expect(access.content == secondContent)
        #expect(firstResult.content == firstContent)
        #expect(secondResult.content == secondContent)
        #expect(firstResult.backupURL != secondResult.backupURL)
        #expect(!coordinator.isWriting)
    }

    @Test func runsQueuedWritesInOrderWithoutCoalescing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = DelayedHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)

        let initialFingerprint = HostsReconciliation.canonical(access.content)
        let first = Task {
            try await coordinator.write(
                "127.0.0.1 localhost\n10.0.0.1 a.local\n",
                expectedCurrentFingerprint: initialFingerprint
            )
        }
        while !access.started {
            await Task.yield()
        }
        let second = Task {
            try await coordinator.write(
                "127.0.0.1 localhost\n10.0.0.2 b.local\n",
                expectedCurrentFingerprint: initialFingerprint
            )
        }
        let third = Task {
            try await coordinator.write(
                "127.0.0.1 localhost\n10.0.0.3 c.local\n",
                expectedCurrentFingerprint: initialFingerprint
            )
        }
        // 让排队中的两次写入真正入队。
        for _ in 0..<4 {
            await Task.yield()
        }

        let results = try await [first.value, second.value, third.value]

        // 每次请求都独立执行，最终文件是最后一次请求的内容。
        #expect(access.content.contains("c.local"))
        #expect(access.writeCount == 3)
        #expect(results[0].content.contains("a.local"))
        #expect(results[1].content.contains("b.local"))
        #expect(results[2].content.contains("c.local"))
        #expect(!coordinator.isWriting)
    }

    @Test func generatesContentAndCommitsAtQueueHead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = DelayedHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        var committed: [String] = []

        let first = Task {
            try await coordinator.perform(
                makeContent: {
                    HostsWriteRequest(content: "127.0.0.1 localhost\n10.0.0.1 first.local\n")
                },
                commit: { committed.append($0.content) }
            )
        }
        while !access.started {
            await Task.yield()
        }
        let second = Task {
            try await coordinator.perform(
                makeContent: {
                    // Must observe the first operation's commit when it runs.
                    HostsWriteRequest(content: "127.0.0.1 localhost\n10.0.0.2 \(committed.count).local\n")
                },
                commit: { committed.append($0.content) }
            )
        }

        _ = try await first.value
        _ = try await second.value
        #expect(committed.count == 2)
        #expect(committed[1].contains("10.0.0.2 1.local"))
    }

    @Test func reportsCommitFailureAfterFileWasWritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let content = "127.0.0.1 localhost\n10.0.0.9 commit.local\n"

        do {
            _ = try await coordinator.perform(
                makeContent: { HostsWriteRequest(content: content) },
                commit: { _ in throw CommitTestError() }
            )
            Issue.record("Expected a commit error")
        } catch let error as HostsWriteCommitError {
            #expect(error.result.content == content)
            #expect(access.content == content)
            #expect(!coordinator.isWriting)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func blocksQueueUntilCommitFailureIsReconciled() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let first = "127.0.0.1 localhost\n10.0.0.1 first.local\n"
        let second = "127.0.0.1 localhost\n10.0.0.2 second.local\n"

        do {
            _ = try await coordinator.perform(
                makeContent: { HostsWriteRequest(content: first) },
                commit: { _ in throw CommitTestError() }
            )
            Issue.record("Expected the first commit to fail")
        } catch is HostsWriteCommitError {
            // Expected: the file is written, but the state transaction failed.
        }

        do {
            _ = try await coordinator.perform(
                makeContent: { HostsWriteRequest(content: second) },
                commit: { _ in }
            )
            Issue.record("Expected writes to stay blocked after a failed state commit")
        } catch is HostsReconciliationRequiredError {
            // Expected: the file and the saved model are temporarily divergent.
        }
        #expect(access.content == first)

        coordinator.reconcile(currentContent: first)
        let result = try await coordinator.perform(
            makeContent: { HostsWriteRequest(content: second) },
            commit: { _ in }
        )
        #expect(result.content == second)
        #expect(access.content == second)
        #expect(!coordinator.isWriting)
    }

    @Test func continuesQueueAfterContentGenerationFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let content = "127.0.0.1 localhost\n10.0.0.3 recovered.local\n"

        do {
            _ = try await coordinator.perform(
                makeContent: { throw CommitTestError() },
                commit: { _ in }
            )
            Issue.record("Expected content generation to fail")
        } catch is CommitTestError {
            // Expected.
        }

        let result = try await coordinator.perform(
            makeContent: { HostsWriteRequest(content: content) },
            commit: { _ in }
        )
        #expect(result.content == content)
        #expect(access.content == content)
        #expect(!coordinator.isWriting)
    }

    @Test func rejectsWriteWhenFingerprintChangedBeforeQueueHead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let firstContent = "127.0.0.1 localhost\n10.0.0.1 first.local\n"
        _ = try await coordinator.write(
            firstContent,
            expectedCurrentFingerprint: HostsReconciliation.canonical(access.content)
        )

        // Simulate an external tool changing the file after the caller captured
        // the fingerprint. Queue head validation must reject the queued write.
        let staleFingerprint = HostsReconciliation.canonical(
            firstContent
        )
        access.content = "127.0.0.1 localhost\n10.0.0.9 external.local\n"
        #expect(staleFingerprint != HostsReconciliation.canonical(access.content))
        do {
            _ = try await coordinator.perform(
                makeContent: {
                    HostsWriteRequest(
                        content: "127.0.0.1 localhost\n10.0.0.2 second.local\n",
                        expectedCurrentFingerprint: staleFingerprint
                    )
                },
                commit: { _ in }
            )
            Issue.record("Expected a reconciliation error")
        } catch is HostsReconciliationRequiredError {
            // Expected.
        }

        #expect(!access.content.contains("second.local"))
    }

    @Test func acceptsFingerprintFromEarlierInternalWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let firstContent = "127.0.0.1 localhost\n10.0.0.1 first.local\n"
        let secondContent = "127.0.0.1 localhost\n10.0.0.2 second.local\n"
        let staleFingerprint = HostsReconciliation.canonical(access.content)

        _ = try await coordinator.write(
            firstContent,
            expectedCurrentFingerprint: HostsReconciliation.canonical(access.content)
        )
        let result = try await coordinator.perform(
            makeContent: {
                HostsWriteRequest(
                    content: secondContent,
                    expectedCurrentFingerprint: staleFingerprint
                )
            },
            commit: { _ in }
        )

        #expect(result.content == secondContent)
        #expect(access.content == secondContent)
    }

    @Test func keepsBlockingUntilExternalContentIsReconciled() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let access = InMemoryHostsAccess(content: "127.0.0.1 localhost\n")
        let coordinator = HostsWriteCoordinator(access: access, backupDirectory: directory)
        let initial = HostsReconciliation.canonical(access.content)
        access.content = "127.0.0.1 localhost\n10.0.0.9 external.local\n"
        let external = access.content

        do {
            _ = try await coordinator.write(
                "127.0.0.1 localhost\n10.0.0.2 blocked.local\n",
                expectedCurrentFingerprint: initial
            )
            Issue.record("Expected the external edit to be rejected")
        } catch is HostsReconciliationRequiredError {
            // Expected.
        }

        do {
            _ = try await coordinator.write(
                "127.0.0.1 localhost\n10.0.0.3 still-blocked.local\n",
                expectedCurrentFingerprint: HostsReconciliation.canonical(external)
            )
            Issue.record("Expected the external edit to stay blocked")
        } catch is HostsReconciliationRequiredError {
            // Expected.
        }

        coordinator.reconcile(currentContent: external)
        let result = try await coordinator.write(
            "127.0.0.1 localhost\n10.0.0.4 resolved.local\n",
            expectedCurrentFingerprint: HostsReconciliation.canonical(external)
        )
        #expect(result.content.contains("resolved.local"))
    }
}

private struct CommitTestError: Error {}

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
    private(set) var writeCount = 0

    init(content: String) {
        self.content = content
    }

    func read() throws -> String {
        content
    }

    func write(_ content: String) async throws {
        started = true
        writeCount += 1
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

    @Test func seededProfileTracksLastActivation() throws {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)

        let profiles = try controller.container.viewContext.fetch(Profile.fetchRequest())
        guard let custom = profiles.first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile to exist")
            return
        }
        #expect(custom.isActive)
        #expect(custom.lastActivatedAt != nil)
    }

    @Test func activeProfilesGetActivationTimestampBackfilled() throws {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)

        let profiles = try controller.container.viewContext.fetch(Profile.fetchRequest())
        guard let custom = profiles.first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile to exist")
            return
        }
        custom.lastActivatedAt = nil
        try controller.container.viewContext.save()
        try controller.ensureDefaults()
        #expect(custom.lastActivatedAt != nil)
    }

    @Test func ensureDefaultsSyncsToggleWithAppliedState() throws {
        // 开关（isEnabled）表示“已写入系统”，必须与 isActive 一致：
        // 旧数据里新建/导入出来的配置是 isEnabled = true 但从未写入。
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)

        let context = controller.container.viewContext
        let profiles = try context.fetch(Profile.fetchRequest())
        guard let custom = profiles.first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile to exist")
            return
        }
        custom.isActive = false
        custom.isEnabled = true
        try context.save()

        try controller.ensureDefaults()

        #expect(custom.isEnabled == false)
        #expect(custom.isEnabled == custom.isActive)
    }

    @Test func seededDefaultEntriesAreDisabled() throws {
        // The default entries are only created when the real /etc/hosts has no
        // user entries, so only assert the invariant when they are present.
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)

        let profiles = try controller.container.viewContext.fetch(Profile.fetchRequest())
        guard let profile = profiles.first(where: { !$0.isSystem }) else {
            Issue.record("Expected a custom profile to exist")
            return
        }

        let entries = profile.sortedEntries
        let defaultHostnames = ["api.dev.local", "mysql.db.local"]
        let defaults = entries.filter { entry in
            entry.hostList.contains { defaultHostnames.contains($0) }
        }
        guard !defaults.isEmpty else { return }

        #expect(defaults.count == 2)
        #expect(defaults.allSatisfy { !$0.isEnabled })
    }

    @Test func builtInProfileNamesUseLocalizedDisplay() throws {
        let controller = PersistenceController(inMemory: true)
        #expect(controller.loadError == nil)

        let profiles = try controller.container.viewContext.fetch(Profile.fetchRequest())
        let system = profiles.first(where: \.isSystem)
        let custom = profiles.first(where: { !$0.isSystem })
        #expect(system?.localizedName(isEnglish: true) == "System")
        #expect(system?.localizedName(isEnglish: false) == "系统")
        #expect(custom?.localizedName(isEnglish: true) == "Default")
        #expect(custom?.localizedName(isEnglish: false) == "默认")
    }

    @Test func seedDescriptionsLocalize() {
        #expect(localizedSeedDescription("Local API service", isEnglish: false) == "本地 API 服务")
        #expect(localizedSeedDescription("本地 API 服务", isEnglish: true) == "Local API service")
        #expect(localizedSeedDescription("Development database", isEnglish: false) == "开发数据库")
        #expect(localizedSeedDescription("开发数据库", isEnglish: true) == "Development database")
        #expect(localizedSeedDescription("custom description", isEnglish: true) == "custom description")
    }

    @Test func backupNotesLocalize() {
        #expect(localizedBackupNote("启用配置前自动备份", isEnglish: true) == "Auto backup before enabling profile")
        #expect(localizedBackupNote("Auto backup before enabling profile", isEnglish: false) == "启用配置前自动备份")
        #expect(localizedBackupNote("应用“默认”前自动备份", isEnglish: true) == "Auto backup before applying “Default”")
        #expect(localizedBackupNote("Auto backup before applying “Default”", isEnglish: false) == "应用“默认”前自动备份")
        #expect(localizedBackupNote("导入 2026-10-24 1000", isEnglish: true) == "Imported 2026-10-24 1000")
        #expect(localizedBackupNote("Imported 2026-10-24 1000", isEnglish: false) == "导入 2026-10-24 1000")
    }

    @Test func generatedProfileNamesLocalize() {
        #expect(localizedProfileName("新配置", isEnglish: true) == "New Profile")
        #expect(localizedProfileName("New Profile", isEnglish: false) == "新配置")
        #expect(localizedProfileName("默认 副本", isEnglish: true) == "Default Copy")
        #expect(localizedProfileName("Default Copy", isEnglish: false) == "默认 副本")
        #expect(localizedProfileName("导入 2026-10-24 1000", isEnglish: true) == "Imported 2026-10-24 1000")
        #expect(localizedProfileName("Imported 2026-10-24 1000", isEnglish: false) == "导入 2026-10-24 1000")
        #expect(localizedProfileName("从备份恢复 2026-10-24", isEnglish: true) == "Restored from backup 2026-10-24")
        #expect(localizedProfileName("Restored from backup 2026-10-24", isEnglish: false) == "从备份恢复 2026-10-24")
    }
}

struct LocalizationPreferenceTests {
    @Test func appleLanguagesFollowLanguagePreference() {
        let defaults = UserDefaults.standard
        let previous = defaults.array(forKey: "AppleLanguages") as? [String]
        defer {
            if let previous {
                defaults.set(previous, forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }

        LocalizationPreference.applyAppleLanguages(for: "zh")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["zh-Hans"])

        LocalizationPreference.applyAppleLanguages(for: "en")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])

        LocalizationPreference.applyAppleLanguages(for: "system")
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == previous)
    }
}

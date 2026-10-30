import CoreData
import Testing
@testable import hosts_manager

@MainActor
struct ApplyPlanBuilderTests {
    @Test func hostnameConflictBlocksApply() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let target = try makeProfile(
            in: context,
            name: "Target",
            ip: "10.0.0.1",
            hostname: "shared.local"
        )
        let active = try makeProfile(
            in: context,
            name: "Active",
            ip: "10.0.0.2",
            hostname: "shared.local",
            isApplied: true
        )

        let plan = ApplyPlanBuilder.makePlan(
            profile: target,
            allProfiles: [target, active],
            draftText: nil,
            managedHostnamesBaseline: [],
            liveContent: "127.0.0.1 localhost\n",
            removeDuplicates: false,
            isEnglish: true
        )

        #expect(!plan.canApply)
        #expect(plan.conflictIssues.count == 1)
        #expect(plan.conflictIssues.first?.hostname == "shared.local")
    }

    @Test func exactDuplicatesAreReportedAndCanBeRemoved() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let target = try makeProfile(
            in: context,
            name: "Target",
            ip: "10.0.0.1",
            hostname: "duplicate.local"
        )
        let active = try makeProfile(
            in: context,
            name: "Active",
            ip: "10.0.0.1",
            hostname: "duplicate.local",
            isApplied: true
        )

        let keepDuplicates = ApplyPlanBuilder.makePlan(
            profile: target,
            allProfiles: [target, active],
            draftText: nil,
            managedHostnamesBaseline: [],
            liveContent: "127.0.0.1 localhost\n",
            removeDuplicates: false,
            isEnglish: true
        )
        #expect(keepDuplicates.hasExactDuplicatesInTargets)
        #expect(keepDuplicates.exactDuplicateObjectIDs.count == 1)
        #expect(keepDuplicates.duplicateIssues.count == 1)

        let removeDuplicates = ApplyPlanBuilder.makePlan(
            profile: target,
            allProfiles: [target, active],
            draftText: nil,
            managedHostnamesBaseline: [],
            liveContent: "127.0.0.1 localhost\n",
            removeDuplicates: true,
            isEnglish: true
        )
        #expect(removeDuplicates.duplicateIssues.isEmpty)
        #expect(!removeDuplicates.hasExactDuplicatesInTargets)
        #expect(
            HostsParser.parse(removeDuplicates.targetContent)
                .filter { $0.hostnames.contains("duplicate.local") }
                .count == 1
        )
    }

    @Test func draftOverridesStoredEntriesAndRetainsExternalContent() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let profile = try makeProfile(
            in: context,
            name: "Draft",
            ip: "10.0.0.1",
            hostname: "old.local"
        )
        let draft = "10.0.0.2 new.local\n"
        let live = """
        127.0.0.1 localhost
        10.0.0.9 external.local
        10.0.0.1 old.local
        """

        let plan = ApplyPlanBuilder.makePlan(
            profile: profile,
            allProfiles: [profile],
            draftText: draft,
            managedHostnamesBaseline: [],
            liveContent: live,
            removeDuplicates: false,
            isEnglish: true
        )
        let canonical = HostsReconciliation.canonical(plan.targetContent)

        #expect(plan.canApply)
        #expect(canonical.contains("10.0.0.2|new.local"))
        #expect(!canonical.contains("old.local"))
        #expect(canonical.contains("10.0.0.9|external.local"))
    }

    @Test func externalEntriesRemainWhenOnlyOwnedRowsAreReplaced() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let profile = try makeProfile(
            in: context,
            name: "Managed",
            ip: "10.0.0.3",
            hostname: "managed.local"
        )
        let live = """
        10.0.0.8 external.local # external comment
        10.0.0.7 old-managed.local
        """

        let plan = ApplyPlanBuilder.makePlan(
            profile: profile,
            allProfiles: [profile],
            draftText: nil,
            managedHostnamesBaseline: ["old-managed.local"],
            liveContent: live,
            removeDuplicates: false,
            isEnglish: true
        )
        let canonical = HostsReconciliation.canonical(plan.targetContent)

        #expect(canonical.contains("10.0.0.8|external.local"))
        #expect(canonical.contains("10.0.0.3|managed.local"))
        #expect(!canonical.contains("old-managed.local"))
        #expect(plan.targetContent.contains("# external comment"))
    }

    private func makeProfile(
        in context: NSManagedObjectContext,
        name: String,
        ip: String,
        hostname: String,
        isApplied: Bool = false
    ) throws -> Profile {
        let repository = ProfileRepository(context: context)
        let profile = repository.create(
            name: name,
            entries: [
                ParsedHostEntry(
                    ip: ip,
                    hostnames: [hostname],
                    isEnabled: true
                )
            ]
        )
        profile.setApplied(isApplied)
        try context.obtainPermanentIDs(for: [profile])
        return profile
    }
}

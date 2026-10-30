import CoreData
import Foundation

@MainActor
struct ApplyPlan {
    let targetContent: String
    let validationIssues: [HostIssue]
    let conflictIssues: [HostIssue]
    let duplicateIssues: [HostIssue]
    let hasExactDuplicatesInTargets: Bool
    let exactDuplicateObjectIDs: Set<NSManagedObjectID>
    let managedHostnames: Set<String>
    let appliedProfileIDs: [UUID]

    var canApply: Bool {
        conflictIssues.isEmpty
    }
}

@MainActor
enum ApplyPlanBuilder {
    static func makePlan(
        profile: Profile,
        allProfiles: [Profile],
        draftText: String?,
        managedHostnamesBaseline: Set<String>,
        liveContent: String,
        removeDuplicates: Bool,
        isEnglish: Bool
    ) -> ApplyPlan {
        let targets = allProfiles.filter {
            $0.isAppliedForSystem && $0.objectID != profile.objectID && !$0.isDeleted
        } + [profile]
        return makePlan(
            targets: targets,
            profile: profile,
            allProfiles: allProfiles,
            draftText: draftText,
            managedHostnamesBaseline: managedHostnamesBaseline,
            liveContent: liveContent,
            removeDuplicates: removeDuplicates,
            forcedDuplicateObjectIDs: nil,
            isEnglish: isEnglish
        )
    }

    /// Queue-head validation can reuse the duplicate set captured by the user's
    /// preview, so a background edit cannot silently change what was approved.
    static func makePlan(
        targets: [Profile],
        profile: Profile,
        allProfiles: [Profile],
        draftText: String?,
        managedHostnamesBaseline: Set<String>,
        liveContent: String,
        removeDuplicates: Bool,
        forcedDuplicateObjectIDs: Set<NSManagedObjectID>?,
        isEnglish: Bool
    ) -> ApplyPlan {
        let calculatedDuplicateIDs = exactDuplicateObjectIDs(in: targets)
        let duplicateObjectIDs = removeDuplicates
            ? forcedDuplicateObjectIDs ?? calculatedDuplicateIDs
            : []
        let draftEntries = draftText.map(HostsParser.parse)
        let entries = targets.flatMap { target -> [ParsedHostEntry] in
            if target.objectID == profile.objectID, let draftEntries {
                return draftEntries
            }
            return target.sortedEntries.compactMap { entry in
                guard !duplicateObjectIDs.contains(entry.objectID) else {
                    return nil
                }
                return ParsedHostEntry(
                    ip: entry.ip ?? "",
                    hostnames: entry.hostList,
                    desc: localizedSeedDescription(entry.desc, isEnglish: isEnglish),
                    isEnabled: entry.isEnabled,
                    isSystem: entry.isSystem
                )
            }
        }

        let issues = HostValidator.issues(entries: entries.filter(\.isEnabled))
        let ownedHostnames = Set(
            allProfiles
                .filter { !$0.isSystem }
                .flatMap(\.sortedEntries)
                .flatMap(\.hostList)
                .map { $0.lowercased() }
        ).union(managedHostnamesBaseline)
        let targetHostnames = draftEntries?.flatMap(\.hostnames)
            ?? profile.sortedEntries.flatMap(\.hostList)
        let otherHostnames = allProfiles
            .filter {
                !$0.isSystem && $0.objectID != profile.objectID
            }
            .flatMap(\.sortedEntries)
            .flatMap(\.hostList)

        return ApplyPlan(
            targetContent: HostsContentMerger.merge(
                liveContent: liveContent,
                managedEntries: entries,
                ownedHostnames: ownedHostnames
            ),
            validationIssues: issues,
            conflictIssues: issues.filter { $0.kind == .conflict },
            duplicateIssues: issues.filter { $0.kind == .duplicate },
            hasExactDuplicatesInTargets: !removeDuplicates
                && !calculatedDuplicateIDs.isEmpty,
            exactDuplicateObjectIDs: calculatedDuplicateIDs,
            managedHostnames: Set(
                (otherHostnames + targetHostnames).map { $0.lowercased() }
            ),
            appliedProfileIDs: targets.compactMap(\.id)
        )
    }

    static func exactDuplicateObjectIDs(
        in profiles: [Profile]
    ) -> Set<NSManagedObjectID> {
        var seen = Set<String>()
        var duplicates = Set<NSManagedObjectID>()
        for entry in profiles.flatMap(\.sortedEntries) {
            let key = (entry.ip ?? "") + "|" + entry.hostList.joined(separator: ",")
            if !seen.insert(key).inserted {
                duplicates.insert(entry.objectID)
            }
        }
        return duplicates
    }
}

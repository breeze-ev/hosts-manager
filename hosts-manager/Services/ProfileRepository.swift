import CoreData
import Foundation

@MainActor
struct ProfileRepository {
    let context: NSManagedObjectContext

    func create(
        name: String,
        entries: [ParsedHostEntry] = []
    ) -> Profile {
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = name
        profile.setApplied(false)
        profile.createdAt = Date()
        profile.updatedAt = Date()
        add(entries, to: profile)
        return profile
    }

    func delete(_ profile: Profile) {
        context.delete(profile)
    }

    func replaceEntries(
        of profile: Profile,
        with entries: [ParsedHostEntry]
    ) {
        for entry in profile.sortedEntries {
            context.delete(entry)
        }
        add(entries, to: profile)
        profile.updatedAt = Date()
    }

    func add(
        _ entries: [ParsedHostEntry],
        to profile: Profile
    ) {
        for (index, item) in entries.enumerated() {
            let entry = HostEntry(context: context)
            entry.id = UUID()
            entry.profile = profile
            entry.ip = item.ip
            entry.hostnames = item.hostnames
            entry.desc = item.desc
            entry.isEnabled = item.isEnabled
            entry.isSystem = item.isSystem
            entry.sortIndex = Int64(index)
            entry.createdAt = Date()
        }
    }
}

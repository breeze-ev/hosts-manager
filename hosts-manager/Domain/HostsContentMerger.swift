import Foundation

/// Combines profile-managed entries with valid entries from the live system
/// file. Profile hostnames always win; unowned entries are retained as an
/// external layer and are never imported into Core Data.
nonisolated enum HostsContentMerger {
    static func merge(
        liveContent: String,
        managedEntries: [ParsedHostEntry],
        ownedHostnames: Set<String>
    ) -> String {
        let reserved = Set(
            ownedHostnames.map { $0.lowercased() }
                + HostsParser.systemNames.map { $0.lowercased() }
        )
        let external = HostsParser.parse(liveContent).compactMap { entry -> ParsedHostEntry? in
            let externalHostnames = entry.hostnames.filter {
                !reserved.contains($0.lowercased())
            }
            guard !externalHostnames.isEmpty else { return nil }
            var result = entry
            result.hostnames = externalHostnames
            return result
        }
        return HostsParser.mergedContent(
            entries: managedEntries,
            externalEntries: external
        )
    }
}

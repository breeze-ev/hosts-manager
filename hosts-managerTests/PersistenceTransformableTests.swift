import CoreData
import Foundation
import Testing
@testable import hosts_manager

@MainActor
struct PersistenceTransformableTests {
    @Test func hostnamesUseRuntimeVisibleValueClass() throws {
        let entity = try #require(
            PersistenceController.model.entitiesByName["HostEntry"]
        )
        let attribute = try #require(entity.attributesByName["hostnames"])

        #expect(attribute.attributeValueClassName == "NSArray")
    }

    @Test func hostnamesRoundTripThroughPersistentStore() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = "Transformable Test"
        profile.createdAt = Date()
        profile.updatedAt = Date()

        let entry = HostEntry(context: context)
        entry.id = UUID()
        entry.profile = profile
        entry.ip = "127.0.0.1"
        entry.hostnames = ["one.local", "two.local"]
        entry.desc = "test"
        entry.createdAt = Date()
        let entryID = try #require(entry.id)
        try context.save()

        context.reset()
        let request = HostEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", entryID as CVarArg)
        let fetched = try #require(try context.fetch(request).first)
        #expect(fetched.hostnames == ["one.local", "two.local"])
    }
}

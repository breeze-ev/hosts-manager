import CoreData
import Foundation
import SwiftUI
import Testing
@testable import hosts_manager

@MainActor
struct SourceDraftTests {
    @Test func trailingNewlineStaysInEditorBuffer() throws {
        let (model, profile) = try makeModelWithProfile()
        let binding = model.sourceBinding(for: profile)
        let original = binding.wrappedValue

        binding.wrappedValue = original + "\n"

        #expect(binding.wrappedValue == original + "\n")
        #expect(model.sourceText(for: profile) == original + "\n")
    }

    @Test func restoringGeneratedTextClearsDraft() throws {
        let (model, profile) = try makeModelWithProfile()
        let profileID = try #require(profile.id)
        let binding = model.sourceBinding(for: profile)
        let original = binding.wrappedValue

        binding.wrappedValue = original + "\n"
        binding.wrappedValue = original

        #expect(model.sourceDrafts[profileID] == nil)
        #expect(binding.wrappedValue == original)
    }

    private func makeModelWithProfile() throws -> (HostsWorkspaceModel, Profile) {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let profile = Profile(context: context)
        profile.id = UUID()
        profile.name = "测试配置"
        profile.isSystem = false
        profile.setApplied(false)
        profile.createdAt = Date()
        profile.updatedAt = Date()

        let entry = HostEntry(context: context)
        entry.id = UUID()
        entry.profile = profile
        entry.ip = "127.0.0.1"
        entry.hostnames = ["api.ze.local"]
        entry.desc = "app接口"
        entry.isEnabled = true
        entry.isSystem = false
        entry.sortIndex = 0
        entry.createdAt = Date()
        try context.save()

        let model = HostsWorkspaceModel(
            context: context,
            localization: Localization()
        )
        return (model, profile)
    }
}

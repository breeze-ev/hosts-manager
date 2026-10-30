import SwiftUI
import CoreData

// MARK: - Navigation sidebar

struct NavigationSidebarView: View {
    let profiles: FetchedResults<Profile>
    @Binding var selection: SidebarItem
    let selectedProfileID: UUID?
    @Binding var pendingScrollProfileID: UUID?
    let onCreate: () -> Void
    let onSelect: (Profile) -> Void
    let onEnable: (Profile) -> Void
    let onDisable: (Profile) -> Void
    let onDelete: (Profile) -> Void
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(profiles) { profile in
                    #if DEBUG
                    if PreviewEnvironment.isRunning {
                        // Xcode macOS Preview crashes when ForEach directly
                        // returns a custom row from within List.
                        AnyView(EmptyView())
                    }
                    #endif
                    ProfileSidebarRow(
                        profile: profile,
                        isSelected: selection == .profiles && selectedProfileID == profile.id,
                        onSelect: { onSelect(profile) },
                        onEnableActive: { onEnable(profile) },
                        onDisableActive: { onDisable(profile) },
                        onDelete: { onDelete(profile) }
                    )
                    .id(profile.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(l10n.s("配置", "Profiles"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onCreate()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("create-profile-button")
                    .accessibilityLabel(l10n.s("新建配置", "New Profile"))
                    .help(l10n.s("新建配置", "New Profile"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
            .safeAreaBar(edge: .bottom, alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        selection = .backups
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18))
                            .foregroundStyle(selection == .backups ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selection == .backups ? Color.accentColor.opacity(0.18) : .clear)
                            )
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.s("备份", "Backups"))

                    Button {
                        selection = .settings
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(selection == .settings ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selection == .settings ? Color.accentColor.opacity(0.18) : .clear)
                            )
                    }
                    .buttonStyle(.borderless)
                    .help(l10n.s("设置", "Settings"))
                    .accessibilityLabel(l10n.s("设置", "Settings"))
                    .accessibilityIdentifier("sidebar-settings-button")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .onChange(of: profiles.map(\.id)) { _, newIDs in
                if let targetID = pendingScrollProfileID, newIDs.contains(targetID) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(targetID, anchor: .top)
                        }
                        pendingScrollProfileID = nil
                    }
                }
            }
        }
    }
}

private struct NavigationSidebarPreview: View {
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \Profile.isSystem, ascending: false),
        NSSortDescriptor(keyPath: \Profile.createdAt, ascending: true)
    ])
    private var profiles: FetchedResults<Profile>
    @State private var selection: SidebarItem = .profiles
    @State private var pendingScrollProfileID: UUID?

    var body: some View {
        NavigationSidebarView(
            profiles: profiles,
            selection: $selection,
            selectedProfileID: profiles.first(where: { !$0.isSystem })?.id,
            pendingScrollProfileID: $pendingScrollProfileID,
            onCreate: {},
            onSelect: { _ in },
            onEnable: { _ in },
            onDisable: { _ in },
            onDelete: { _ in }
        )
        .frame(width: 280, height: 620)
    }
}

#Preview("Navigation Sidebar") {
    NavigationSidebarPreview()
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
}

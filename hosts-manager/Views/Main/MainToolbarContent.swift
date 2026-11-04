import SwiftUI

struct MainToolbarContent: ToolbarContent {
    let selection: SidebarItem
    let title: String
    let query: Binding<String>
    let mode: Binding<EntryMode>
    let selectedProfile: Profile?
    let l10n: Localization
    let onImport: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .accessibilityIdentifier("detail-toolbar-title")

                if selection == .profiles, let selectedProfile {
                    ProfileStatusBadge(profile: selectedProfile)
                        .fixedSize()
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minWidth: ToolbarTitleLayout.minimumWidth, alignment: .leading)
        }
        .sharedBackgroundVisibility(.hidden)

        // primaryAction only describes intent; an explicit flexible item keeps
        // the actions in the trailing cluster on macOS.
        ToolbarItem {
            Spacer()
        }

        if selection == .profiles {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(l10n.s("搜索", "Search"), text: query)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("toolbar-search-field")
                }
                .padding(.leading, 10)
                .frame(width: 190, alignment: .leading)

                Picker("", selection: mode) {
                    Label(l10n.s("列表", "List"), systemImage: "list.bullet").tag(EntryMode.list)
                    Label(l10n.s("编辑", "Edit"), systemImage: "pencil").tag(EntryMode.source)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Menu {
                    Button(l10n.s("从文件导入配置…", "Import Profile from File…"), systemImage: "doc.badge.plus") {
                        onImport()
                    }
                    Button(l10n.s("复制当前配置", "Duplicate Profile"), systemImage: "doc.on.doc") {
                        onDuplicate()
                    }
                    Button(l10n.s("导出当前配置", "Export Profile"), systemImage: "square.and.arrow.up") {
                        onExport()
                    }
                    .disabled(selectedProfile?.isSystem != false)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(l10n.s("导入、复制或导出配置", "Import, duplicate, or export profile"))
            }
        }
    }
}

private enum ToolbarTitleLayout {
    // macOS centers narrow navigation items; a stable width keeps titles
    // aligned when a page has no status badge.
    static let minimumWidth: CGFloat = 240
}

import SwiftUI

struct MainToolbarContent: ToolbarContent {
    let selection: SidebarItem
    let query: Binding<String>
    let mode: Binding<EntryMode>
    let selectedProfile: Profile?
    let l10n: Localization
    let onImport: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if selection == .profiles {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(l10n.s("搜索", "Search"), text: query)
                        .textFieldStyle(.plain)
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

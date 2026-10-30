import SwiftUI
import CoreData

struct ProfileSidebarRow: View {
    @ObservedObject var profile: Profile
    let isSelected: Bool
    let onSelect: () -> Void
    let onEnableActive: () -> Void
    let onDisableActive: () -> Void
    let onDelete: () -> Void
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization
    @State private var showDeleteConfirm = false
    @State private var showDisableConfirm = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var renameError: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isRenaming {
                ProfileAvatar(profile: profile)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($isNameFocused)
                        .onSubmit(saveRename)
                        .onExitCommand(perform: cancelRename)
                    if let renameError {
                        Text(renameError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    cancelRename()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(l10n.s("取消", "Cancel"))

                Button {
                    saveRename()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(l10n.s("保存", "Save"))
            } else {
                Button {
                    onSelect()
                } label: {
                    ProfileRow(profile: profile, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile-row-\(profile.name ?? "")")

                if !profile.isSystem {
                    Toggle("", isOn: Binding(
                        get: { profile.isAppliedForSystem },
                        set: { newValue in
                            if newValue {
                                guard !profile.isAppliedForSystem else { return }
                                onEnableActive()
                            } else if profile.isAppliedForSystem {
                                showDisableConfirm = true
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .help(l10n.s("启用并写入系统，停用则移除", "Enable and write to system, disable removes it"))
                    .popover(isPresented: $showDisableConfirm, arrowEdge: .bottom) {
                        ConfirmPopover(
                            title: l10n.s("停用当前配置？", "Disable the active profile?"),
                            message: l10n.s(
                                "当前配置管理的条目会从 /etc/hosts 中移除；外部添加的有效条目会保留。操作前会自动备份。",
                                "Entries managed by this profile will be removed from /etc/hosts; valid external entries are kept. A backup is created first."
                            ),
                            cancelTitle: l10n.s("取消", "Cancel"),
                            confirmTitle: l10n.s("停用并移除配置条目", "Disable and remove managed entries"),
                            onCancel: { showDisableConfirm = false },
                            onConfirm: {
                                showDisableConfirm = false
                                onDisableActive()
                            }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(isRenaming || profile.isSystem || profile.isAppliedForSystem ? 1 : 0.45)
        .contextMenu {
            if !profile.isSystem {
                Button(l10n.s("重命名", "Rename")) {
                    beginRename()
                }
                Button(l10n.s("删除配置", "Delete Profile"), role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .popover(isPresented: $showDeleteConfirm, arrowEdge: .trailing) {
            ConfirmPopover(
                title: l10n.s("删除此配置？", "Delete this profile?"),
                message: l10n.s("此操作无法撤销。", "This action cannot be undone."),
                cancelTitle: l10n.s("取消", "Cancel"),
                confirmTitle: l10n.s("删除", "Delete"),
                onCancel: { showDeleteConfirm = false },
                onConfirm: {
                    showDeleteConfirm = false
                    onDelete()
                }
            )
        }
    }

    private func beginRename() {
        draftName = profile.localizedName(isEnglish: l10n.isEnglish)
        renameError = nil
        isRenaming = true
        isNameFocused = true
    }

    private func cancelRename() {
        isRenaming = false
        isNameFocused = false
        renameError = nil
    }

    private func saveRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            renameError = l10n.s("配置名称不能为空。", "The profile name cannot be empty.")
            return
        }
        profile.name = trimmed
        profile.updatedAt = Date()
        do {
            try context.save()
            cancelRename()
        } catch {
            context.rollback()
            renameError = error.localizedDescription
        }
    }
}

#Preview("Profile Sidebar Row") {
    ProfileSidebarRow(
        profile: PreviewFixtures.userProfile,
        isSelected: true,
        onSelect: {},
        onEnableActive: {},
        onDisableActive: {},
        onDelete: {}
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .padding(10)
    .frame(width: 280)
}

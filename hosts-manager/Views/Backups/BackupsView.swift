import SwiftUI
import CoreData
import AppKit

// MARK: - Backups

struct BackupsView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BackupRecord.timestamp, ascending: false)])
    private var backups: FetchedResults<BackupRecord>
    @EnvironmentObject private var l10n: Localization
    @Environment(\.managedObjectContext) private var context
    @State private var previewBackup: BackupRecord?
    @State private var restoreBackup: BackupRecord?
    @State private var restoreMessage: String?
    @StateObject private var writeCoordinator = HostsWriteCoordinator.shared
    let isTitleBarCollapsed: Bool
    let onTitleBarScrollOffsetChange: (CGFloat) -> Void

    var body: some View {
        Group {
            if backups.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    if !isTitleBarCollapsed {
                        header
                    }
                    ContentUnavailableView(l10n.s("暂无备份", "No backups"), systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List {
                    ForEach(Array(backups.enumerated()), id: \.element.id) { index, backup in
                        #if DEBUG
                        if PreviewEnvironment.isRunning {
                            AnyView(EmptyView())
                        }
                        #endif
                        BackupRow(
                            backup: backup,
                            onView: { previewBackup = backup },
                            onDelete: { delete(backup) }
                        )
                        .zebraRowBackground(index)
                    }
                }
                .listStyle(.inset)
                .detailListSafeAreaHeader(isCollapsed: isTitleBarCollapsed) {
                    header
                }
                .background(.clear)
                .detailHeaderScrollTracking { offset in
                    onTitleBarScrollOffsetChange(offset)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .sheet(item: $previewBackup) { backup in
            BackupPreviewSheet(backup: backup) {
                previewBackup = nil
                restoreBackup = backup
            }
        }
        .onAppear {
            onTitleBarScrollOffsetChange(0)
            guard !PreviewEnvironment.isRunning else {
                return
            }
            do {
                try BackupMaintenance.prune(context: context)
            } catch {
                context.rollback()
                restoreMessage = error.localizedDescription
            }
        }
        .confirmationDialog(l10n.s("还原此备份？", "Restore this backup?"), isPresented: restoreBinding, titleVisibility: .visible) {
            Button(l10n.s("覆盖 /etc/hosts 并停用所有配置", "Overwrite /etc/hosts and Disable All Profiles")) {
                restore(asNewProfile: false)
            }
            Button(l10n.s("恢复为新配置", "Restore as New Profile")) { restore(asNewProfile: true) }
            Button(l10n.s("取消", "Cancel"), role: .cancel) { restoreBackup = nil }
        } message: {
            Text(l10n.s(
                "将用备份内容覆盖 /etc/hosts，并关闭所有配置开关，避免下次编辑覆盖还原内容。覆盖前会先备份当前文件。",
                "The backup will overwrite /etc/hosts and turn off every profile switch so the next edit cannot overwrite the restored content. The current file is backed up first."
            ))
        }
        .alert(l10n.s("还原结果", "Restore Result"), isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var header: some View {
        DetailPageHeader(
            title: l10n.s("备份", "Backups"),
            subtitle: l10n.s(
                "每次写入前自动生成时间戳备份，可查看并还原。",
                "Timestamped backups are created before each write. View or restore anytime."
            )
        )
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { restoreBackup != nil }, set: { if !$0 { restoreBackup = nil } })
    }

    private func restore(asNewProfile: Bool) {
        guard let backup = restoreBackup, let path = backup.filePath,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            restoreMessage = l10n.s("备份文件不存在或无法读取。", "The backup file is missing or unreadable.")
            restoreBackup = nil
            return
        }
        restoreBackup = nil
        if asNewProfile {
            _ = ProfileRepository(context: context).create(
                name: l10n.s(
                    "从备份恢复 \(Date().formatted(date: .abbreviated, time: .shortened))",
                    "Restored \(Date().formatted(date: .abbreviated, time: .shortened))"
                ),
                entries: HostsParser.parse(content).filter { !$0.isSystem }
            )
            do {
                try context.save()
                restoreMessage = l10n.s("已恢复为新配置。", "Restored as a new profile.")
            } catch {
                context.rollback()
                restoreMessage = error.localizedDescription
            }
            return
        }
        Task {
            let coordinator = writeCoordinator
            do {
                _ = try await coordinator.perform(
                    makeContent: { _ in
                        // Restoring a backup is an explicit overwrite. Queue-head
                        // serialization still ensures it runs after any earlier
                        // committed operation.
                        HostsWriteRequest(
                            content: content,
                            appliedProfileIDs: [],
                            managedHostnames: []
                        )
                    },
                    commit: { result in
                        try commitHostsWrite(
                            result: result,
                            context: context,
                            profileName: nil,
                            note: l10n.s("还原备份前自动备份", "Auto backup before restore"),
                            appliedProfileIDs: []
                        ) {
                            // The file now represents the backup, not the old
                            // active-profile merge. Clear every cached applied
                            // flag so the next edit cannot silently overwrite
                            // the restored content.
                            try clearAppliedStateForUserProfiles(in: context)
                        }
                    }
                )
                await MainActor.run {
                    writeCoordinator.clearStateRecovery()
                    NotificationCenter.default.post(name: .hostsStateReconciled, object: nil)
                    restoreMessage = l10n.s(
                        "已还原备份。原已启用配置均已标记为未应用，需要时可重新打开对应开关。",
                        "Backup restored. Previously applied profiles are now marked unapplied; re-enable them when needed."
                    )
                }
            } catch {
                await MainActor.run {
                    if error is HostsStateRecoveryRequiredError {
                        restoreMessage = l10n.s(
                            "配置状态尚未恢复，写入已暂停。请先完成恢复操作。",
                            "Profile state recovery is pending and writes are paused. Complete recovery first."
                        )
                    } else if let commitError = error as? HostsWriteCommitError {
                        // The file already contains the backup and all previous
                        // profiles are intended to be unapplied. Pose the exact
                        // empty selection so recovery cannot reapply stale ids.
                        coordinator.requiresStateRecoveryAfterCommitFailure(
                            content: commitError.result.content,
                            appliedProfileIDs: [],
                            managedHostnames: []
                        )
                        restoreMessage = l10n.s(
                            "/etc/hosts 已还原，但配置开关状态未能清理。请选择“保留当前系统文件”完成恢复。\n\(commitError.underlying.localizedDescription)",
                            "/etc/hosts was restored, but the profile switches could not be cleared. Choose “Keep Current System File” to finish recovery.\n\(commitError.underlying.localizedDescription)"
                        )
                        NotificationCenter.default.post(name: .hostsStateReconciled, object: nil)
                    } else {
                        restoreMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func delete(_ backup: BackupRecord) {
        let path = backup.filePath
        context.delete(backup)
        do {
            try context.save()
        } catch {
            context.rollback()
            restoreMessage = error.localizedDescription
            return
        }
        if let path, FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                restoreMessage = l10n.s(
                    "备份记录已删除，但备份文件无法移除。",
                    "The backup record was deleted, but its file could not be removed."
                )
            }
        }
    }
}

#Preview("Backups") {
    let _ = PreviewFixtures.backup

    BackupsView(
        isTitleBarCollapsed: false,
        onTitleBarScrollOffsetChange: { _ in }
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .frame(width: 860, height: 620)
}

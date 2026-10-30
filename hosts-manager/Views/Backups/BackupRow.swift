import SwiftUI
import CoreData

struct BackupRow: View {
    @ObservedObject var backup: BackupRecord
    let onView: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var l10n: Localization
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text((backup.filePath as NSString?)?.lastPathComponent ?? "")
                    .font(.system(.body, design: .monospaced))
                Text(localizedBackupNote(backup.note, isEnglish: l10n.isEnglish))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            RowIconButton(systemName: "eye", help: l10n.s("查看", "View")) {
                onView()
            }

            RowIconButton(systemName: "trash", help: l10n.s("删除", "Delete")) {
                showDeleteConfirm = true
            }
            .popover(isPresented: $showDeleteConfirm, arrowEdge: .bottom) {
                ConfirmPopover(
                    title: l10n.s("删除此备份？", "Delete this backup?"),
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
        .listRowSeparator(.hidden)
    }
}

#Preview("Backup Row") {
    BackupRow(
        backup: PreviewFixtures.backup,
        onView: {},
        onDelete: {}
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .padding()
    .frame(width: 760)
}

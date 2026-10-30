import AppKit
import SwiftUI

struct StoreRecoveryView: View {
    @ObservedObject var persistenceController: PersistenceController
    @EnvironmentObject private var l10n: Localization
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 38))
                .foregroundStyle(.orange)

            Text(l10n.s("无法打开配置数据库", "Unable to Open Profile Store"))
                .font(.system(size: 22, weight: .bold))

            Text(persistenceController.loadError ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            HStack(spacing: 10) {
                Button(l10n.s("重试", "Retry")) {
                    persistenceController.retryLoad()
                }
                .buttonStyle(.glassProminent)

                Button(l10n.s("打开数据目录", "Open Data Folder")) {
                    NSWorkspace.shared.open(persistenceController.storeDirectoryURL)
                }
                .buttonStyle(.glass)

                Button(l10n.s("重置数据库…", "Reset Store…"), role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.glass)
            }
        }
        .padding(36)
        .frame(minWidth: 620, minHeight: 360)
        .buttonBorderShape(.capsule)
        .confirmationDialog(
            l10n.s("重置数据库？", "Reset the profile store?"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(l10n.s("删除并重建", "Delete and Recreate"), role: .destructive) {
                persistenceController.resetStore()
            }
            Button(l10n.s("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(l10n.s(
                "配置、备份记录和设置会被删除，但磁盘中的 hosts 备份文件不会被删除。",
                "Profiles, backup records, and settings will be deleted. Backup files on disk will remain."
            ))
        }
    }
}

#Preview("Store Recovery") {
    StoreRecoveryView(persistenceController: PersistenceController.preview)
        .environmentObject(Localization())
}

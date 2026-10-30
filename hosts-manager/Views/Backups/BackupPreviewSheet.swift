import SwiftUI
import CoreData

struct BackupPreviewSheet: View {
    let backup: BackupRecord
    let onRestore: () -> Void
    @EnvironmentObject private var l10n: Localization
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((backup.filePath as NSString?)?.lastPathComponent ?? "")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
            Divider()
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Spacer()
                Button(l10n.s("还原", "Restore"), systemImage: "arrow.uturn.backward") {
                    onRestore()
                }
                .buttonStyle(.glassProminent)
                .disabled(backup.filePath == nil)
                Button(l10n.s("关闭", "Close")) { dismiss() }.buttonStyle(.glass)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .buttonBorderShape(.capsule)
    }

    private var content: String {
        guard let path = backup.filePath else { return "" }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}

#Preview("Backup Preview Sheet") {
    BackupPreviewSheet(backup: PreviewFixtures.backup, onRestore: {})
        .environment(\.managedObjectContext, PreviewFixtures.context)
        .environmentObject(Localization())
}

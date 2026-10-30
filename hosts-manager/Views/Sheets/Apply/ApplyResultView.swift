import SwiftUI

struct ApplyResultView: View {
    let profileName: String
    let errorMessage: String?
    let baselineContent: String
    let targetContent: String
    let onDone: () -> Void
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                    Text(l10n.s("写入失败", "Write failed"))
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(errorMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                    Text(l10n.s(
                        "已应用“\(profileName)”到 /etc/hosts",
                        "Applied “\(profileName)” to /etc/hosts"
                    ))
                    .font(.system(size: 15, weight: .semibold))
                }
                Text(l10n.s(
                    "备份已保存到备份目录。",
                    "A backup was saved to the backup folder."
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            }
            ApplyDiffView(
                before: baselineContent,
                after: targetContent,
                title: errorMessage == nil
                    ? l10n.s("已应用更改", "Applied changes")
                    : l10n.s("待应用更改", "Pending changes")
            )
            Spacer()
            HStack {
                Spacer()
                Button(l10n.s("完成", "Done"), action: onDone)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

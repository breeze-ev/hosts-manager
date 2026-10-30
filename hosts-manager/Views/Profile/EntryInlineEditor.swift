import SwiftUI

struct EntryInlineEditor: View {
    @Binding var ip: String
    @Binding var hosts: String
    @Binding var desc: String
    @Binding var enabled: Bool
    let error: String?
    let saveTitle: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("127.0.0.1 / ::1", text: $ip)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                TextField("example.com www.example.com", text: $hosts)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                TextField(l10n.s("描述", "Description"), text: $desc)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text(l10n.s("启用", "Enabled"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button(l10n.s("取消", "Cancel")) { onCancel() }
                    .buttonStyle(.glass)
                Button(saveTitle) { onSave() }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

#Preview("Inline Entry Editor") {
    @Previewable @State var ip = "127.0.0.1"
    @Previewable @State var hosts = "api.dev.local admin.dev.local"
    @Previewable @State var description = "本地 API 服务"
    @Previewable @State var enabled = true

    EntryInlineEditor(
        ip: $ip,
        hosts: $hosts,
        desc: $description,
        enabled: $enabled,
        error: nil,
        saveTitle: "确认",
        onCancel: {},
        onSave: {}
    )
    .environmentObject(Localization())
    .padding()
    .frame(width: 820)
}

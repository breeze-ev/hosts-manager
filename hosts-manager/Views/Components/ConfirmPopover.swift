import SwiftUI

// MARK: - Inline confirmation popover

struct ConfirmPopover: View {
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(cancelTitle, role: .cancel) {
                    onCancel()
                }
                .controlSize(.small)
                .buttonStyle(.glass)
                Button(confirmTitle, role: .destructive) {
                    onConfirm()
                }
                .controlSize(.small)
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

typealias DeleteConfirmPopover = ConfirmPopover

#Preview("Confirm Popover") {
    ConfirmPopover(
        title: "删除此配置？",
        message: "此操作无法撤销。",
        cancelTitle: "取消",
        confirmTitle: "删除",
        onCancel: {},
        onConfirm: {}
    )
    .padding()
    .background(.regularMaterial)
}

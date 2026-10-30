import SwiftUI

struct RowIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

#Preview("Row Icon Button") {
    HStack(spacing: 0) {
        RowIconButton(systemName: "pencil", help: "编辑") {}
        RowIconButton(systemName: "trash", help: "删除") {}
    }
    .padding()
}

import SwiftUI

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 170, alignment: .leading)
            Spacer()
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

#Preview("Settings Row") {
    @Previewable @State var enabled = true

    SettingsRow(label: "背景模糊") {
        Toggle("背景模糊", isOn: $enabled)
            .labelsHidden()
            .toggleStyle(.switch)
    }
    .detailCard(cornerRadius: 14)
    .padding()
    .frame(width: 620)
}

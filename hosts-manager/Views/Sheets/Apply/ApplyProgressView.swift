import SwiftUI

struct ApplyProgressView: View {
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(l10n.s("正在写入 /etc/hosts…", "Writing to /etc/hosts…"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

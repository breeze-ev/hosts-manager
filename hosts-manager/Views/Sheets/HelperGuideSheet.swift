import SwiftUI

// MARK: - Helper guide

struct HelperGuideSheet: View {
    @EnvironmentObject private var l10n: Localization
    @State private var message: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s("启用后台写入助手", "Enable the Background Writer Helper"))
                        .font(.system(size: 20, weight: .bold))
                    Text(l10n.s("后台功能需要启用后才能使用。", "This background feature only works while it's enabled."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                guideRow(
                    icon: "bolt.fill",
                    title: l10n.s("静默写入 /etc/hosts", "Silent writes to /etc/hosts"),
                    detail: l10n.s("修改 hosts 时不再每次输入管理员密码。", "Hosts changes are written without asking for your admin password each time.")
                )
                guideRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: l10n.s("自动应用配置", "Automatic profile apply"),
                    detail: l10n.s("切换配置、实时应用都会在后台自动完成。", "Profile switches and real-time applies complete automatically in the background.")
                )
                guideRow(
                    icon: "lock.shield",
                    title: l10n.s("仅本应用可用", "Only this app can call it"),
                    detail: l10n.s("助手只接受本应用签名调用，安全可靠。", "The helper only accepts calls from this signed app.")
                )
            }

            Divider()

            Text(l10n.s("如何启用", "How to enable"))
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                guideStep(1, l10n.s("点击下方“立即启用”。", "Tap Enable Now below."))
                guideStep(2, l10n.s(
                    "在弹出的系统设置 → 通用 → 登录项与扩展中，找到 Hosts Manager 并打开助手。",
                    "In System Settings > General > Login Items & Extensions, find Hosts Manager and turn on the helper."
                ))
            }

            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(l10n.s("暂不启用", "Not Now")) {
                    onClose()
                }
                .buttonStyle(.glass)

                Button(l10n.s("立即启用", "Enable Now")) {
                    let error = HostsHelperClient.enable(isEnglish: l10n.isEnglish)
                    if let error {
                        message = error
                    } else if HostsHelperClient.isRegistered {
                        onClose()
                    } else {
                        message = l10n.s(
                            "已请求启用，请在系统设置中允许后返回。",
                            "Enable requested. Allow it in System Settings, then come back."
                        )
                        HostsHelperClient.openSystemSettingsLoginItems()
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12.5))
        }
    }
}

#Preview("Helper Guide") {
    HelperGuideSheet(onClose: {})
        .environmentObject(Localization())
}

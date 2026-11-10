import AppKit
import SwiftUI

enum AboutWindow {
    static let id = "about"
}

enum AppLinks {
    static let repository = url("https://github.com/breeze-ev/hosts-manager")
    static let issues = url("https://github.com/breeze-ev/hosts-manager/issues")
    static let license = url("https://github.com/breeze-ev/hosts-manager/blob/master/LICENSE")

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid app link: \(string)")
        }
        return url
    }
}

struct AboutView: View {
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            VStack(spacing: 5) {
                Text("Hosts Manager")
                    .font(.system(size: 20, weight: .semibold))
                Text(l10n.s(
                    "版本 \(AppBuildInfo.shortVersion)（\(AppBuildInfo.buildNumber)）",
                    "Version \(AppBuildInfo.shortVersion) (\(AppBuildInfo.buildNumber))"
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                GridRow {
                    Text(l10n.s("作者", "Author"))
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    Text("Breeze")
                }
                GridRow {
                    Text("GitHub")
                        .foregroundStyle(.secondary)
                    Link("breeze-ev/hosts-manager", destination: AppLinks.repository)
                        .help(AppLinks.repository.absoluteString)
                }
                GridRow {
                    Text(l10n.s("问题反馈", "Issues"))
                        .foregroundStyle(.secondary)
                    Link(l10n.s("提交问题", "Report an Issue"), destination: AppLinks.issues)
                        .help(AppLinks.issues.absoluteString)
                }
                GridRow {
                    Text(l10n.s("许可证", "License"))
                        .foregroundStyle(.secondary)
                    Link("MIT", destination: AppLinks.license)
                        .help(l10n.s("查看 MIT 许可证", "View the MIT license"))
                }
            }
            .font(.system(size: 12.5))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("© 2026 Breeze")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360)
    }
}

#Preview("About") {
    AboutView()
        .environmentObject(Localization())
}

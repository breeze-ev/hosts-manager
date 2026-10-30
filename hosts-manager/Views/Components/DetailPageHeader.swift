import SwiftUI

private enum DetailHeaderMetrics {
    static let titleSize: CGFloat = 28
    static let subtitleSize: CGFloat = 13
}

struct DetailPageHeader: View {
    let title: String
    let subtitle: String?
    var badge: AnyView?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: DetailHeaderMetrics.titleSize, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let badge {
                        badge
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: DetailHeaderMetrics.subtitleSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailing {
                trailing
            }
        }
    }
}

#Preview("Detail Page Header") {
    DetailPageHeader(
        title: "开发环境",
        subtitle: "5 条启用 · 2 条停用",
        badge: AnyView(
            Text("已应用")
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.green.opacity(0.16)))
                .foregroundStyle(.green)
        ),
        trailing: AnyView(
            Button("添加", systemImage: "plus") {}
                .buttonStyle(.glass)
        )
    )
    .padding(24)
    .frame(width: 680)
    .background(.regularMaterial)
}

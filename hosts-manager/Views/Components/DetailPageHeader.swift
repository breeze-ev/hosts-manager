import SwiftUI

private enum DetailHeaderMetrics {
    static let subtitleSize: CGFloat = 13
    static let minHeight: CGFloat = 28
}

/// Shared page-level layout metrics so every detail page places its header at
/// the same vertical offset, regardless of whether it is hosted in a list's
/// safe-area bar or in a plain stack.
enum DetailPageMetrics {
    static let headerTopInset: CGFloat = 2
    static let horizontalInset: CGFloat = 12
    static let bottomInset: CGFloat = 0
}

struct DetailPageHeader: View {
    let subtitle: String?
    var badge: AnyView?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                if let badge {
                    badge
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
        .frame(minHeight: DetailHeaderMetrics.minHeight)
    }
}

#Preview("Detail Page Header") {
    DetailPageHeader(
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

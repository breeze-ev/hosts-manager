import SwiftUI

struct ApplyDiffView: View {
    let before: String
    let after: String
    let title: String
    @EnvironmentObject private var l10n: Localization

    private let displayLimit = 300

    var body: some View {
        let diff = HostsLineDiff.compare(before: before, after: after)
        let removed = Array(diff.removed.prefix(displayLimit))
        let added = Array(diff.added.prefix(displayLimit))
        let hiddenCount = max(0, diff.removed.count - removed.count)
            + max(0, diff.added.count - added.count)

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                if diff.isEmpty {
                    Text(l10n.s("内容无变化", "No changes"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(removed.enumerated()), id: \.offset) { _, line in
                            Text("− \(line)")
                                .foregroundStyle(.red)
                        }
                        ForEach(Array(added.enumerated()), id: \.offset) { _, line in
                            Text("+ \(line)")
                                .foregroundStyle(.green)
                        }
                        if hiddenCount > 0 {
                            Text(l10n.s(
                                "另有 \(hiddenCount) 行变更未展开。",
                                "\(hiddenCount) additional changed lines are hidden."
                            ))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

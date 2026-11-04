import SwiftUI

// MARK: - Profile detail

struct ProfileDetailView: View {
    @ObservedObject var profile: Profile
    @Binding var mode: EntryMode
    @Binding var query: String
    @Binding var sourceText: String
    let isSourceDirty: Bool
    let hasDraftConflict: Bool
    let onApply: () -> Void
    let onDiscardDraft: () -> Void
    @EnvironmentObject private var l10n: Localization
    @State private var isAdding = false

    var body: some View {
        Group {
            if profile.isSystem {
                SystemHostsView(
                    mode: mode,
                    query: query,
                    header: AnyView(header)
                )
            } else if mode == .list {
                EntriesListView(
                    profile: profile,
                    query: query,
                    isAdding: $isAdding,
                    header: AnyView(header)
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    SourceEditorView(
                        profile: profile,
                        text: $sourceText,
                        isDirty: isSourceDirty,
                        hasDraftConflict: hasDraftConflict,
                        onApply: onApply,
                        onDiscardDraft: onDiscardDraft,
                        toolbarQuery: query
                    )
                }
            }
        }
        .padding(.horizontal, DetailPageMetrics.horizontalInset)
        .padding(.bottom, DetailPageMetrics.bottomInset)
        .padding(.top, mode == .list ? 0 : DetailPageMetrics.headerTopInset)
        // 不再在出现/切模式时往草稿里写初始文本：sourceText 的 getter 已经会返回
        // 生成好的内容，写入反而会让空配置凭空变成“未应用”状态。
    }

    private var header: some View {
        DetailPageHeader(
            subtitle: meta,
            trailing: addButton
        )
    }

    private var addButton: AnyView? {
        guard !profile.isSystem && mode == .list else { return nil }
        return AnyView(
            Button(l10n.s("添加", "Add"), systemImage: "plus") {
                isAdding = true
            }
            .buttonStyle(.glass)
            .frame(minWidth: 64)
        )
    }

    private var meta: String {
        detailProfileSubtitle(for: profile, l10n: l10n)
    }

}

#Preview("Profile Detail") {
    @Previewable @State var mode: EntryMode = .list
    @Previewable @State var query = ""
    @Previewable @State var sourceText = localizedSourceText(
        for: PreviewFixtures.userProfile,
        isEnglish: false
    )

    ProfileDetailView(
        profile: PreviewFixtures.userProfile,
        mode: $mode,
        query: $query,
        sourceText: $sourceText,
        isSourceDirty: false,
        hasDraftConflict: false,
        onApply: {},
        onDiscardDraft: {}
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .frame(width: 860, height: 640)
}

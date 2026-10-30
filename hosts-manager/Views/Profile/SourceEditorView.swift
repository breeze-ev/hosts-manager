import SwiftUI

struct SourceEditorView: View {
    @ObservedObject var profile: Profile
    @Binding var text: String
    let isDirty: Bool
    let hasDraftConflict: Bool
    let onApply: () -> Void
    let onDiscardDraft: () -> Void
    let toolbarQuery: String
    let onScrollOffsetChange: (CGFloat) -> Void
    @EnvironmentObject private var l10n: Localization
    @StateObject private var proxy = SourceEditorProxy()
    @State private var showFind = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var validationMessage: String?
    @FocusState private var isReplaceFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(l10n.s("编辑", "Edit"), systemImage: "pencil")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                if isDirty {
                    Text(l10n.s("未应用", "Unapplied"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                if hasDraftConflict {
                    Label(l10n.s("列表已变更", "List changed"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .help(l10n.s(
                            "编辑源码期间列表内容被修改过。点击“应用”以源码为准写入，或点击“放弃修改”丢弃草稿。",
                            "The list was changed while you were editing. Apply to keep the source text, or discard your draft."
                        ))
                }
                Spacer()
                if isDirty {
                    Button(l10n.s("放弃修改", "Discard")) {
                        onDiscardDraft()
                    }
                    .buttonStyle(.glass)
                    .help(l10n.s(
                        "丢弃当前源码草稿，恢复为已保存的内容。",
                        "Discard the current source draft and restore the saved content."
                    ))
                }
                if validationMessage == nil {
                    Label(l10n.s("校验通过", "Valid"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(validationMessage ?? "")
                }

                Button(l10n.s("校验", "Validate")) {
                    validate()
                }
                .buttonStyle(.glass)

                Button {
                    showFind.toggle()
                    isReplaceFieldFocused = showFind
                } label: {
                    Label(l10n.s("替换", "Replace"), systemImage: "arrow.2.squarepath")
                }
                .buttonStyle(.glass)
                .help(l10n.s("查找与替换", "Find and Replace"))

                Button {
                    onApply()
                } label: {
                    Label(l10n.s("应用", "Apply"), systemImage: "checkmark.circle")
                }
                .buttonStyle(.glassProminent)
                .disabled(validationMessage != nil)
                .accessibilityIdentifier("apply-profile-button")
                .help(l10n.s("预览后写入 /etc/hosts", "Preview, then write to /etc/hosts"))
            }

            if showFind {
                HStack(spacing: 8) {
                    TextField(l10n.s("查找", "Find"), text: $findText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    Button {
                        _ = proxy.findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 24, height: 16)
                    }
                    .buttonStyle(.glass)
                    Button {
                        _ = proxy.findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 24, height: 16)
                    }
                    .buttonStyle(.glass)
                    TextField(l10n.s("替换", "Replace"), text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .focused($isReplaceFieldFocused)
                    Button(l10n.s("全部替换", "Replace All")) {
                        _ = proxy.replaceAll(query: findText, replacement: replaceText)
                    }
                    .buttonStyle(.glass)
                    Button(l10n.s("完成", "Done")) {
                        showFind = false
                        isReplaceFieldFocused = false
                    }
                    .buttonStyle(.glass)
                }
                .font(.system(size: 12))
                .task(id: findText) {
                    proxy.prepareFind(query: findText)
                }
            }

            SourceTextEditor(
                text: $text,
                proxy: proxy,
                onScrollOffsetChange: onScrollOffsetChange
            )
                .editorSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                Text("\(proxy.status.line):\(proxy.status.column)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !findText.isEmpty {
                    Text("\(proxy.status.findIndex)/\(proxy.status.findMatches)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(l10n.s("\(proxy.status.totalLines) 行", "\(proxy.status.totalLines) lines"))
                Text(l10n.s(
                    "启用 \(proxy.status.enabledEntries) / 共 \(proxy.status.totalEntries)",
                    "Enabled \(proxy.status.enabledEntries) of \(proxy.status.totalEntries)"
                ))
                Text(l10n.s("写入前自动备份", "Backup before write"))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        // NSViewRepresentable installs the text view during the SwiftUI update.
        // Defer observable status/find changes until that transaction finishes.
        .task(id: text) {
            validate()
            proxy.refreshStatus()
            proxy.reapplyFindHighlight()
        }
        .task(id: toolbarQuery) {
            proxy.applyFindHighlight(query: toolbarQuery)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceFind)) { _ in
            showFind = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceToggleComment)) { _ in
            proxy.toggleCommentOnSelection()
            validate()
        }
    }

    private func validate() {
        validationMessage = HostsValueValidator.validate(content: text)
    }
}

#Preview("Source Editor") {
    @Previewable @State var text = localizedSourceText(
        for: PreviewFixtures.userProfile,
        isEnglish: false
    )

    SourceEditorView(
        profile: PreviewFixtures.userProfile,
        text: $text,
        isDirty: false,
        hasDraftConflict: false,
        onApply: {},
        onDiscardDraft: {},
        toolbarQuery: "",
        onScrollOffsetChange: { _ in }
    )
    .environment(\.managedObjectContext, PreviewFixtures.context)
    .environmentObject(Localization())
    .padding()
    .frame(width: 860, height: 620)
}

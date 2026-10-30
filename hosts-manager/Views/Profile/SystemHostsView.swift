import SwiftUI
import AppKit

// MARK: - System (read-only live view)

struct SystemHostsView: View {
    let mode: EntryMode
    let query: String
    let header: AnyView
    let isHeaderCollapsed: Bool
    let onScrollOffsetChange: (CGFloat) -> Void
    @EnvironmentObject private var l10n: Localization
    @State private var content = ""

    private var live: [ParsedHostEntry] {
        HostsParser.parse(content)
    }

    private var raw: String {
        content
    }

    private var filtered: [ParsedHostEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return live }
        return live.filter {
            $0.ip.lowercased().contains(q) ||
            $0.hostnames.joined(separator: " ").lowercased().contains(q) ||
            localizedSeedDescription($0.desc, isEnglish: l10n.isEnglish).lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if mode == .list {
                if live.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        if !isHeaderCollapsed {
                            header
                        }
                        ContentUnavailableView(l10n.s("无法读取 /etc/hosts", "Could not read /etc/hosts"), systemImage: "exclamationmark.triangle")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        if !isHeaderCollapsed {
                            header
                        }
                        ContentUnavailableView(l10n.s("没有匹配的条目", "No matching entries"), systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    List {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                            #if DEBUG
                            if PreviewEnvironment.isRunning {
                                AnyView(EmptyView())
                            }
                            #endif
                            HStack(spacing: 12) {
                                Image(systemName: entry.isEnabled ? "circle.fill" : "circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(entry.isEnabled ? .green : .secondary)
                                Text(entry.ip)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 140, alignment: .leading)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    ForEach(entry.hostnames, id: \.self) { host in
                                        Text(host)
                                            .font(.system(.caption, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(.thinMaterial))
                                            .overlay(Capsule().stroke(.quaternary))
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(localizedSeedDescription(entry.desc, isEnglish: l10n.isEnglish))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .opacity(entry.isEnabled ? 1 : 0.6)
                            .listRowSeparator(.hidden)
                            .zebraRowBackground(index)
                        }
                    }
                    .listStyle(.inset)
                    .detailListSafeAreaHeader(isCollapsed: isHeaderCollapsed) {
                        header
                    }
                    .detailHeaderScrollTracking(onScrollOffsetChange)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.s("/etc/hosts（系统只读）", "/etc/hosts (system, read-only)"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ReadOnlyHostsTextView(
                            content: raw,
                            query: query,
                            onScrollOffsetChange: onScrollOffsetChange
                        )
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .editorSurface(cornerRadius: 14)
                    }
                }
            }
        }
        .onAppear {
            refreshContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hostsContentChanged)) { _ in
            refreshContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshContent()
        }
    }

    private func refreshContent() {
        content = HostsWriter.currentContent()
    }
}

#Preview("System Hosts") {
    SystemHostsView(
        mode: .list,
        query: "",
        header: AnyView(
            DetailPageHeader(
                title: "系统",
                subtitle: "来自 /etc/hosts 的实时内容",
                badge: AnyView(
                    Text("系统只读")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .foregroundStyle(.secondary)
                )
            )
        ),
        isHeaderCollapsed: false,
        onScrollOffsetChange: { _ in }
    )
    .environmentObject(Localization())
    .frame(width: 860, height: 620)
}

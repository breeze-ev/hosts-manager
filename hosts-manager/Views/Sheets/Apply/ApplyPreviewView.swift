import SwiftUI

struct ApplyPreviewView: View {
    let profileName: String
    let plan: ApplyPlan
    let baselineContent: String
    let onRemoveDuplicates: () -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.s(
                "应用“\(profileName)”",
                "Apply “\(profileName)”"
            ))
            .font(.system(size: 20, weight: .bold))

            backupNotice
            if !plan.validationIssues.isEmpty {
                validationNotice
            }
            ApplyDiffView(
                before: baselineContent,
                after: plan.targetContent,
                title: l10n.s("预览", "Preview")
            )
            Spacer()
            HStack {
                Spacer()
                Button(l10n.s("取消", "Cancel"), action: onCancel)
                    .buttonStyle(.glass)
                Button(l10n.s("确认应用", "Confirm Apply"), action: onConfirm)
                    .buttonStyle(.glassProminent)
                    .disabled(!plan.canApply)
                    .accessibilityIdentifier("confirm-apply-button")
            }
        }
    }

    private var backupNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.green)
            Text(l10n.s(
                "写入前将自动备份当前 /etc/hosts 到备份目录，可随时还原。",
                "The current /etc/hosts will be backed up before writing and can be restored anytime."
            ))
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.green.opacity(0.3))
        )
    }

    private var validationNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                plan.conflictIssues.isEmpty
                    ? l10n.s("存在完全重复条目", "Exact duplicates found")
                    : l10n.s("存在主机名冲突", "Hostname conflict found"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(plan.conflictIssues.isEmpty ? .green : .orange)
            Text(plan.validationIssues.map(\.hostname).joined(separator: ", "))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            if !plan.conflictIssues.isEmpty {
                Text(l10n.s(
                    "这些主机名分别指向了不同 IP；修复前不会写入系统。",
                    "These hostnames point to different IPs; nothing will be written until they are fixed."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else if !plan.duplicateIssues.isEmpty {
                Text(l10n.s(
                    "完全重复条目会在写入时自动去重，不会阻止应用。",
                    "Exact duplicates are removed automatically when applying and do not block the write."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            if plan.hasExactDuplicatesInTargets {
                Button(l10n.s(
                    "清理应用范围内的完全重复条目",
                    "Remove Exact Duplicates in Applied Profiles"
                )) {
                    onRemoveDuplicates()
                }
                .buttonStyle(.glass)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.orange.opacity(0.1))
        )
    }
}

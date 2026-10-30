import SwiftUI
import CoreData
import AppKit

// MARK: - Settings

struct SettingsView: View {
    @FetchRequest private var settings: FetchedResults<AppSettings>
    @EnvironmentObject private var l10n: Localization
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("backgroundBlurEnabled") private var backgroundBlurEnabled = false
    @State private var retention = 30
    @State private var defaultView = EntryMode.list.rawValue
    @State private var helperStatus = HostsHelperClient.status
    @State private var installMessage: String?
    @State private var settingsError: String?
    init() {
        _settings = FetchRequest(sortDescriptors: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailPageHeader(
                title: l10n.s("设置", "Settings"),
                subtitle: l10n.s(
                    "管理默认视图、备份保留、外观与后台写入。",
                    "Manage the default view, backup retention, appearance, and background writes."
                )
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preferencesSection
                    updateSection
                    helperSection
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 16)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshHelperStatus()
            if let s = settings.first {
                retention = Int(s.backupRetention)
                defaultView = s.defaultView ?? EntryMode.list.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshHelperStatus()
        }
        .onChange(of: defaultView) { _, newValue in
            settings.first?.defaultView = newValue
            saveSettings()
            NotificationCenter.default.post(name: .defaultEntryModeChanged, object: newValue)
        }
        .onChange(of: retention) { _, newValue in
            settings.first?.backupRetention = Int64(newValue)
            saveSettings()
            if let context = settings.first?.managedObjectContext {
                do {
                    try BackupMaintenance.prune(context: context)
                } catch {
                    context.rollback()
                    settingsError = l10n.s("无法清理旧备份。", "Unable to prune old backups.")
                }
            }
        }
        .alert(
            l10n.s("保存设置失败", "Unable to Save Settings"),
            isPresented: Binding(
                get: { settingsError != nil },
                set: { if !$0 { settingsError = nil } }
            )
        ) {
            Button("OK") { settingsError = nil }
        } message: {
            Text(settingsError ?? "")
        }
    }

    private func refreshHelperStatus() {
        helperStatus = HostsHelperClient.status
    }

    private var preferencesSection: some View {
        VStack(spacing: 0) {
            SettingsRow(label: l10n.s("默认视图", "Default view")) {
                Picker("", selection: $defaultView) {
                    Label(l10n.s("列表", "List"), systemImage: "list.bullet").tag(EntryMode.list.rawValue)
                    Label(l10n.s("编辑", "Edit"), systemImage: "pencil").tag(EntryMode.source.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider()
            SettingsRow(label: l10n.s("备份保留数量", "Backup retention")) {
                Stepper("\(retention)", value: $retention, in: 1...100)
            }
            Divider()
            SettingsRow(label: l10n.s("界面语言", "Interface language")) {
                Picker("", selection: $l10n.language) {
                    Text(l10n.s("跟随系统", "Follow system")).tag("system")
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider()
            SettingsRow(label: l10n.s("外观", "Appearance")) {
                Picker("", selection: $appearance) {
                    Text(l10n.s("跟随系统", "Follow system")).tag("system")
                    Text(l10n.s("浅色", "Light")).tag("light")
                    Text(l10n.s("深色", "Dark")).tag("dark")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider()
            SettingsRow(label: l10n.s("背景", "Background")) {
                Toggle(l10n.s("背景模糊", "Background blur"), isOn: $backgroundBlurEnabled)
                    .toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity)
        .detailCard(cornerRadius: 14)
    }

    private var helperSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.blue)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.s(
                    "后台写入助手：\(helperStatusLabel)",
                    "Background Writer Helper: \(helperStatusLabel)"
                ))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text(l10n.s(
                    "启用后可静默写入 /etc/hosts，无需每次输入管理员密码，切换配置与实时应用都会在后台自动完成。助手仅接受本应用的签名调用。",
                    "When enabled, hosts changes are written silently without asking for your admin password each time, and profile switches and real-time applies complete automatically in the background. The helper only accepts calls signed by this app."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                if let installMessage {
                    installMessageView(installMessage)
                }
                if !HostsHelperClient.isRegistered {
                    Button(l10n.s("启用助手", "Enable Helper")) {
                        let error = HostsHelperClient.enable(isEnglish: l10n.isEnglish)
                        if let error {
                            installMessage = error
                        } else if HostsHelperClient.isRegistered {
                            installMessage = l10n.s("助手已启用。", "Helper is enabled.")
                        } else {
                            installMessage = l10n.s(
                                "已请求启用，请在系统设置中允许后返回。",
                                "Enable requested. Allow it in System Settings, then come back."
                            )
                            HostsHelperClient.openSystemSettingsLoginItems()
                        }
                        refreshHelperStatus()
                    }
                    .buttonStyle(.glass)
                }
            }
            Spacer()
        }
        .padding(12)
        .detailCard()
    }

    private var helperStatusLabel: String {
        HostsHelperClient.statusLabel(
            for: helperStatus,
            isEnglish: l10n.isEnglish
        )
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.s("软件更新", "Software Update"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(l10n.s(
                        "当前版本 \(AppBuildInfo.shortVersion)（\(AppBuildInfo.buildNumber)）",
                        "Current version \(AppBuildInfo.shortVersion) (\(AppBuildInfo.buildNumber))"
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    SparkleUpdater.shared.checkForUpdates()
                } label: {
                    Text(l10n.s("检查更新…", "Check for Updates…"))
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("settings-check-for-updates")
            }

        }
        .padding(12)
        .detailCard()
        .accessibilityIdentifier("software-update-card")
    }

    private func installMessageView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.orange)
    }

    private func saveSettings() {
        guard let context = settings.first?.managedObjectContext else {
            settingsError = l10n.s(
                "设置数据不存在，无法保存。请重新打开应用后再试。",
                "The settings record is missing and could not be saved. Reopen the app and try again."
            )
            return
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            settingsError = error.localizedDescription
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(\.managedObjectContext, PreviewFixtures.context)
        .environmentObject(Localization())
        .frame(width: 860, height: 620)
}

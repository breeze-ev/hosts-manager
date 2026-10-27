import SwiftUI
import CoreData
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let language = UserDefaults.standard.string(forKey: "language") ?? "system"
        LocalizationPreference.applyAppleLanguages(for: language)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateAppMenuTitle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.updateAppMenuTitle()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateAppMenuTitle()
    }

    private func updateAppMenuTitle() {
        NSApp.mainMenu?.items.first?.submenu?.title = "Hosts Manager"
    }
}

@main
struct HostsManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var l10n = Localization()
    @StateObject private var updateCenter = UpdateCenter.forCurrentProcess()
    @AppStorage("language") private var language = "system"

    private var isEnglish: Bool {
        LocalizationPreference.isEnglish(for: language)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if persistenceController.loadError == nil {
                    ContentView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                } else {
                    StoreRecoveryView(persistenceController: persistenceController)
                }
            }
            .environmentObject(l10n)
            .environmentObject(updateCenter)
            .task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await updateCenter.checkAutomaticallyIfDue()
            }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(isEnglish ? "Check for Updates…" : "检查更新…") {
                    Task { await updateCenter.checkForUpdates(manual: true) }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .accessibilityIdentifier("check-for-updates-menu-item")
            }
            CommandGroup(after: .saveItem) {
                Button(isEnglish ? "Apply Profile" : "应用配置") {
                    NotificationCenter.default.post(name: .performApply, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button(isEnglish ? "Find" : "查找…") {
                    NotificationCenter.default.post(name: .sourceFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button(isEnglish ? "Toggle Comment" : "注释 / 取消注释") {
                    NotificationCenter.default.post(name: .sourceToggleComment, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button(isEnglish ? "Settings…" : "设置…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

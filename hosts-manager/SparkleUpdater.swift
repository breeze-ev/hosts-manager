import AppKit
import Foundation
import Sparkle

nonisolated enum AppBuildInfo {
    static var shortVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
    }
}

@MainActor
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdater()

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard controller == nil else { return }

        // Unit and UI test hosts should never contact the production feed.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        start()
        guard let controller else { return }

        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        #if arch(x86_64)
        return "https://raw.githubusercontent.com/breeze-ev/hosts-manager/master/Sparkle/appcast-x86_64.xml"
        #else
        return "https://raw.githubusercontent.com/breeze-ev/hosts-manager/master/Sparkle/appcast-arm64.xml"
        #endif
    }
}

import Foundation

nonisolated enum PreviewEnvironment {
    static var isRunning: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
        #else
        return false
        #endif
    }
}

import Foundation

extension Notification.Name {
    static let openSettings = Notification.Name("hostsManager.openSettings")
    static let performApply = Notification.Name("hostsManager.performApply")
    static let sourceDraftApplied = Notification.Name("hostsManager.sourceDraftApplied")
    static let profileEntriesChanged = Notification.Name("hostsManager.profileEntriesChanged")
    static let defaultEntryModeChanged = Notification.Name("hostsManager.defaultEntryModeChanged")
    static let sourceFind = Notification.Name("hostsManager.sourceFind")
    static let sourceToggleComment = Notification.Name("hostsManager.sourceToggleComment")
    static let hostsStateReconciled = Notification.Name("hostsManager.hostsStateReconciled")
    static let hostsStateNeedsReconciliation = Notification.Name("hostsManager.hostsStateNeedsReconciliation")
    static let hostsStateSynchronized = Notification.Name("hostsManager.hostsStateSynchronized")
    static let hostsContentChanged = Notification.Name("hostsManager.hostsContentChanged")
}

enum HostsStateNotificationKey {
    static let appliedProfileIDs = "appliedProfileIDs"
    static let managedHostnames = "managedHostnames"
    static let skipRealtimeApply = "skipRealtimeApply"
}

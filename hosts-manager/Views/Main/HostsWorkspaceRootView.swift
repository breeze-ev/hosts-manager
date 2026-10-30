import CoreData
import SwiftUI

/// Owns the workspace model for the lifetime of the main window. Keeping this
/// lifecycle separate from the FetchRequest-backed view also keeps SwiftUI's
/// dynamic query wrapper out of a custom initializer.
struct HostsWorkspaceRootView: View {
    @State private var workspace: HostsWorkspaceModel

    init(context: NSManagedObjectContext, localization: Localization) {
        _workspace = State(
            initialValue: HostsWorkspaceModel(
                context: context,
                localization: localization
            )
        )
    }

    var body: some View {
        HostsWorkspaceView(workspace: workspace)
    }
}

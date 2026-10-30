import CoreData
import SwiftUI

/// Resolves SwiftUI environment values before creating the long-lived workspace
/// observation model. Environment values are not available from `init`.
struct ContentView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var l10n: Localization

    var body: some View {
        HostsWorkspaceRootView(context: context, localization: l10n)
    }
}

#Preview("Main Window") {
    ContentView()
        .environment(\.managedObjectContext, PreviewFixtures.context)
        .environmentObject(Localization())
        .frame(minWidth: 1_000, minHeight: 680)
}

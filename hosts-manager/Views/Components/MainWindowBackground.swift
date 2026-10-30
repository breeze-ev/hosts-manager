import SwiftUI
import AppKit

struct MainWindowBackground: View {
    let isBlurEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isBlurEnabled {
            Rectangle()
                .fill(.thinMaterial)
                .overlay {
                    if colorScheme == .dark {
                        // Thin material picks up a lot of brightness from a light
                        // desktop. Tint it down so white detail text keeps contrast.
                        Color.black.opacity(0.32)
                    }
                }
        } else {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }
}

#Preview("Window Background") {
    ZStack {
        MainWindowBackground(isBlurEnabled: true)
        Text("Hosts Manager")
            .font(.system(size: 28, weight: .bold))
    }
    .frame(width: 520, height: 300)
}

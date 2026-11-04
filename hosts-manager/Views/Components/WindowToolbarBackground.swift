import AppKit
import SwiftUI

/// Shows a solid toolbar background only while the window is in full screen.
/// Windowed windows keep the toolbar transparent so the window background and
/// its materials stay visible.
struct WindowToolbarBackground: ViewModifier {
    @State private var isFullScreen = false

    func body(content: Content) -> some View {
        content
            .background(WindowFullScreenState(isFullScreen: $isFullScreen))
            .toolbarBackground(.windowBackground, for: .windowToolbar)
            .toolbarBackgroundVisibility(
                isFullScreen ? .visible : .hidden,
                for: .windowToolbar
            )
    }
}

/// Reports the hosting window's full-screen state through a binding.
private struct WindowFullScreenState: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> WindowStateView {
        let view = WindowStateView()
        let coordinator = context.coordinator
        view.onWindowChange = { window in
            coordinator.observe(window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowStateView, context: Context) {
        context.coordinator.update(binding: $isFullScreen)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    final class Coordinator {
        private var isFullScreen: Binding<Bool>
        private weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        func update(binding: Binding<Bool>) {
            isFullScreen = binding
        }

        func observe(_ window: NSWindow?) {
            guard self.window !== window else { return }
            removeObservers()
            self.window = window
            guard let window else { return }

            let center = NotificationCenter.default
            let enter = center.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(true) }
            }
            let exit = center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.set(false) }
            }
            tokens = [enter, exit]

            // `viewDidMoveToWindow` runs inside AppKit's layout pass, so the
            // first state write is deferred to avoid updating SwiftUI mid-layout.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.set(self.window?.styleMask.contains(.fullScreen) ?? false)
                }
            }
        }

        private func set(_ value: Bool) {
            guard isFullScreen.wrappedValue != value else { return }
            isFullScreen.wrappedValue = value
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            tokens.forEach(center.removeObserver)
            tokens.removeAll()
        }
    }
}

private final class WindowStateView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

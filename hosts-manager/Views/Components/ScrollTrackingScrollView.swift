import AppKit

// MARK: - Shared scrolling

final class ScrollTrackingScrollView: NSScrollView {
    var onScrollOffsetChange: ((CGFloat) -> Void)?
    private var boundsObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.reportScrollOffset()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func reportScrollOffset() {
        onScrollOffsetChange?(max(0, contentView.bounds.minY))
    }
}

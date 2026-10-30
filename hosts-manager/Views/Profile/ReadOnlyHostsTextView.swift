import SwiftUI
import AppKit

struct ReadOnlyHostsTextView: NSViewRepresentable {
    let content: String
    let query: String
    let onScrollOffsetChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ScrollTrackingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = content
        scrollView.documentView = textView
        Self.apply(content: content, query: query, to: textView)
        scrollView.onScrollOffsetChange = onScrollOffsetChange
        DispatchQueue.main.async {
            scrollView.reportScrollOffset()
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        (nsView as? ScrollTrackingScrollView)?.onScrollOffsetChange = onScrollOffsetChange
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != content {
            tv.string = content
        }
        Self.apply(content: content, query: query, to: tv)
    }

    private static func apply(content: String, query: String, to tv: NSTextView) {
        SourceTextEditor.applyHighlighting(to: tv)
        guard !query.isEmpty else { return }
        let ns = content as NSString
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.location != NSNotFound {
            let found = ns.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            tv.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: found
            )
            searchRange = NSRange(location: NSMaxRange(found), length: ns.length - NSMaxRange(found))
        }
    }
}

#Preview("Read-only Hosts Text") {
    ReadOnlyHostsTextView(
        content: """
        127.0.0.1 localhost
        255.255.255.255 broadcasthost
        ::1 localhost

        127.0.0.1 api.dev.local
        """,
        query: "localhost",
        onScrollOffsetChange: { _ in }
    )
    .editorSurface()
    .frame(width: 720, height: 360)
}

import SwiftUI
import AppKit
import Combine

struct SourceStatus: Equatable {
    var line = 1
    var column = 1
    var totalLines = 1
    var enabledEntries = 0
    var totalEntries = 0
    var validationMessage: String?
    var findMatches = 0
    var findIndex = 0
}

final class SourceEditorProxy: ObservableObject {
    @Published var status = SourceStatus()
    weak var textView: NSTextView?
    private var findRanges: [NSRange] = []
    private var findQuery = ""

    func refreshStatus() {
        guard let tv = textView else { return }
        let string = tv.string
        let ns = string as NSString
        let location = min(tv.selectedRange().location, ns.length)
        let lineStart = ns.lineRange(for: NSMakeRange(location, 0)).location
        let line = ns.substring(to: lineStart).components(separatedBy: "\n").count
        let column = location - lineStart + 1
        let entries = HostsParser.parse(string)
        let newStatus = SourceStatus(
            line: line,
            column: column,
            totalLines: string.isEmpty ? 1 : max(1, ns.components(separatedBy: "\n").count),
            enabledEntries: entries.filter(\.isEnabled).count,
            totalEntries: entries.count,
            validationMessage: HostsValueValidator.validate(content: string),
            findMatches: findRanges.count,
            findIndex: findRanges.isEmpty ? 0 : status.findIndex
        )
        guard newStatus != status else { return }
        status = newStatus
        if let ruler = tv.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            ruler.needsDisplay = true
        }
    }

    func applyFindHighlight(query: String) {
        guard let tv = textView else { return }
        let string = tv.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
        findRanges.removeAll()
        guard !query.isEmpty else {
            findQuery = ""
            status.findMatches = 0
            status.findIndex = 0
            return
        }
        findQuery = query
        var searchRange = NSRange(location: 0, length: string.length)
        while searchRange.location != NSNotFound {
            let found = string.range(of: query, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            findRanges.append(found)
            searchRange = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
        }
        for range in findRanges {
            tv.textStorage?.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.35),
                range: range
            )
        }
        status.findMatches = findRanges.count
        status.findIndex = findRanges.isEmpty ? 0 : 1
        objectWillChange.send()
    }

    func prepareFind(query: String) {
        applyFindHighlight(query: query)
    }

    func reapplyFindHighlight() {
        applyFindHighlight(query: findQuery)
    }

    @discardableResult
    func findNext() -> Int {
        guard textView != nil, !findRanges.isEmpty else { return 0 }
        let current = status.findIndex
        let nextIndex = current >= findRanges.count ? 0 : current
        selectMatch(at: nextIndex)
        return nextIndex + 1
    }

    @discardableResult
    func findPrevious() -> Int {
        guard textView != nil, !findRanges.isEmpty else { return 0 }
        let current = status.findIndex
        let previousIndex = current <= 1 ? findRanges.count - 1 : current - 2
        selectMatch(at: previousIndex)
        return previousIndex + 1
    }

    func replaceAll(query: String, replacement: String) -> Int {
        guard let tv = textView, !query.isEmpty else { return 0 }
        let string = tv.string
        let replaced = string.replacingOccurrences(
            of: query,
            with: replacement,
            options: [.caseInsensitive]
        )
        guard replaced != string else {
            prepareFind(query: query)
            return 0
        }
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard tv.shouldChangeText(in: fullRange, replacementString: replaced) else {
            prepareFind(query: query)
            return 0
        }
        tv.textStorage?.replaceCharacters(in: fullRange, with: replaced)
        tv.didChangeText()
        prepareFind(query: query)
        return (string as NSString).components(separatedBy: query).count - 1
    }

    func toggleCommentOnSelection() {
        guard let tv = textView else { return }
        let full = tv.string as NSString
        guard full.length > 0 else { return }

        let selected = tv.selectedRange()
        let location = min(selected.location, full.length)
        let end = selected.length == 0
            ? location
            : min(selected.location + selected.length - 1, max(0, full.length - 1))
        let combined = NSUnionRange(
            full.lineRange(for: NSMakeRange(location, 0)),
            full.lineRange(for: NSMakeRange(end, 0))
        )
        let block = full.substring(with: combined)
        let toggled = HostsSourceEditing.toggledComment(in: block)

        guard tv.shouldChangeText(in: combined, replacementString: toggled) else { return }
        tv.textStorage?.replaceCharacters(in: combined, with: toggled)
        tv.didChangeText()
        tv.setSelectedRange(NSMakeRange(combined.location, 0))
    }

    private func selectMatch(at index: Int) {
        guard let tv = textView, findRanges.indices.contains(index) else { return }
        let range = findRanges[index]
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        status.findIndex = index + 1
        objectWillChange.send()
    }
}

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.textView = textView
        ruleThickness = 42
        clientView = textView
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.needsDisplay = true
            }
        }
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Do not call super: NSRulerView paints an opaque backing color, which
        // breaks the translucent editor surface.
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView,
              let layoutManager = tv.layoutManager,
              let textContainer = tv.textContainer else { return }

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(rect: NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height)).fill()

        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: tv.visibleRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        let string = tv.string as NSString
        guard string.length > 0 else { return }

        var lineRange = string.lineRange(for: NSMakeRange(visibleCharacterRange.location, 0))
        var lineNumber = string.substring(to: lineRange.location)
            .components(separatedBy: "\n").count

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        while lineRange.location < NSMaxRange(visibleCharacterRange) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let convertedPoint = convert(
                NSPoint(x: 0, y: lineRect.minY + tv.textContainerOrigin.y),
                from: tv
            )
            let labelPoint = NSPoint(x: 6, y: convertedPoint.y + 2)
            NSString(string: "\(lineNumber)").draw(at: labelPoint, withAttributes: attributes)
            lineNumber += 1

            let next = string.lineRange(for: NSMakeRange(NSMaxRange(lineRange), 0))
            if next.location == lineRange.location { break }
            lineRange = next
        }
    }
}

struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String
    var proxy: SourceEditorProxy
    let onScrollOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, proxy: proxy) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ScrollTrackingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isRichText = false
        textView.allowsUndo = true
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
        textView.string = text
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRulerView(scrollView: scrollView, textView: textView)
        proxy.textView = textView
        Self.applyHighlighting(to: textView)
        scrollView.onScrollOffsetChange = onScrollOffsetChange
        DispatchQueue.main.async {
            scrollView.reportScrollOffset()
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        (nsView as? ScrollTrackingScrollView)?.onScrollOffsetChange = onScrollOffsetChange
        guard let tv = nsView.documentView as? NSTextView else { return }
        let changed = tv.string != text
        if changed {
            tv.string = text
            Self.applyHighlighting(to: tv)
        }
        proxy.textView = tv
    }

    static func applyHighlighting(to tv: NSTextView) {
        let full = tv.string
        let ns = full as NSString
        let baseRange = NSRange(location: 0, length: ns.length)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let storage = tv.textStorage
        tv.undoManager?.disableUndoRegistration()
        storage?.beginEditing()
        storage?.addAttribute(.font, value: mono, range: baseRange)
        storage?.addAttribute(.foregroundColor, value: NSColor.labelColor, range: baseRange)
        storage?.removeAttribute(.backgroundColor, range: baseRange)
        if ns.length > 0 {
            ns.enumerateSubstrings(in: baseRange, options: [.byLines]) { substring, lineRange, _, _ in
                guard let line = substring else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return }
                if trimmed.hasPrefix("#") {
                    storage?.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                } else if HostsParser.parse(line).isEmpty {
                    storage?.addAttribute(.foregroundColor, value: NSColor.systemRed, range: lineRange)
                } else {
                    applyTokenColors(line: line, lineRange: lineRange, storage: storage)
                }
            }
        }
        storage?.endEditing()
        tv.undoManager?.enableUndoRegistration()
    }

    private static func applyTokenColors(line: String, lineRange: NSRange, storage: NSTextStorage?) {
        let nsLine = line as NSString
        let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
        var scanLocation = 0
        var isFirst = true

        while scanLocation < nsLine.length {
            let remaining = NSRange(location: scanLocation, length: nsLine.length - scanLocation)
            let found = nsLine.rangeOfCharacter(from: nonWhitespace, options: [], range: remaining)
            if found.location == NSNotFound { break }

            var end = found.location + found.length
            while end < nsLine.length,
                  let scalar = Unicode.Scalar(nsLine.character(at: end)),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                end += 1
            }
            let tokenRange = NSRange(location: found.location, length: end - found.location)
            let token = nsLine.substring(with: tokenRange)
            let absoluteRange = NSRange(location: lineRange.location + tokenRange.location, length: tokenRange.length)

            if token.hasPrefix("#") {
                storage?.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: absoluteRange)
                break
            } else if isFirst {
                storage?.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: absoluteRange)
                isFirst = false
            } else {
                storage?.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: absoluteRange)
            }
            scanLocation = end
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let proxy: SourceEditorProxy

        init(text: Binding<String>, proxy: SourceEditorProxy) {
            self.text = text
            self.proxy = proxy
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
            SourceTextEditor.applyHighlighting(to: tv)
            proxy.refreshStatus()
            proxy.reapplyFindHighlight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            proxy.refreshStatus()
        }
    }
}

#Preview("Source Text Editor") {
    @Previewable @State var text = """
    # Managed by Hosts Manager
    127.0.0.1 localhost
    255.255.255.255 broadcasthost
    ::1 localhost

    127.0.0.1 api.dev.local admin.dev.local
    192.168.1.50 mysql.db.local
    """
    @Previewable @StateObject var proxy = SourceEditorProxy()

    SourceTextEditor(
        text: $text,
        proxy: proxy,
        onScrollOffsetChange: { _ in }
    )
    .editorSurface()
    .frame(width: 760, height: 420)
}

import AppKit
import Foundation
import JavaScriptCore
import SwiftUI

/// Native chat rendering backed by the same GFM parser used in MarkdownViewer.
/// Marked runs with raw HTML disabled, then AppKit renders the safe HTML into a
/// selectable, self-sizing text view.
enum GFMMarkdownRenderer {
    private static let markedSource: String = {
        guard let url = Bundle.module.url(forResource: "marked.umd", withExtension: "js", subdirectory: "Markdown"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return source
    }()

    static func html(from source: String) -> String? {
        guard !markedSource.isEmpty else { return nil }
        let markdown = MarkdownSanitizer.renderable(source)
        guard let encoded = try? JSONEncoder().encode(markdown),
              let literal = String(data: encoded, encoding: .utf8) else { return nil }
        let context = JSContext()
        var failed = false
        context?.exceptionHandler = { _, _ in failed = true }
        context?.evaluateScript(markedSource)
        context?.evaluateScript("marked.use({ gfm: true, breaks: false, renderer: { html() { return ''; } } });")
        let result = context?.evaluateScript("marked.parse(\(literal), { gfm: true, breaks: false });")?.toString()
        guard !failed, let result, !result.isEmpty else { return nil }
        return result
    }

    static func attributed(from source: String) -> NSAttributedString {
        guard let html = html(from: source),
              let rendered = try? NSAttributedString(
                data: Data(html.utf8),
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return NSAttributedString(string: MarkdownSanitizer.renderable(source), attributes: baseAttributes)
        }

        let mutable = NSMutableAttributedString(attributedString: rendered)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: range) { value, attributeRange, _ in
            let existing = value as? NSFont
            let size = max(14, existing?.pointSize ?? 15)
            let traits = existing?.fontDescriptor.symbolicTraits ?? []
            let font = traits.contains(.bold) ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
            mutable.addAttribute(.font, value: font, range: attributeRange)
        }
        mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        return mutable
    }

    private static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor
        ]
    }
}

struct GFMMarkdownMessageView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> MarkdownTextView {
        MarkdownTextView()
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        let rendered = GFMMarkdownRenderer.attributed(from: content)
        guard view.attributedString() != rendered else { return }
        view.textStorage?.setAttributedString(rendered)
        view.invalidateMeasuredSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownTextView, context: Context) -> CGSize? {
        let width = max(120, proposal.width ?? 680)
        return CGSize(width: width, height: nsView.height(for: width))
    }
}

final class MarkdownTextView: NSTextView {
    private var measuredWidth: CGFloat = 0

    init() {
        let container = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainerInset = NSSize(width: 0, height: 1)
        textContainer?.lineFragmentPadding = 0
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let width = max(120, bounds.width > 0 ? bounds.width : 680)
        return NSSize(width: NSView.noIntrinsicMetric, height: height(for: width))
    }

    override func layout() {
        super.layout()
        let width = bounds.width.rounded(.down)
        guard width > 0, width != measuredWidth else { return }
        measuredWidth = width
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let didChangeWidth = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        guard didChangeWidth else { return }
        measuredWidth = 0
        invalidateIntrinsicContentSize()
    }

    func invalidateMeasuredSize() {
        measuredWidth = 0
        invalidateIntrinsicContentSize()
    }

    func height(for width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layoutManager else { return 1 }
        container.containerSize = NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height
        return ceil(used + textContainerInset.height * 2)
    }
}

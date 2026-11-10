import AppKit
import SwiftUI

struct InlineTaskEditor: NSViewRepresentable {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDetails: () -> Void

    func makeNSView(context: Context) -> InlineTaskTextView {
        let view = InlineTaskTextView(frame: .zero)
        view.isRichText = false
        view.allowsUndo = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        if let container = view.textContainer {
            container.size = NSSize(width: 0, height: 0)
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.lineFragmentPadding = 0
        }
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        view.setAccessibilityLabel("续写任务")
        view.string = text
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: InlineTaskTextView, context: Context) {
        context.coordinator.editor = self
        view.onSave = onSave
        view.onDetails = onDetails
        if view.string != text, !view.hasMarkedText() { view.string = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: InlineTaskTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let editorContainer = view.textContainer else { return nil }

        // SwiftUI can try several widths before placing the editor.
        let storage = NSTextStorage(attributedString: view.attributedString())
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: 0))
        container.lineFragmentPadding = editorContainer.lineFragmentPadding
        container.lineBreakMode = editorContainer.lineBreakMode
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let textHeight = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentUsedRect.maxY)
        return CGSize(width: width, height: max(ceil(textHeight), 18))
    }

    func makeCoordinator() -> Coordinator { Coordinator(editor: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: InlineTaskEditor

        init(editor: InlineTaskEditor) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            editor.text = view.string
        }

        func textView(_ view: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !view.hasMarkedText() else { return false }
            if command == #selector(NSResponder.cancelOperation(_:)) {
                editor.onCancel()
                return true
            }
            if command == #selector(NSResponder.insertNewline(_:)),
               NSApp.currentEvent?.modifierFlags.contains(.shift) != true {
                editor.onSave()
                return true
            }
            return false
        }
    }
}

final class InlineTaskTextView: NSTextView {
    var onSave: (() -> Void)?
    var onDetails: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, window.makeFirstResponder(self) else { return }
            let end = NSRange(location: self.string.utf16.count, length: 0)
            self.setSelectedRange(end)
            self.scrollRangeToVisible(end)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDetails?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder !== self else { return }
            self.onSave?()
        }
        return true
    }
}

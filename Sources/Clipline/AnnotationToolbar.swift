import AppKit

@MainActor final class AnnotationButton: NSButton {
    var pressed: () -> Void
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        pressed = action
        super.init(frame: .zero)
        self.title = title; target = self; self.action = #selector(run)
        bezelStyle = .rounded
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            imagePosition = .imageOnly; isBordered = false
        }
        toolTip = title; setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { pressed() }
}

@MainActor final class AnnotationToolbar: NSView {
    enum Action { case ocr, undo, redo, clear, share, saveAs, copy, close }
    var onTool: ((AnnotationKind) -> Void)?
    var onAction: ((Action) -> Void)?
    private var toolButtons: [AnnotationKind: NSView] = [:]
    private var contentWidth: CGFloat = 0
    private var textTool: AnnotationKind = .text
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        layer?.cornerRadius = 13; layer?.borderWidth = 1; layer?.borderColor = NSColor(white: 0.3, alpha: 1).cgColor
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), scroll.topAnchor.constraint(equalTo: topAnchor, constant: 3), scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)])
        stack.orientation = .horizontal; stack.spacing = 2; stack.alignment = .centerY
        scroll.documentView = stack
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: contentWidth + 12, height: 47) }
    func configure(_ settings: AnnotationEditorSettings) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        toolButtons.removeAll()
        let size: CGFloat = settings.largeToolbar ? 44 : 36
        func append(_ button: NSView) {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: size).isActive = true
            button.heightAnchor.constraint(equalToConstant: size).isActive = true
            (button as? NSButton)?.contentTintColor = .white; stack.addArrangedSubview(button)
        }
        for kind in settings.order where !settings.hidden.contains(kind) {
            if kind == .text {
                let primary = AnnotationButton(L("Text and bubble")) { [weak self] in
                    guard let self else { return }; self.onTool?(self.textTool)
                }
                primary.title = "A"; primary.font = .systemFont(ofSize: 19); primary.isBordered = false; primary.contentTintColor = .white
                let down = AnnotationButton(L("Text variants"), symbol: "chevron.down") { [weak self, weak primary] in
                    guard let self, let primary else { return }
                    let menu = NSMenu()
                    for variant in [AnnotationKind.text, .bubble] {
                        let item = AnnotationMenuItem(variant.title) { [weak self] in self?.textTool = variant; self?.onTool?(variant) }
                        item.state = self.textTool == variant ? .on : .off; menu.addItem(item)
                    }
                    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: primary.bounds.minY), in: primary)
                }
                down.widthAnchor.constraint(equalToConstant: 11).isActive = true; down.contentTintColor = .white
                let slot = NSStackView(views: [primary, down]); slot.spacing = 0
                slot.wantsLayer = true; slot.layer?.cornerRadius = 6; slot.setAccessibilityLabel(L("Text and bubble"))
                toolButtons[kind] = slot; append(slot); continue
            }
            let button = AnnotationButton(kind.title, symbol: kind.symbol) { [weak self] in self?.onTool?(kind) }
            button.wantsLayer = true; button.layer?.cornerRadius = 6
            toolButtons[kind] = button; append(button)
        }
        let actions: [(Action, String, String)] = [(.ocr, L("Recognize text (Option: ddddocr)"), "text.viewfinder"), (.undo, L("Undo"), "arrow.uturn.backward"), (.redo, L("Redo"), "arrow.uturn.forward")]
        for (action, title, symbol) in actions {
            let button = AnnotationButton(title, symbol: symbol) { [weak self] in self?.onAction?(action) }
            if action == .undo { undoButton = button }; if action == .redo { redoButton = button }; append(button)
        }
        let eraser = AnnotationButton(AnnotationKind.eraser.title, symbol: AnnotationKind.eraser.symbol) { [weak self] in self?.onTool?(.eraser) }
        eraser.wantsLayer = true; eraser.layer?.cornerRadius = 6; toolButtons[.eraser] = eraser; append(eraser)
        for (action, title, symbol) in [(Action.clear, L("Clear all"), "trash"), (.share, L("Share"), "square.and.arrow.up"), (.saveAs, L("Save image as"), "square.and.arrow.down"), (.copy, L("Copy image"), "doc.on.doc"), (.close, L("Close"), "xmark")] {
            append(AnnotationButton(title, symbol: symbol) { [weak self] in self?.onAction?(action) })
        }
        contentWidth = CGFloat(stack.arrangedSubviews.count) * (size + 2)
        stack.frame = CGRect(x: 0, y: 0, width: contentWidth, height: size)
        invalidateIntrinsicContentSize()
    }
    func update(tool: AnnotationKind, canUndo: Bool, canRedo: Bool) {
        if tool == .text || tool == .bubble { textTool = tool }
        let selected = tool == .bubble ? .text : tool
        for (kind, button) in toolButtons {
            button.layer?.backgroundColor = (kind == selected ? NSColor.systemBlue : .clear).cgColor
            button.setAccessibilityValue(kind == selected ? 1 : 0)
        }
        undoButton?.isEnabled = canUndo; redoButton?.isEnabled = canRedo
    }
}

@MainActor final class AnnotationPopup: NSPopUpButton {
    var changed: (Int) -> Void
    init(_ titles: [String], selected: Int = 0, action: @escaping (Int) -> Void) {
        changed = action
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: titles); selectItem(at: selected); target = self; self.action = #selector(run)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { changed(indexOfSelectedItem) }
}

@MainActor final class AnnotationField: NSTextField {
    var changed: (String) -> Void
    init(_ text: String, action: @escaping (String) -> Void) {
        changed = action
        super.init(frame: .zero)
        stringValue = text; isEditable = true; isSelectable = true; isBezeled = true; cell?.sendsActionOnEndEditing = true
        target = self; self.action = #selector(run)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor = currentEditor() as? NSTextView, editor.performAnnotationTextCommand(with: event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    @objc private func run() { changed(stringValue) }
}

@MainActor private final class AnnotationMenuItem: NSMenuItem {
    let pressed: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        pressed = action
        super.init(title: title, action: nil, keyEquivalent: "")
        target = self; self.action = #selector(run)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { pressed() }
}

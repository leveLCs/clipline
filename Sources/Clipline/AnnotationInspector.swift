import AppKit

/// A compact native parameter panel. Controls edit either the selected item or the next-tool style.
@MainActor final class AnnotationInspector: NSView {
    var onStyle: ((AnnotationStyle) -> Void)?
    var onText: ((String) -> Void)?
    var onStamp: ((String) -> Void)?
    private var style = AnnotationStyle()
    private var handlers: [ObjectIdentifier: (NSControl) -> Void] = [:]
    private let rows = NSStackView()
    private var current: (UUID?, AnnotationKind)?
    private var currentText = ""
    private var currentStepNumber = 0
    private var updating = false
    private weak var stepPreview: AnnotationStepPreview?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 12; layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 7; rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), rows.topAnchor.constraint(equalTo: topAnchor, constant: 10), rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(kind: AnnotationKind, style: AnnotationStyle, selected: Annotation?, stamp: String, stepNumber: Int = 1, force: Bool = false) {
        guard !updating else { return }
        let text = selected?.text ?? stamp
        // Keep controls during geometry-only changes; external undo/redo must refresh their values.
        if !force, let current, current.0 == selected?.id, current.1 == kind,
           self.style == style, currentText == text, currentStepNumber == stepNumber { return }
        self.style = style; currentText = text; currentStepNumber = stepNumber
        current = (selected?.id, kind)
        rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
        handlers.removeAll()
        if [.hand, .eraser].contains(kind) {
            rows.addArrangedSubview(NSTextField(labelWithString: kind == .hand ? L("Drag to move. Double-click text to edit.") : L("Erase annotations without changing the source image.")))
            return
        }
        if kind == .step {
            slider(L("Annotation size"), key: \.size, range: 12...160)
            let colors = NSStackView(); colors.spacing = 7; colors.alignment = .centerY
            for (title, key) in [(L("Background"), \AnnotationStyle.backgroundColor), (L("Text color"), \AnnotationStyle.textColor)] {
                let well = NSColorWell(); well.color = style[keyPath: key].nsColor
                well.widthAnchor.constraint(equalToConstant: 34).isActive = true; well.heightAnchor.constraint(equalToConstant: 24).isActive = true
                well.setAccessibilityLabel(title)
                bind(well) { [weak self] control in self?.style[keyPath: key] = AnnotationColor((control as! NSColorWell).color); self?.changed() }
                colors.addArrangedSubview(NSTextField(labelWithString: title)); colors.addArrangedSubview(well)
            }
            let preview = AnnotationStepPreview(style: style, number: stepNumber); stepPreview = preview
            preview.widthAnchor.constraint(equalToConstant: 40).isActive = true; preview.heightAnchor.constraint(equalToConstant: 40).isActive = true
            let fields = rows.arrangedSubviews
            fields.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
            let controls = NSStackView(views: fields)
            controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 7; controls.addArrangedSubview(colors)
            rows.addArrangedSubview(NSStackView(views: [controls, preview]))
            return
        }
        if [.rectangle, .ellipse, .line, .arrow, .pen, .highlighter, .bubble, .note, .magnify].contains(kind) {
            slider(L("Width"), key: \.lineWidth, range: 1...40)
            color(L("Color"), key: \.color)
        }
        if [.rectangle, .ellipse].contains(kind) {
            choice(L("Frame style"), values: AnnotationBoxStyle.allCases, labels: [L("Square"), L("Rounded"), L("Dashed"), L("Rounded dashed")], key: \.boxStyle)
            toggle(L("Fill"), key: \.filled)
            slider(L("Corner radius"), key: \.cornerRadius, range: 0...80)
        }
        if kind == .arrow {
            choice(L("Arrow style"), values: AnnotationArrowStyle.allCases, labels: [L("Open"), L("Emphasis"), L("Dashed"), L("Curved")], key: \.arrowStyle)
        }
        if [.text, .bubble].contains(kind) {
            let font = NSPopUpButton()
            let fonts = NSFontManager.shared.availableFontFamilies.sorted()
            font.addItems(withTitles: [L("System font")] + fonts)
            font.selectItem(withTitle: style.fontName.isEmpty ? L("System font") : (NSFont(name: style.fontName, size: style.fontSize)?.familyName ?? style.fontName))
            bind(font) { [weak self] control in
                let popup = control as! NSPopUpButton
                let family = popup.titleOfSelectedItem ?? ""
                self?.style.fontName = popup.indexOfSelectedItem == 0 ? "" : (NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 24)?.fontName ?? family)
                self?.changed()
            }; row(L("Font"), font)
            slider(L("Font size"), key: \.fontSize, range: 8...120)
            color(L("Text color"), key: \.textColor)
            if kind == .bubble { color(L("Background"), key: \.backgroundColor) }
        }
        if kind == .highlighter { slider(L("Opacity"), key: \.opacity, range: 0.05...1) }
        if kind == .pixelate {
            choice(L("Mask mode"), values: AnnotationMaskStyle.allCases, labels: [L("Pixelate"), L("Blur"), L("Solid mask")], key: \.maskStyle)
            slider(L("Pixel size"), key: \.pixelSize, range: 2...80)
            slider(L("Blur radius"), key: \.blurRadius, range: 1...80)
            color(L("Mask color"), key: \.color)
        }
        if kind == .magnify {
            slider(L("Zoom"), key: \.zoom, range: 1...8)
            toggle(L("Link source"), key: \.magnifierLinked)
        }
        if [.step, .stamp, .note].contains(kind) { slider(L("Annotation size"), key: \.size, range: 12...160) }
        if [.step, .note].contains(kind) {
            color(L("Background"), key: \.backgroundColor); color(L("Text color"), key: \.textColor)
        }
        if kind == .stamp {
            let field = NSTextField(string: selected?.text ?? stamp); field.cell?.sendsActionOnEndEditing = true
            field.placeholderString = L("Emoji or symbol"); field.widthAnchor.constraint(equalToConstant: 150).isActive = true
            bind(field) { [weak self] control in
                let text = (control as! NSTextField).stringValue; self?.currentText = text; self?.onStamp?(text)
            }
            row(L("Stamp"), field)
            rows.addArrangedSubview(AnnotationButton(L("Search emoji and symbols"), symbol: nil) { NSApp.orderFrontCharacterPalette(nil) })
        }
        if kind == .spotlight {
            choice(L("Spotlight shape"), values: AnnotationSpotlightShape.allCases, labels: [L("Ellipse"), L("Rectangle")], key: \.spotlightShape)
            slider(L("Corner radius"), key: \.cornerRadius, range: 0...100)
            slider(L("Darkness"), key: \.spotlightDarkness, range: 0...0.95)
        }
        if kind == .note {
            choice(L("Note style"), values: AnnotationNoteStyle.allCases, labels: [L("Solid frame"), L("Dashed frame"), L("Rounded frame"), L("Rounded dashed frame"), L("Solid arrow"), L("Dashed arrow"), L("Curved arrow")], key: \.noteStyle)
            slider(L("Note font size"), key: \.fontSize, range: 8...72)
            if let selected {
                let field = NSTextField(string: selected.text); field.cell?.sendsActionOnEndEditing = true; field.widthAnchor.constraint(equalToConstant: 220).isActive = true
                bind(field) { [weak self] control in
                    let text = (control as! NSTextField).stringValue; self?.currentText = text; self?.onText?(text)
                }
                row(L("Note text"), field)
            }
        }
    }
    private func row(_ title: String, _ control: NSView) {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [label, control]); stack.spacing = 9; stack.alignment = .centerY
        rows.addArrangedSubview(stack); control.setAccessibilityLabel(title)
    }
    private func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        control.target = self; control.action = #selector(controlChanged(_:)); handlers[ObjectIdentifier(control)] = handler
    }
    @objc private func controlChanged(_ sender: NSControl) {
        updating = true
        defer { updating = false }
        handlers[ObjectIdentifier(sender)]?(sender)
    }
    private func changed() { stepPreview?.style = style; stepPreview?.needsDisplay = true; updating = true; onStyle?(style); updating = false }
    private func slider(_ title: String, key: WritableKeyPath<AnnotationStyle, CGFloat>, range: ClosedRange<CGFloat>) {
        func display(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
        let value = NSTextField(labelWithString: display(Double(style[keyPath: key])))
        value.widthAnchor.constraint(equalToConstant: 42).isActive = true
        let slider = NSSlider(value: Double(style[keyPath: key]), minValue: Double(range.lowerBound), maxValue: Double(range.upperBound), target: nil, action: nil)
        slider.isContinuous = false; slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        bind(slider) { [weak self] control in
            guard let self else { return }
            self.style[keyPath: key] = CGFloat(control.doubleValue)
            value.stringValue = display(control.doubleValue); self.changed()
        }
        row(title, NSStackView(views: [slider, value]))
    }
    private func color(_ title: String, key: WritableKeyPath<AnnotationStyle, AnnotationColor>) {
        let well = NSColorWell(); well.color = style[keyPath: key].nsColor
        well.widthAnchor.constraint(equalToConstant: 50).isActive = true; well.heightAnchor.constraint(equalToConstant: 23).isActive = true
        NSColorPanel.shared.showsAlpha = true
        bind(well) { [weak self] control in self?.style[keyPath: key] = AnnotationColor((control as! NSColorWell).color); self?.changed() }
        row(title, well)
    }
    private func toggle(_ title: String, key: WritableKeyPath<AnnotationStyle, Bool>) {
        let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        checkbox.state = style[keyPath: key] ? .on : .off
        bind(checkbox) { [weak self] control in self?.style[keyPath: key] = (control as! NSButton).state == .on; self?.changed() }
        rows.addArrangedSubview(checkbox)
    }
    private func choice<T: Equatable>(_ title: String, values: [T], labels: [String], key: WritableKeyPath<AnnotationStyle, T>) {
        let popup = NSPopUpButton(); popup.addItems(withTitles: labels); popup.selectItem(at: values.firstIndex(of: style[keyPath: key]) ?? 0)
        bind(popup) { [weak self] control in self?.style[keyPath: key] = values[(control as! NSPopUpButton).indexOfSelectedItem]; self?.changed() }
        row(title, popup)
    }
}

@MainActor private final class AnnotationStepPreview: NSView {
    var style: AnnotationStyle
    let number: Int
    init(style: AnnotationStyle, number: Int) {
        self.style = style; self.number = number; super.init(frame: .zero)
        setAccessibilityLabel(L("Step preview"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        style.backgroundColor.nsColor.setFill(); circle.fill()
        style.textColor.nsColor.setStroke(); circle.lineWidth = 2; circle.stroke()
        let text = String(number) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: style.textColor.nsColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

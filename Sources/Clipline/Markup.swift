import AppKit
import UniformTypeIdentifiers

/// One native annotation session. The original is touched only by an explicit Save.
@MainActor final class Markup: NSObject, NSWindowDelegate {
    static let shared = Markup()
    var onSaved: (URL) -> Void = { _ in }
    private var document: AnnotationDocument?
    private var canvas: AnnotationCanvas?
    private var window: NSWindow?
    private var toolbar: AnnotationToolbar?
    private var inspector: AnnotationInspector?
    private var dimensions: NSButton?
    private var status: NSTextField?
    private var settings = AnnotationEditorSettings()
    private var session = UUID()
    private var recognitionID = UUID()
    private var recognition: Task<Void, Never>?
    private var dddd: DdddOCR?
    private var auxiliary: [NSWindow] = []
    private var notesWindow: NSWindow?
    private var sharingPicker: NSSharingServicePicker?
    private var applyingStyle = false

    func edit(_ url: URL) {
        if document?.sourceURL?.standardizedFileURL == url.standardizedFileURL {
            window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        guard requestClose() else { return }
        do {
            let document = try AnnotationDocument(url: url)
            self.document = document; session = UUID()
            buildWindow(document)
        } catch { showError(error) }
    }

    /// Used by the close button, Escape, switching files, and application termination.
    @discardableResult func requestClose() -> Bool {
        guard let document else { return true }
        commitPendingEdits()
        if document.isDirty {
            let alert = NSAlert(); alert.messageText = L("Keep annotation changes?")
            alert.informativeText = L("Save changes to the original image, discard them, or keep editing.")
            alert.addButton(withTitle: L("Save changes")); alert.addButton(withTitle: L("Discard changes")); alert.addButton(withTitle: L("Cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: return finish()
            case .alertSecondButtonReturn: break
            default: return false
            }
        }
        dispose(); return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window { _ = requestClose(); return false }
        return true
    }
    private func commitPendingEdits() {
        Self.commitPendingEdits(canvas: canvas, windows: [window].compactMap { $0 } + auxiliary)
        window?.makeFirstResponder(canvas)
    }
    static func commitPendingEdits(canvas: AnnotationCanvas?, windows: [NSWindow]) {
        // Auxiliary note windows have their own field editors, independent of the canvas window.
        for window in windows { window.makeFirstResponder(nil) }
        canvas?.finishTextEditing()
    }
    private func dispose() {
        cancelRecognition(); session = UUID()
        auxiliary.forEach { $0.close() }; auxiliary.removeAll(); notesWindow = nil
        window?.delegate = nil; window?.close(); window = nil
        canvas = nil; document = nil; toolbar = nil; inspector = nil; dimensions = nil; status = nil; sharingPicker = nil
    }
    @discardableResult private func finish() -> Bool {
        guard let document, let url = document.sourceURL else { return false }
        commitPendingEdits()
        do { try document.saveOriginal(); dispose(); onSaved(url); return true }
        catch { showError(error); return false }
    }
    private func buildWindow(_ document: AnnotationDocument) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 900)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: min(1500, screen.width - 40), height: min(900, screen.height - 40)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("Markup") + " — " + (document.sourceURL?.lastPathComponent ?? "")
        window.appearance = NSAppearance(named: .darkAqua); window.backgroundColor = NSColor(white: 0.095, alpha: 1)
        window.minSize = NSSize(width: 720, height: 620); window.isReleasedWhenClosed = false; window.delegate = self
        self.window = window
        let content = window.contentView!
        let canvas = AnnotationCanvas(document: document); self.canvas = canvas
        canvas.contentInsets = NSEdgeInsets(top: 55, left: 24, bottom: 340, right: 24)
        canvas.clickCreatesShapes = settings.clickCreatesShapes
        canvas.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(canvas)
        NSLayoutConstraint.activate([canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor), canvas.topAnchor.constraint(equalTo: content.topAnchor), canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        let tools = AnnotationToolbar(); toolbar = tools; tools.configure(settings)
        tools.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([tools.heightAnchor.constraint(equalToConstant: settings.largeToolbar ? 55 : 47)])
        let inspector = AnnotationInspector(); self.inspector = inspector
        inspector.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(inspector)
        let dimensions = AnnotationButton("") { [weak self] in self?.showCrop() }; self.dimensions = dimensions
        let header = NSStackView(views: [
            AnnotationButton(L("Hand tool"), symbol: "hand.draw") { [weak self] in self?.selectTool(.hand) },
            AnnotationButton(L("Notes overview"), symbol: "note.text") { [weak self] in self?.showNotes() },
            AnnotationButton(L("Detect QR codes"), symbol: "qrcode.viewfinder") { [weak self] in self?.recognize(qr: true) },
            AnnotationButton(L("Fit image"), symbol: "arrow.up.left.and.arrow.down.right") { [weak self] in self?.canvas?.fit() }
        ])
        header.spacing = 12; header.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(header)
        let finish = AnnotationButton(L("Finish and save to original"), symbol: "pin.fill") { [weak self] in _ = self?.finish() }
        let close = AnnotationButton(L("Close"), symbol: "xmark") { [weak self] in _ = self?.requestClose() }
        let preferences = AnnotationButton(L("Editor settings"), symbol: "slider.horizontal.3") { [weak self] in self?.showSettings() }
        let ending = NSStackView(views: [dimensions, preferences, finish]); ending.spacing = 14
        ending.wantsLayer = true; ending.layer?.cornerRadius = 13; ending.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        ending.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        ending.translatesAutoresizingMaskIntoConstraints = false
        let barGroup = NSStackView(views: [tools, ending]); barGroup.spacing = 10; barGroup.alignment = .centerY
        barGroup.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(barGroup)
        NSLayoutConstraint.activate([inspector.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 8), inspector.centerXAnchor.constraint(equalTo: content.centerXAnchor), inspector.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -40)])
        tools.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        ending.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([barGroup.centerXAnchor.constraint(equalTo: content.centerXAnchor), barGroup.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 20), barGroup.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20), barGroup.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -290), tools.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)])
        close.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(close)
        let status = NSTextField(labelWithString: document.restorationNotice ?? ""); self.status = status; status.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(status)
        let cancel = AnnotationButton(L("Cancel recognition"), symbol: "stop.circle") { [weak self] in self?.cancelRecognition() }
        cancel.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(cancel)
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22), header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22), close.centerYAnchor.constraint(equalTo: header.centerYAnchor), status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22), status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10), cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22), cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)])
        dimensions.setAccessibilityLabel(L("Crop and image dimensions"))
        tools.onTool = { [weak self] in self?.selectTool($0) }
        tools.onAction = { [weak self] in self?.perform($0) }
        inspector.onStyle = { [weak self] style in
            guard let self, let canvas = self.canvas else { return }
            let kind = canvas.selectedAnnotation?.kind ?? canvas.tool
            self.settings.styles[kind] = style; self.settings.save()
            self.applyingStyle = true; canvas.applyStyle(style); self.applyingStyle = false
        }
        inspector.onText = { [weak canvas] in canvas?.updateSelectedText($0) }
        inspector.onStamp = { [weak canvas] value in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            canvas?.stampText = value
            if canvas?.selectedAnnotation?.kind == .stamp { canvas?.updateSelectedText(value) }
        }
        canvas.onSelectionChanged = { [weak self] _ in self?.refreshInspector() }
        canvas.onDocumentChanged = { [weak self] in self?.refresh() }
        canvas.onFinish = { [weak self] in _ = self?.finish() }
        canvas.onCancel = { [weak self] in _ = self?.requestClose() }
        canvas.onCopy = { [weak self] in self?.copyImage() }
        canvas.onOCR = { [weak self] in self?.recognize(qr: false) }
        canvas.onError = { [weak self] in self?.showError($0) }
        selectTool(settings.lastTool); refresh()
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func selectTool(_ kind: AnnotationKind) {
        guard let canvas else { return }
        canvas.selectTool(kind); canvas.style = settings.style(for: kind)
        settings.lastTool = kind; settings.save(); refresh(); refreshInspector(force: true)
    }
    private func refresh() {
        guard let canvas, let document else { return }
        toolbar?.update(tool: canvas.tool, canUndo: document.canUndo, canRedo: document.canRedo)
        let crop = document.state.crop ?? CGRect(x: 0, y: 0, width: document.source.width, height: document.source.height)
        dimensions?.title = "\(Int(crop.width)) × \(Int(crop.height)) ▾"
        window?.isDocumentEdited = document.isDirty
    }
    private func refreshInspector(force: Bool = false) {
        guard !applyingStyle, let canvas else { return }
        let item = canvas.selectedAnnotation
        inspector?.configure(kind: item?.kind ?? canvas.tool, style: item?.style ?? canvas.style, selected: item, stamp: canvas.stampText, stepNumber: item.flatMap { document?.state.stepNumber(for: $0.id) } ?? ((document?.state.annotations.filter { $0.kind == .step }.count ?? 0) + 1), force: force)
    }
    private func perform(_ action: AnnotationToolbar.Action) {
        commitPendingEdits()
        switch action {
        case .ocr: recognize(qr: false)
        case .undo: canvas?.undo(); refreshInspector(force: true)
        case .redo: canvas?.redo(); refreshInspector(force: true)
        case .clear:
            canvas?.finishTextEditing()
            if let document { var next = document.state; next.annotations = []; document.commit(state: next, label: L("Clear all")) }
        case .share: share()
        case .saveAs: saveAs()
        case .copy: copyImage()
        case .close: _ = requestClose()
        }
    }
    private func rendered(includeNotes: Bool = true) throws -> CGImage {
        commitPendingEdits()
        guard let document else { throw AnnotationFailure.noSource }
        return try document.render(includeNotes: includeNotes)
    }
    private func copyImage() {
        do {
            let data = try AnnotationRenderer.encode(rendered(), type: UTType.png.identifier)
            let item = NSPasteboardItem(); item.setData(data, forType: .png)
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([item]); status?.stringValue = L("Image copied")
        } catch { showError(error) }
    }
    private func share() {
        do {
            let image = try rendered(); let item = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            let picker = NSSharingServicePicker(items: [item]); sharingPicker = picker
            if let toolbar { picker.show(relativeTo: toolbar.bounds, of: toolbar, preferredEdge: .maxY) }
        } catch { showError(error) }
    }
    private func saveAs() {
        guard let document, window != nil else { return }
        commitPendingEdits()
        let panel = NSSavePanel(); panel.title = L("Save image as"); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (document.sourceURL?.deletingPathExtension().lastPathComponent ?? L("Annotated image")) + "-annotated.png"
        let format = AnnotationPopup(["PNG", "JPEG"]) { [weak panel] index in
            if let panel { Self.configureExportPanel(panel, type: index == 0 ? .png : .jpeg) }
        }
        panel.accessoryView = format
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            if let original = document.sourceURL {
                if Self.isOriginalDestination(target, source: original) {
                    let alert = NSAlert(); alert.messageText = L("Choose a different file")
                    alert.informativeText = L("Use Finish and save to original to safely replace the original image."); alert.runModal(); return
                }
            }
            let data = try document.encodedData(type: format.indexOfSelectedItem == 0 ? UTType.png.identifier : UTType.jpeg.identifier)
            try data.write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            status?.stringValue = L("Image saved")
        } catch { showError(error) }
    }
    static func configureExportPanel(_ panel: NSSavePanel, type: UTType) {
        panel.allowedContentTypes = [type]
        let name = URL(fileURLWithPath: panel.nameFieldStringValue)
        if UTType(filenameExtension: name.pathExtension)?.conforms(to: type) != true,
           let suffix = type.preferredFilenameExtension {
            panel.nameFieldStringValue = name.deletingPathExtension().lastPathComponent + "." + suffix
        }
    }
    static func isOriginalDestination(_ target: URL, source: URL) -> Bool {
        if target.resolvingSymlinksInPath().standardizedFileURL == source.resolvingSymlinksInPath().standardizedFileURL { return true }
        guard let original = try? FileVersion.read(source), let destination = try? FileVersion.read(target) else { return false }
        return original.device == destination.device && original.inode == destination.inode
    }
    private func cancelRecognition() {
        recognitionID = UUID(); recognition?.cancel(); recognition = nil; dddd?.cancel(); dddd = nil
        status?.stringValue = ""
    }
    private func recognize(qr: Bool) {
        do {
            let image = try rendered(includeNotes: false)
            cancelRecognition(); let id = recognitionID, session = session
            let alternative = !qr && NSEvent.modifierFlags.contains(.option)
            let worker = alternative ? DdddOCR() : nil; dddd = worker
            status?.stringValue = qr ? L("Detecting QR codes…") : L("Recognizing text…")
            // shortcut: synchronous Vision may finish after cancel; replace its request API if stopping CPU work becomes necessary.
            recognition = Task { [weak self] in
                do {
                    if qr {
                        let result = try await Task.detached(priority: .userInitiated) { try AnnotationRecognition.qr(image) }.value
                        guard !Task.isCancelled, let self, self.session == session, self.recognitionID == id else { return }
                        self.status?.stringValue = ""; self.showQR(result, image: image)
                    } else {
                        let result = try await Task.detached(priority: .userInitiated) { try worker?.recognize(image) ?? (alternative ? nil : TextRecognition.recognize(image)) }.value
                        guard !Task.isCancelled, let self, self.session == session, self.recognitionID == id else { return }
                        self.status?.stringValue = ""; self.showText(result)
                    }
                } catch {
                    guard !Task.isCancelled, let self, self.session == session, self.recognitionID == id else { return }
                    self.status?.stringValue = ""; self.showError(error)
                }
            }
        } catch { showError(error) }
    }
    private func showText(_ text: String?) {
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 12
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        let view = NSTextView(); view.isEditable = false; view.isSelectable = true; view.font = .systemFont(ofSize: 16)
        view.string = text ?? L("No text found. The clipboard was not changed.")
        scroll.documentView = view; view.isVerticallyResizable = true; view.textContainer?.widthTracksTextView = true
        scroll.widthAnchor.constraint(equalToConstant: 520).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        rows.addArrangedSubview(scroll)
        let copy = AnnotationButton(L("Copy text")) { _ = TextRecognition.copy(text) }; copy.isEnabled = text?.isEmpty == false
        rows.addArrangedSubview(copy); showPanel(L("Recognized text"), content: rows)
    }
    private func showQR(_ codes: [AnnotationQRCode], image: CGImage) {
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 10
        let preview = AnnotationQRPreview(image: image, codes: codes)
        preview.widthAnchor.constraint(equalToConstant: 520).isActive = true; preview.heightAnchor.constraint(equalToConstant: 280).isActive = true
        rows.addArrangedSubview(preview)
        let hints = AnnotationButton(L("Show QR hints")) { [weak preview] in preview?.showsHints.toggle(); preview?.needsDisplay = true }
        hints.setButtonType(.switch); hints.state = .on; rows.addArrangedSubview(hints)
        if codes.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString: L("No QR codes found."))) }
        for code in codes {
            let text = NSTextField(wrappingLabelWithString: code.text); text.isSelectable = true
            text.widthAnchor.constraint(equalToConstant: 420).isActive = true
            rows.addArrangedSubview(NSStackView(views: [text, AnnotationButton(L("Copy")) { _ = TextRecognition.copy(code.text) }]))
        }
        showPanel(L("QR results"), content: rows)
    }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = L("Annotation failed"); alert.informativeText = error.localizedDescription
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
    @discardableResult private func showPanel(_ title: String, content: NSView) -> NSWindow {
        let panel = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.appearance = NSAppearance(named: .darkAqua); panel.isReleasedWhenClosed = false
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        panel.contentView = scroll
        let wrapper = NSView(); content.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16), content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16)])
        wrapper.frame = CGRect(origin: .zero, size: NSSize(width: max(500, content.fittingSize.width + 32), height: content.fittingSize.height + 32)); scroll.documentView = wrapper
        panel.setContentSize(NSSize(width: min(650, wrapper.frame.width), height: min(620, wrapper.frame.height)))
        auxiliary.append(panel); window?.addChildWindow(panel, ordered: .above); panel.center(); panel.makeKeyAndOrderFront(nil)
        return panel
    }
    private func showCrop() {
        guard let document, let canvas else { return }
        canvas.finishTextEditing(); canvas.isCropping = true; canvas.selectedID = nil
        let source = CGRect(x: 0, y: 0, width: document.source.width, height: document.source.height)
        let current = document.state.crop ?? source
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 10
        rows.addArrangedSubview(NSTextField(wrappingLabelWithString: L("Crop uses source pixels. Presets shrink to fit; images are never upscaled.")))
        var fields: [NSTextField] = []
        for (title, number) in [(L("X"), current.minX), (L("Y"), current.minY), (L("Crop width"), current.width), (L("Height"), current.height)] {
            let field = NSTextField(string: String(Int(number))); field.setAccessibilityLabel(title); field.widthAnchor.constraint(equalToConstant: 100).isActive = true
            fields.append(field); rows.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: title), field]))
        }
        rows.addArrangedSubview(AnnotationButton(L("Apply crop")) { [weak self, weak canvas] in
            let values = fields.compactMap { Double($0.stringValue) }
            guard values.count == 4, values.allSatisfy(\.isFinite), values[2] >= 1, values[3] >= 1 else { self?.showError(AnnotationFailure.invalidGeometry); return }
            let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3]).intersection(source)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { self?.showError(AnnotationFailure.invalidGeometry); return }
            canvas?.setCrop(rect.integral.intersection(source))
        })
        for (title, ratio) in [("1:1", CGFloat(1)), ("4:3", 4 / CGFloat(3)), ("16:9", 16 / CGFloat(9))] {
            rows.addArrangedSubview(AnnotationButton(title) { [weak canvas] in canvas?.setCrop(AnnotationEditorSettings.crop(ratio: ratio, in: current)) })
        }
        for size in [CGSize(width: 640, height: 480), CGSize(width: 1280, height: 720), CGSize(width: 1920, height: 1080)] {
            rows.addArrangedSubview(AnnotationButton("\(Int(size.width)) × \(Int(size.height))") { [weak canvas] in canvas?.setCrop(AnnotationEditorSettings.crop(size: size, in: source)) })
        }
        rows.addArrangedSubview(AnnotationButton(L("Reset crop")) { [weak canvas] in canvas?.setCrop(nil) })
        showPanel(L("Crop image"), content: rows)
    }
    private func showNotes() {
        commitPendingEdits()
        if let notesWindow, notesWindow.isVisible { notesWindow.orderOut(nil); return }
        notesWindow?.close()
        guard let document else { return }
        canvas?.finishTextEditing()
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 10
        let notes = document.state.annotations.filter { $0.kind == .note }
        if notes.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString: L("Draw a note to add an entry."))) }
        for (index, note) in notes.enumerated() {
            let text = AnnotationField(note.text) { [weak self] value in
                guard let self, let canvas = self.canvas, self.document?.state.annotations.contains(where: { $0.id == note.id }) == true else { return }
                canvas.selectedID = note.id; canvas.updateSelectedText(value)
            }
            text.widthAnchor.constraint(equalToConstant: 380).isActive = true
            text.setAccessibilityLabel(L("Note text"))
            let select = AnnotationButton("\(index + 1)") { [weak self] in
                self?.canvas?.selectTool(.hand); self?.canvas?.selectedID = note.id
                self?.window?.makeKeyAndOrderFront(nil); self?.canvas?.editSelectedText()
            }
            rows.addArrangedSubview(NSStackView(views: [select, text]))
        }
        rows.addArrangedSubview(NSTextField(wrappingLabelWithString: L("Press Return to keep each note edit. Notes are included once below the exported image.")))
        notesWindow = showPanel(L("Notes overview"), content: rows)
    }
    private func showSettings() {
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 9
        let size = AnnotationPopup([L("Small toolbar"), L("Large toolbar")], selected: settings.largeToolbar ? 1 : 0) { [weak self] index in self?.settings.largeToolbar = index == 1; self?.applySettings() }
        rows.addArrangedSubview(size)
        let click = AnnotationButton(L("Create shapes with a click")) { [weak self] in
            guard let self else { return }; self.settings.clickCreatesShapes.toggle(); self.applySettings()
        }
        click.setButtonType(.switch); click.state = settings.clickCreatesShapes ? .on : .off; rows.addArrangedSubview(click)
        rows.addArrangedSubview(NSTextField(labelWithString: L("Visible tools and order")))
        let order = NSStackView(); order.orientation = .vertical; order.alignment = .leading; order.spacing = 5; rows.addArrangedSubview(order)
        fillOrder(order)
        rows.addArrangedSubview(AnnotationButton(L("Reset editor settings")) { [weak self, weak order] in
            guard let self else { return }
            self.settings = AnnotationEditorSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            self.applySettings(); if let order { self.fillOrder(order) }
            size.selectItem(at: 0); click.state = .on; self.selectTool(.rectangle)
        })
        showPanel(L("Editor settings"), content: rows)
    }
    private func fillOrder(_ stack: NSStackView) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, kind) in settings.order.enumerated() {
            let visible = AnnotationButton(kind == .text ? L("Text and bubble") : kind.title) { [weak self] in
                guard let self else { return }
                if self.settings.hidden.contains(kind) { self.settings.hidden.remove(kind) } else { self.settings.hidden.insert(kind) }
                self.applySettings()
            }
            visible.setButtonType(.switch); visible.state = settings.hidden.contains(kind) ? .off : .on
            let up = AnnotationButton(L("Move tool earlier"), symbol: "chevron.up") { [weak self, weak stack] in
                guard let self, index > 0 else { return }; self.settings.order.swapAt(index, index - 1); self.applySettings(); if let stack { self.fillOrder(stack) }
            }; up.isEnabled = index > 0
            let down = AnnotationButton(L("Move tool later"), symbol: "chevron.down") { [weak self, weak stack] in
                guard let self, index + 1 < self.settings.order.count else { return }; self.settings.order.swapAt(index, index + 1); self.applySettings(); if let stack { self.fillOrder(stack) }
            }; down.isEnabled = index + 1 < settings.order.count
            stack.addArrangedSubview(NSStackView(views: [visible, up, down]))
        }
    }
    private func applySettings() {
        settings.save(); canvas?.clickCreatesShapes = settings.clickCreatesShapes
        toolbar?.configure(settings)
        toolbar?.constraints.first(where: { $0.firstAttribute == .height && $0.secondItem == nil })?.constant = settings.largeToolbar ? 55 : 47
        refresh()
    }
}

@MainActor private final class AnnotationQRPreview: NSView {
    let image: NSImage
    let codes: [AnnotationQRCode]
    var showsHints = true
    init(image: CGImage, codes: [AnnotationQRCode]) {
        self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)); self.codes = codes
        super.init(frame: .zero); setAccessibilityLabel(L("QR preview"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let rect = CGRect(x: (bounds.width - image.size.width * scale) / 2, y: (bounds.height - image.size.height * scale) / 2, width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: rect)
        if showsHints {
            NSColor.systemGreen.setStroke()
            for code in codes {
                let r = code.bounds
                let path = NSBezierPath(rect: CGRect(x: rect.minX + r.minX * rect.width, y: rect.minY + r.minY * rect.height, width: r.width * rect.width, height: r.height * rect.height))
                path.lineWidth = 3; path.stroke()
            }
        }
    }
}

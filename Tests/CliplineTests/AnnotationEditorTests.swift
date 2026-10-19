import AppKit
import CoreImage
import Vision

@main struct AnnotationEditorTests {
    @MainActor static func main() throws {
        let suite = "Clipline.AnnotationChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AnnotationEditorSettings(defaults: defaults)
        assert(settings.style(for: .step).backgroundColor == .red)
        assert(settings.style(for: .step).textColor == .white)
        assert(settings.style(for: .highlighter).color != .red)
        settings.order = [.note, .note, .hand, .rectangle]
        settings.hidden = [.note]; settings.lastTool = .hand
        settings.largeToolbar = true; settings.clickCreatesShapes = false
        var style = settings.style(for: .magnify); style.zoom = 3.5
        settings.styles[.magnify] = style; settings.save(to: defaults)
        settings = AnnotationEditorSettings(defaults: defaults)
        assert(settings.order.first == .note && Set(settings.order).count == settings.order.count)
        assert(!settings.order.contains(.hand) && settings.order.count == AnnotationEditorSettings.tools.count)
        assert(settings.hidden == [.note] && settings.lastTool == .hand && settings.largeToolbar && !settings.clickCreatesShapes)
        assert(settings.style(for: .magnify).zoom == 3.5)
        let crop = AnnotationEditorSettings.crop(size: CGSize(width: 1920, height: 1080), in: CGRect(x: 0, y: 0, width: 800, height: 600))
        assert(crop.width == 800 && crop.height == 450 && crop.minY == 75)
        let ratio = AnnotationEditorSettings.crop(ratio: 1, in: CGRect(x: 20, y: 30, width: 300, height: 200))
        assert(ratio == CGRect(x: 70, y: 30, width: 200, height: 200))
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("CLIPLINE-ANNOTATION-QA".utf8), forKey: "inputMessage")
        let qr = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let image = CIContext().createCGImage(qr, from: qr.extent)!
        let results = try AnnotationRecognition.qr(image)
        assert(results.count == 1 && results[0].text == "CLIPLINE-ANNOTATION-QA")
        assert(results[0].bounds.width > 0 && results[0].bounds.minX >= 0)
        _ = NSApplication.shared
        let inspector = AnnotationInspector()
        var editedStyle: AnnotationStyle?
        inspector.onStyle = { editedStyle = $0 }
        inspector.configure(kind: .step, style: settings.style(for: .step), selected: nil, stamp: "", stepNumber: 7)
        inspector.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let controls = descendants(inspector)
        let wells = controls.compactMap { $0 as? NSColorWell }
        assert(wells.count == 2 && controls.filter { $0 is NSSlider }.count == 1)
        assert(inspector.fittingSize.height < 100 && inspector.fittingSize.width < 400)
        wells[0].color = NSColor(displayP3Red: 0.8, green: 0.2, blue: 0.1, alpha: 0.7)
        wells[0].sendAction(wells[0].action, to: wells[0].target)
        assert(editedStyle?.backgroundColor.space == .displayP3 && editedStyle?.backgroundColor.alpha == 0.7)
        assert(editedStyle?.textColor == .white)
        // Drive the same Canvas keyboard route as Cmd-Z, without showing a window or posting system events.
        let history = AnnotationDocument(image: image)
        let rectangle = Annotation(kind: .rectangle, rect: CGRect(x: 10, y: 10, width: 60, height: 40))
        history.commit(state: AnnotationState(annotations: [rectangle]), label: "Fixture")
        let historyCanvas = AnnotationCanvas(document: history)
        historyCanvas.selectTool(.hand); historyCanvas.selectedID = rectangle.id
        let historyInspector = AnnotationInspector()
        func refreshInspector() {
            let item = historyCanvas.selectedAnnotation!
            historyInspector.configure(kind: item.kind, style: item.style, selected: item, stamp: "")
        }
        historyCanvas.onSelectionChanged = { item in if item != nil { refreshInspector() } }
        historyInspector.onStyle = { historyCanvas.applyStyle($0) }
        refreshInspector()
        let widthSlider = descendants(historyInspector).compactMap { $0 as? NSSlider }.first!
        widthSlider.doubleValue = 18; widthSlider.sendAction(widthSlider.action, to: widthSlider.target)
        let colorWell = descendants(historyInspector).compactMap { $0 as? NSColorWell }.first!
        colorWell.color = .blue; colorWell.sendAction(colorWell.action, to: colorWell.target)
        let undoKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        let redoKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        var regressions = 0
        func check(_ condition: Bool, _ label: String) { if !condition { regressions += 1; print("FAIL " + label) } }
        assert(historyCanvas.performKeyEquivalent(with: undoKey))
        check(AnnotationColor(descendants(historyInspector).compactMap { $0 as? NSColorWell }.first!.color) == .red, "keyboard undo refreshes same-object color well")
        assert(historyCanvas.performKeyEquivalent(with: undoKey))
        check(descendants(historyInspector).compactMap { $0 as? NSSlider }.first!.doubleValue == 4, "keyboard undo refreshes same-object width slider")
        assert(historyCanvas.performKeyEquivalent(with: redoKey))
        check(descendants(historyInspector).compactMap { $0 as? NSSlider }.first!.doubleValue == 18, "keyboard redo refreshes same-object width slider")
        let note = Annotation(kind: .note, rect: CGRect(x: 10, y: 10, width: 60, height: 40), text: "Original note")
        history.commit(state: AnnotationState(annotations: [note]), label: "Note fixture")
        historyCanvas.selectedID = note.id
        historyInspector.onText = { historyCanvas.updateSelectedText($0) }
        let changedNoteField = descendants(historyInspector).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        changedNoteField.stringValue = "Changed note"; changedNoteField.sendAction(changedNoteField.action, to: changedNoteField.target)
        assert(historyCanvas.performKeyEquivalent(with: undoKey))
        let noteField = descendants(historyInspector).compactMap { $0 as? NSTextField }.first { $0.isEditable }
        check(noteField?.stringValue == "Original note", "keyboard undo refreshes same-object note field")
        // The notes overview owns a separate native field editor; no Return/action is sent here.
        let mainWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        let notesWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 120), styleMask: .borderless, backing: .buffered, defer: false)
        let noteURL = FileManager.default.temporaryDirectory.appendingPathComponent("annotation-notes-\(UUID().uuidString).png")
        try AnnotationRenderer.encode(image).write(to: noteURL)
        defer { try? FileManager.default.removeItem(at: noteURL) }
        let noteDocument = try AnnotationDocument(url: noteURL)
        noteDocument.commit(state: AnnotationState(annotations: [note]), label: "Saved note fixture")
        try noteDocument.saveOriginal()
        assert(!noteDocument.isDirty)
        let noteCanvas = AnnotationCanvas(document: noteDocument)
        mainWindow.contentView = noteCanvas
        let overviewField = AnnotationField(note.text) { value in
            noteCanvas.selectedID = note.id; noteCanvas.updateSelectedText(value)
        }
        overviewField.frame = CGRect(x: 10, y: 10, width: 350, height: 30)
        notesWindow.contentView!.addSubview(overviewField)
        defer { mainWindow.contentView = nil; notesWindow.contentView = nil }
        overviewField.selectText(nil)
        let pending = overviewField.currentEditor() as! NSTextView
        pending.insertText("Pending overview text without Return", replacementRange: NSRange(location: 0, length: pending.string.utf16.count))
        assert(noteDocument.state.annotations[0].text == "Original note" && !noteDocument.isDirty)
        Markup.commitPendingEdits(canvas: noteCanvas, windows: [mainWindow, notesWindow])
        check(noteDocument.state.annotations[0].text == "Pending overview text without Return", "output preparation commits the auxiliary field editor")
        let output = try noteDocument.render()
        var expectedNote = note; expectedNote.text = "Pending overview text without Return"
        let expected = try AnnotationRenderer.render(source: noteDocument.source, state: AnnotationState(annotations: [expectedNote]))
        check(output.width == expected.width && output.height == expected.height && (output.dataProvider!.data! as Data) == (expected.dataProvider!.data! as Data), "render includes the unsubmitted overview text")
        try noteDocument.saveOriginal()
        assert(!noteDocument.isDirty)
        let savedBytes = try Data(contentsOf: noteURL), expectedBytes = try noteDocument.encodedData()
        assert(savedBytes == expectedBytes)
        overviewField.selectText(nil)
        let closing = overviewField.currentEditor() as! NSTextView
        closing.insertText("Pending close text", replacementRange: NSRange(location: 0, length: closing.string.utf16.count))
        Markup.commitPendingEdits(canvas: noteCanvas, windows: [mainWindow, notesWindow])
        check(noteDocument.isDirty && noteDocument.state.annotations[0].text == "Pending close text", "close preparation includes auxiliary changes before dirty evaluation")
        if regressions > 0 { exit(1) }
        print("PASS pending overview text reaches rendered/saved output and dirty close; keyboard undo/redo refreshes inspector")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original.png")
        let hardlink = folder.appendingPathComponent("hardlink.png")
        let symlink = folder.appendingPathComponent("symlink.png")
        let copy = folder.appendingPathComponent("copy.png")
        try Data("source".utf8).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardlink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        try Data("source".utf8).write(to: copy)
        assert(Markup.isOriginalDestination(original, source: original))
        assert(Markup.isOriginalDestination(hardlink, source: original))
        assert(Markup.isOriginalDestination(symlink, source: original))
        assert(!Markup.isOriginalDestination(copy, source: original))
        assert(!Markup.isOriginalDestination(folder.appendingPathComponent("new.png"), source: original))
        print("PASS persisted tool settings, defaults, clamped crops and real Vision QR and original-file aliases; compact native Step controls preserve P3")
    }
}

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

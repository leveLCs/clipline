import AppKit
import CoreImage
import UniformTypeIdentifiers

@main struct AnnotationHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = HarnessDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(labelWithString: "Saved callbacks: 0")
    private var saves = 0
    private let folder = Bundle.main.bundleURL.deletingLastPathComponent()
    private var fixture: URL { folder.appendingPathComponent("annotation-fixture.png") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        do { if !FileManager.default.fileExists(atPath: fixture.path) { try makeFixture() } } catch { status.stringValue = error.localizedDescription }
        Markup.shared.onSaved = { [weak self] url in
            guard let self else { return }; self.saves += 1
            self.status.stringValue = "Saved callbacks: \(self.saves) — \(url.lastPathComponent)"
        }
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 220), styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Clipline Annotation QA Launcher"; window.isReleasedWhenClosed = false
        let rows = NSStackView(views: [
            NSTextField(labelWithString: "Clipline 標記編輯器 · Native QA"),
            AnnotationButton("Open Test Image / 開啟測試圖片") { [weak self] in guard let self else { return }; Markup.shared.edit(self.fixture) },
            AnnotationButton("Reset Generated Fixture / 重建測試圖片") { [weak self] in
                guard let self, Markup.shared.requestClose() else { return }
                do { try self.makeFixture(); self.status.stringValue = "Fixture reset. Saved callbacks: \(self.saves)" }
                catch { self.status.stringValue = error.localizedDescription }
            }, status,
            NSTextField(wrappingLabelWithString: fixture.path)
        ])
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 12; rows.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(rows)
        NSLayoutConstraint.activate([rows.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20), rows.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20), rows.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        print("HARNESS fixture=\(fixture.path)")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { Markup.shared.requestClose() ? .terminateNow : .terminateCancel }
    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Annotation QA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
    private func makeFixture() throws {
        let image = NSImage(size: NSSize(width: 1200, height: 800))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
        for y in 0..<12 { for x in 0..<36 {
            (x + y).isMultiple(of: 2) ? NSColor.black.setFill() : NSColor.white.setFill()
            NSRect(x: 40 + x * 15, y: 100 + y * 15, width: 15, height: 15).fill()
        } }
        let lines = [("CLIPLINE ANNOTATION QA", 700, 44), ("標記測試：繁體中文與 English", 620, 36), ("Invoice 0123456789  998877665544", 545, 30), ("Crop • Draw • Mask • Notes • OCR", 475, 28)]
        for (line, y, size) in lines {
            (line as NSString).draw(at: CGPoint(x: 50, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(size)), .foregroundColor: NSColor.black])
        }
        NSColor.systemRed.setFill(); NSRect(x: 50, y: 330, width: 150, height: 70).fill()
        NSColor.systemGreen.setFill(); NSRect(x: 220, y: 330, width: 150, height: 70).fill()
        NSColor.systemBlue.setFill(); NSRect(x: 390, y: 330, width: 150, height: 70).fill()
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("CLIPLINE-ANNOTATION-QA".utf8), forKey: "inputMessage")
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let cg = CIContext().createCGImage(code, from: code.extent)!
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)).draw(in: CGRect(x: 800, y: 100, width: 300, height: 300))
        ("Safe generated QR payload" as NSString).draw(at: CGPoint(x: 770, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { throw AnnotationFailure.renderFailed }
        try png.write(to: fixture, options: .atomic)
    }
}

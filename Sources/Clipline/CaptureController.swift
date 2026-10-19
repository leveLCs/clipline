import AppKit
import ScreenCaptureKit

@MainActor
final class CaptureController {
    var onImage: ((URL, CGRect) -> Void)?
    var onActiveChanged: (() -> Void)?
    private(set) var isActive = false
    private var session = UUID()
    private var task: Task<Void, Never>?
    private var ddddOCR: DdddOCR?
    private var panels: [SelectionPanel] = []
    private var keyMonitor: Any?
    private var displayObserver: Any?
    private var spaceObserver: Any?
    private var cursorPushed = false
    private var notice: NSPanel?

    func start() {
        guard !isActive else { return }
        notice?.orderOut(nil)
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = L("Allow screen capture")
            alert.informativeText = L("Allow Clipline in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen Clipline. Only still images are captured; no audio is recorded.")
            alert.addButton(withTitle: L("Open System Settings"))
            alert.addButton(withTitle: L("Not now"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            return
        }
        isActive = true
        session = UUID()
        let current = session
        onActiveChanged?()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                var snapshots: [(CGRect, CGImage)] = []
                for screen in NSScreen.screens {
                    guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                          let display = content.displays.first(where: { $0.displayID == id.uint32Value }) else { continue }
                    let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = Int(screen.frame.width * screen.backingScaleFactor)
                    config.height = Int(screen.frame.height * screen.backingScaleFactor)
                    config.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    try Task.checkCancellation()
                    snapshots.append((screen.frame, image))
                }
                guard self.session == current else { return }
                guard !snapshots.isEmpty else { throw CocoaError(.fileReadUnknown) }
                self.task = nil
                self.present(snapshots)
            } catch {
                guard self.session == current else { return }
                self.finish()
                if !(error is CancellationError) { self.showError(error) }
            }
        }
    }

    func cancel() {
        guard isActive else { return }
        task?.cancel()
        ddddOCR?.cancel()
        finish()
    }

    private func present(_ snapshots: [(CGRect, CGImage)]) {
        for (frame, image) in snapshots {
            let view = SelectionView(frame: CGRect(origin: .zero, size: frame.size), image: image)
            view.onCancel = { [weak self] in self?.cancel() }
            view.onSelect = { [weak self] start, end, flags in
                self?.selected(start: start, end: end, flags: flags, frame: frame, image: image)
            }
            let panel = SelectionPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = true
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = view
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            panel.makeFirstResponder(view)
            panels.append(panel)
        }
        (panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panels.first)?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, !self.panels.isEmpty else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.cancel() }
                return nil
            }
            for panel in self.panels {
                guard let view = panel.contentView as? SelectionView, !view.isRecognizing else { continue }
                view.mode = CaptureMode(modifiers: event.modifierFlags)
            }
            return event
        }
        NSCursor.crosshair.push()
        cursorPushed = true
    }

    private func selected(start: CGPoint, end: CGPoint, flags: NSEvent.ModifierFlags,
                          frame: CGRect, image: CGImage) {
        guard let selection = CaptureSelection(start: start, end: end, screenFrame: frame,
                pixelSize: CGSize(width: image.width, height: image.height), modifiers: flags),
              let crop = image.cropping(to: selection.pixelRect) else {
            cancel()
            return
        }
        let current = session
        if selection.mode == .ddddocr {
            // Keep keyboard focus and cancellation observers while the slower worker runs.
            for panel in panels { (panel.contentView as? SelectionView)?.isRecognizing = true }
        } else {
            removeOverlays()
        }
        let worker = selection.mode == .ddddocr ? DdddOCR() : nil
        ddddOCR = worker
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if selection.mode == .hang {
                    let url = try await Task.detached(priority: .userInitiated) {
                        try CaptureStorage.save(crop)
                    }.value
                    guard self.session == current else { return }
                    self.finish()
                    self.onImage?(url, selection.rect)
                } else {
                    let text = try await Task.detached(priority: .userInitiated) {
                        if let worker { return try worker.recognize(crop) }
                        return try TextRecognition.recognize(crop)
                    }.value
                    guard self.session == current else { return }
                    let copied = TextRecognition.copy(text)
                    self.finish()
                    self.showNotice(copied ? L("Text copied") : L("No text found"), on: frame)
                }
            } catch {
                guard self.session == current else { return }
                self.finish()
                self.showError(error)
            }
        }
    }

    private func removeOverlays() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    private func finish() {
        removeOverlays()
        session = UUID()
        task = nil
        ddddOCR = nil
        isActive = false
        onActiveChanged?()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L("Could not capture")
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showNotice(_ text: String, on frame: CGRect) {
        let panel = NSPanel(contentRect: CGRect(x: frame.midX - 140, y: frame.maxY - 130, width: 280, height: 48),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        let effect = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 280, height: 48))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        label.frame = CGRect(x: 10, y: 14, width: 260, height: 22)
        effect.addSubview(label)
        panel.contentView = effect
        notice = panel
        panel.orderFrontRegardless()
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.notice === panel { self?.notice = nil }
        }
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    let image: CGImage
    var onCancel: (() -> Void)?
    var onSelect: ((CGPoint, CGPoint, NSEvent.ModifierFlags) -> Void)?
    var mode = CaptureMode(modifiers: NSEvent.modifierFlags) { didSet { needsDisplay = true } }
    var isRecognizing = false {
        didSet {
            mode = .ddddocr
            setAccessibilityLabel(L("Recognizing text (ddddocr). Escape cancels."))
        }
    }
    private var start: CGPoint?
    private var end: CGPoint?

    init(frame: CGRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Drag: Apple Vision · ⌥: ddddocr · ⌃: Hang image · Esc: Cancel"))
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func mouseDown(with event: NSEvent) {
        guard !isRecognizing else { return }
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        end = start
        mode = CaptureMode(modifiers: event.modifierFlags)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard !isRecognizing else { return }
        end = convert(event.locationInWindow, from: nil)
        mode = CaptureMode(modifiers: event.modifierFlags)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard !isRecognizing, let start, let window else { return }
        let end = convert(event.locationInWindow, from: nil)
        onSelect?(window.convertPoint(toScreen: convert(start, to: nil)),
                  window.convertPoint(toScreen: convert(end, to: nil)), event.modifierFlags)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
        let mask = NSBezierPath(rect: bounds)
        var selection: CGRect?
        if let start, let end {
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
            if !rect.isEmpty { mask.appendRect(rect); selection = rect }
        }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.30).setFill()
        mask.fill()
        if let selection {
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 2
            (mode == .hang ? NSColor.systemMint : .white).setStroke()
            outline.stroke()
        }
        let title: String
        switch mode {
        case .vision: title = L("Capture text (Apple Vision)")
        case .ddddocr: title = isRecognizing ? L("Recognizing text (ddddocr). Escape cancels.") : L("Capture text (ddddocr)")
        case .hang: title = L("Hang image")
        }
        let hint = L("Drag: Apple Vision · ⌥: ddddocr · ⌃: Hang image · Esc: Cancel")
        let width = min(620, bounds.width - 40)
        let box = CGRect(x: (bounds.width - width) / 2, y: bounds.height - 112, width: width, height: 68)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (title as NSString).draw(in: CGRect(x: box.minX + 10, y: box.minY + 35, width: width - 20, height: 24),
            withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold),
                             .foregroundColor: mode == .hang ? NSColor.systemMint : .white, .paragraphStyle: paragraph])
        (hint as NSString).draw(in: CGRect(x: box.minX + 12, y: box.minY + 10, width: width - 24, height: 20),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white,
                             .paragraphStyle: paragraph])
    }
}

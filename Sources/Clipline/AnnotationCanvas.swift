import AppKit

/// View coordinates are logical points; document coordinates are normalized source pixels.
struct AnnotationViewport: Equatable {
    var scale: CGFloat = 1
    var origin: CGPoint = .zero
    func sourcePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
    func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + origin.x, y: point.y * scale + origin.y)
    }
    func viewRect(_ rect: CGRect) -> CGRect { CGRect(origin: viewPoint(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale)) }
    mutating func zoom(to value: CGFloat, anchor: CGPoint) {
        let pixel = sourcePoint(anchor)
        scale = max(0.01, min(32, value))
        origin = CGPoint(x: anchor.x - pixel.x * scale, y: anchor.y - pixel.y * scale)
    }
}

enum AnnotationHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, start, end, source, tail
}

enum AnnotationCanvasGeometry {
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    static func constrained(_ point: CGPoint, from anchor: CGPoint, line: Bool) -> CGPoint {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        if line {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: anchor.x + (dx < 0 ? -side : side), y: anchor.y + (dy < 0 ? -side : side))
    }
    static func created(kind: AnnotationKind, from a: CGPoint, to point: CGPoint, style: AnnotationStyle, shift: Bool) -> Annotation {
        let b = shift ? constrained(point, from: a, line: kind == .line || kind == .arrow) : point
        var item = Annotation(kind: kind, rect: rect(from: a, to: b), style: style)
        if kind == .line || kind == .arrow { item.points = [a, b] }
        if kind == .pen || kind == .highlighter { item.points = [a, b] }
        if kind == .magnify { item.magnifierSource = a }
        return item
    }
    static func handles(_ rect: CGRect) -> [(AnnotationHandle, CGPoint)] {
        [(.topLeft, CGPoint(x: rect.minX, y: rect.minY)), (.top, CGPoint(x: rect.midX, y: rect.minY)),
         (.topRight, CGPoint(x: rect.maxX, y: rect.minY)), (.right, CGPoint(x: rect.maxX, y: rect.midY)),
         (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)), (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
         (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)), (.left, CGPoint(x: rect.minX, y: rect.midY))]
    }
    static func resizedRect(_ rect: CGRect, handle: AnnotationHandle, to point: CGPoint, shift: Bool) -> CGRect {
        var a = rect.origin, b = CGPoint(x: rect.maxX, y: rect.maxY)
        if [.topLeft, .left, .bottomLeft].contains(handle) { a.x = point.x }
        if [.topLeft, .top, .topRight].contains(handle) { a.y = point.y }
        if [.topRight, .right, .bottomRight].contains(handle) { b.x = point.x }
        if [.bottomLeft, .bottom, .bottomRight].contains(handle) { b.y = point.y }
        if shift && [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle) {
            let opposite: CGPoint
            switch handle {
            case .topLeft: opposite = CGPoint(x: rect.maxX, y: rect.maxY)
            case .topRight: opposite = CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomLeft: opposite = CGPoint(x: rect.maxX, y: rect.minY)
            default: opposite = rect.origin
            }
            return self.rect(from: opposite, to: constrained(point, from: opposite, line: false))
        }
        return self.rect(from: a, to: b)
    }
    static func resized(_ item: Annotation, handle: AnnotationHandle, to point: CGPoint, shift: Bool) -> Annotation {
        var result = item
        if handle == .source { result.magnifierSource = point; return result }
        if handle == .tail { result.points = [point]; return result }
        if handle == .start || handle == .end {
            var points = item.points.count >= 2 ? item.points : [item.rect.origin, CGPoint(x: item.rect.maxX, y: item.rect.maxY)]
            let index = handle == .start ? 0 : points.count - 1
            points[index] = shift ? constrained(point, from: points[index == 0 ? points.count - 1 : 0], line: true) : point
            result.points = points; result.rect = rect(from: points[0], to: points[points.count - 1])
            return result
        }
        return item.resized(to: resizedRect(item.rect, handle: handle, to: point, shift: shift))
    }
    static func clampedCrop(_ rect: CGRect, source: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        let crop = rect.standardized.intersection(source)
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else { return nil }
        return crop
    }
    static func movedCrop(_ crop: CGRect, by offset: CGSize, source: CGRect) -> CGRect {
        CGRect(x: max(source.minX, min(source.maxX - crop.width, crop.minX + offset.width)),
               y: max(source.minY, min(source.maxY - crop.height, crop.minY + offset.height)), width: crop.width, height: crop.height)
    }
    static func hit(_ item: Annotation, at point: CGPoint, tolerance: CGFloat) -> Bool {
        if item.kind == .ellipse || item.kind == .magnify {
            let r = item.rect.insetBy(dx: -tolerance, dy: -tolerance)
            guard r.width > 0, r.height > 0 else { return false }
            return pow((point.x - r.midX) / (r.width / 2), 2) + pow((point.y - r.midY) / (r.height / 2), 2) <= 1
        }
        return item.contains(point, tolerance: tolerance)
    }
}

@MainActor
final class AnnotationCanvas: NSView, NSTextViewDelegate {
    let document: AnnotationDocument
    private(set) var tool: AnnotationKind = .hand
    var style = AnnotationStyle()
    var selectedID: UUID? { didSet { if oldValue != selectedID { needsDisplay = true; onSelectionChanged?(selectedAnnotation) } } }
    var selectedAnnotation: Annotation? { state.annotations.first { $0.id == selectedID } }
    var onSelectionChanged: ((Annotation?) -> Void)?
    var onDocumentChanged: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCopy: (() -> Void)?
    var onOCR: (() -> Void)?
    var onError: ((Error) -> Void)?
    /// Enabled by the controller for crop mode; crop is separate from the document's drawing tools.
    var isCropping = false { didSet { finishTextEditing(); selectedID = nil; needsDisplay = true } }
    var clickCreatesShapes = true
    var stampText = "👍"
    var contentInsets = NSEdgeInsets(top: 24, left: 24, bottom: 100, right: 24)
    private(set) var viewport = AnnotationViewport()
    private var fitted = false
    private var preview: AnnotationState?
    private var state: AnnotationState { preview ?? document.state }
    private var sourceRect: CGRect { CGRect(x: 0, y: 0, width: document.source.width, height: document.source.height) }
    private var cachedImage: CGImage?
    private var cacheDirty = true
    private var gesture: Gesture?
    private var editor: AnnotationTextView?
    private var editingID: UUID?
    private var textIsNew = false
    private var finishingText = false
    private var isPanning = false
    private var lastPan: CGPoint = .zero

    private struct Gesture {
        enum Action { case create, move(UUID), resize(UUID, AnnotationHandle), erase, cropCreate, cropMove, cropResize(AnnotationHandle) }
        var action: Action
        var start: CGPoint
        var base: AnnotationState
        var item: Annotation?
    }

    init(document: AnnotationDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityLabel(L("Annotation canvas"))
        setAccessibilityRole(.group)
        document.onChange = { [weak self] in
            guard let self else { return }
            self.preview = nil
            if !self.document.state.annotations.contains(where: { $0.id == self.selectedID }) { self.selectedID = nil }
            self.invalidateImage()
            self.onSelectionChanged?(self.selectedAnnotation)
            self.onDocumentChanged?()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var isEditingText: Bool { editor != nil }

    override func layout() {
        super.layout()
        if !fitted && bounds.width > 0 && bounds.height > 0 { fit() }
        updateEditorFrame()
        invalidateImage()
    }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); invalidateImage() }
    func fit() {
        finishTextEditing()
        let width = max(1, bounds.width - contentInsets.left - contentInsets.right)
        let height = max(1, bounds.height - contentInsets.top - contentInsets.bottom)
        viewport.scale = max(0.01, min(width / sourceRect.width, height / sourceRect.height))
        viewport.origin = CGPoint(x: contentInsets.left + (width - sourceRect.width * viewport.scale) / 2,
                                  y: contentInsets.top + (height - sourceRect.height * viewport.scale) / 2)
        fitted = true; invalidateImage()
    }
    func zoom(to scale: CGFloat, anchor: CGPoint? = nil) {
        viewport.zoom(to: scale, anchor: anchor ?? CGPoint(x: bounds.midX, y: bounds.midY))
        fitted = true; updateEditorFrame(); invalidateImage()
    }
    func zoomIn() { zoom(to: viewport.scale * 1.25) }
    func zoomOut() { zoom(to: viewport.scale / 1.25) }
    func sourcePoint(fromView point: CGPoint) -> CGPoint { viewport.sourcePoint(point) }
    func viewPoint(fromSource point: CGPoint) -> CGPoint { viewport.viewPoint(point) }
    func selectTool(_ value: AnnotationKind) {
        finishTextEditing(); tool = value; isCropping = false
        if value != .hand { selectedID = nil }
        window?.makeFirstResponder(self); window?.invalidateCursorRects(for: self)
    }
    func applyStyle(_ value: AnnotationStyle) {
        finishTextEditing(); style = value
        guard let id = selectedID, let index = document.state.annotations.firstIndex(where: { $0.id == id }) else { return }
        var next = document.state; next.annotations[index].style = value
        document.commit(state: next, label: L("Change annotation style"))
    }
    func updateSelectedText(_ text: String) {
        finishTextEditing()
        guard let index = document.state.annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        var next = document.state; next.annotations[index].text = text
        document.commit(state: next, label: L("Edit annotation text"))
    }
    func deleteSelection() {
        finishTextEditing()
        guard let id = selectedID else { return }
        var next = document.state; next.annotations.removeAll { $0.id == id }
        document.commit(state: next, label: L("Delete annotation")); selectedID = nil
    }
    func duplicateSelection() {
        finishTextEditing()
        guard var item = selectedAnnotation else { return }
        item = item.translated(by: CGSize(width: 16, height: 16)); item.id = UUID()
        if item.style.magnifierLinked, let sample = item.magnifierSource { item.magnifierSource = CGPoint(x: sample.x + 16, y: sample.y + 16) }
        var next = document.state; next.annotations.append(item)
        document.commit(state: next, label: L("Duplicate annotation")); selectedID = item.id
    }
    func undo() { finishTextEditing(); cancelInteraction(); document.undo() }
    func redo() { finishTextEditing(); cancelInteraction(); document.redo() }
    func setCrop(_ crop: CGRect?) {
        finishTextEditing(); cancelInteraction()
        var next = document.state
        if let crop { guard let clamped = AnnotationCanvasGeometry.clampedCrop(crop, source: sourceRect) else { return }; next.crop = clamped }
        else { next.crop = nil }
        document.commit(state: next, label: L("Crop image"))
    }
    func requestOCR() { finishTextEditing(); onOCR?() }
    func requestCopy() { finishTextEditing(); onCopy?() }
    private func invalidateImage() { cacheDirty = true; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        if cacheDirty { rebuildImage() }
        if let cachedImage, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState(); context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
            context.draw(cachedImage, in: bounds); context.restoreGState()
        }
        if let crop = state.crop ?? (isCropping ? sourceRect : nil) {
            let r = viewport.viewRect(crop)
            let mask = NSBezierPath(rect: viewport.viewRect(sourceRect)); mask.appendRect(r); mask.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.35).setFill(); mask.fill()
            NSColor.white.setStroke(); let border = NSBezierPath(rect: r); border.lineWidth = 1; border.stroke()
            if isCropping { drawHandles(AnnotationCanvasGeometry.handles(crop), color: .white) }
        }
        if !isCropping, let item = selectedAnnotation {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: viewport.viewRect(item.bounds)); border.lineWidth = 1
            border.setLineDash([4, 3], count: 2, phase: 0); border.stroke()
            drawHandles(selectionHandles(item), color: .controlAccentColor)
        }
    }
    private func rebuildImage() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let backing = window?.backingScaleFactor ?? 1
        let width = max(1, Int(ceil(bounds.width * backing))), height = max(1, Int(ceil(bounds.height * backing)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: backing, y: -backing)
        context.translateBy(x: viewport.origin.x, y: viewport.origin.y); context.scaleBy(x: viewport.scale, y: viewport.scale)
        var drawing = state
        // Keep the actual crop during effect sampling so the preview cannot reveal cropped pixels.
        if let index = drawing.annotations.firstIndex(where: { $0.id == editingID }) { drawing.annotations[index].text = "" }
        do { try AnnotationRenderer.draw(source: document.source, state: drawing, in: context); cachedImage = context.makeImage(); cacheDirty = false }
        catch { cachedImage = nil; cacheDirty = false; onError?(error) }
    }
    private func drawHandles(_ handles: [(AnnotationHandle, CGPoint)], color: NSColor) {
        for (handle, point) in handles {
            let p = viewport.viewPoint(point), r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            let path = handle == .source || handle == .tail ? NSBezierPath(ovalIn: r) : NSBezierPath(rect: r)
            color.setFill(); path.fill(); NSColor.black.withAlphaComponent(0.65).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
    private func selectionHandles(_ item: Annotation) -> [(AnnotationHandle, CGPoint)] {
        if item.kind == .line || item.kind == .arrow {
            let points = item.points.count >= 2 ? item.points : [item.rect.origin, CGPoint(x: item.rect.maxX, y: item.rect.maxY)]
            return [(.start, points[0]), (.end, points[points.count - 1])]
        }
        var handles = AnnotationCanvasGeometry.handles(item.rect)
        if item.kind == .magnify, !item.style.magnifierLinked { handles.append((.source, item.magnifierSource ?? CGPoint(x: item.rect.midX, y: item.rect.midY))) }
        if item.kind == .bubble { handles.append((.tail, item.points.last ?? CGPoint(x: item.rect.midX, y: item.rect.maxY + 18))) }
        return handles
    }
    private func hitHandle(_ handles: [(AnnotationHandle, CGPoint)], at point: CGPoint) -> AnnotationHandle? {
        handles.reversed().first { hypot($0.1.x - point.x, $0.1.y - point.y) <= 7 / viewport.scale }?.0
    }
    private func topItem(at point: CGPoint) -> Annotation? {
        state.annotations.reversed().first { AnnotationCanvasGeometry.hit($0, at: point, tolerance: 5 / viewport.scale) }
    }

    // These source-pixel operations are shared by native events and focused behavior checks.
    func beginInteraction(at point: CGPoint, shift: Bool = false, clickCount: Int = 1) {
        finishTextEditing()
        let base = document.state
        if isCropping {
            let crop = base.crop ?? sourceRect
            if let handle = hitHandle(AnnotationCanvasGeometry.handles(crop), at: point) {
                gesture = Gesture(action: .cropResize(handle), start: point, base: base)
            } else if base.crop != nil && crop.contains(point) {
                gesture = Gesture(action: .cropMove, start: point, base: base)
            } else { gesture = Gesture(action: .cropCreate, start: clampedPoint(point), base: base) }
        } else if tool == .eraser {
            gesture = Gesture(action: .erase, start: point, base: base)
        } else if let item = selectedAnnotation, let handle = hitHandle(selectionHandles(item), at: point) {
            gesture = Gesture(action: .resize(item.id, handle), start: point, base: base, item: item)
        } else if tool == .hand {
            if let item = topItem(at: point) {
                selectedID = item.id
                if clickCount >= 2 && [.text, .bubble, .note].contains(item.kind) { beginTextEditing(item.id, isNew: false); return }
                gesture = Gesture(action: .move(item.id), start: point, base: base, item: item)
            } else { selectedID = nil; return }
        } else {
            guard sourceRect.contains(point) else { selectedID = nil; return }
            var item = AnnotationCanvasGeometry.created(kind: tool, from: point, to: point, style: style, shift: shift)
            if tool == .pen || tool == .highlighter { item.points = [point] }
            if tool == .stamp { item.text = stampText }
            if tool == .text || tool == .bubble { item.text = L("Text") }
            if tool == .note { item.text = L("Note") }
            if tool == .step || tool == .stamp { item.rect = centeredRect(point, size: CGSize(width: style.size, height: style.size)) }
            selectedID = nil
            gesture = Gesture(action: .create, start: point, base: base, item: item)
        }
        updateInteraction(to: point, shift: shift)
    }
    func updateInteraction(to point: CGPoint, shift: Bool = false) {
        guard var gesture else { return }
        var next = gesture.base
        let offset = CGSize(width: point.x - gesture.start.x, height: point.y - gesture.start.y)
        switch gesture.action {
        case .create:
            guard var item = gesture.item else { return }
            if item.kind == .pen || item.kind == .highlighter {
                if item.points.last != point { item.points.append(point) }
                item.rect = item.points.reduce(CGRect(origin: gesture.start, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            } else if item.kind != .step && item.kind != .stamp {
                let id = item.id, text = item.text
                item = AnnotationCanvasGeometry.created(kind: item.kind, from: gesture.start, to: point, style: item.style, shift: shift)
                item.id = id; item.text = text
            }
            gesture.item = item; self.gesture = gesture; next.annotations.append(item)
        case .move(let id):
            guard let original = gesture.item, let index = next.annotations.firstIndex(where: { $0.id == id }) else { return }
            var item = original.translated(by: offset)
            if item.kind == .magnify && item.style.magnifierLinked {
                let source = original.magnifierSource ?? CGPoint(x: original.rect.midX, y: original.rect.midY)
                item.magnifierSource = CGPoint(x: source.x + offset.width, y: source.y + offset.height)
            }
            next.annotations[index] = item
        case .resize(let id, let handle):
            guard let original = gesture.item, let index = next.annotations.firstIndex(where: { $0.id == id }) else { return }
            var item = AnnotationCanvasGeometry.resized(original, handle: handle, to: point, shift: shift)
            if item.kind == .magnify && item.style.magnifierLinked {
                let sample = original.magnifierSource ?? CGPoint(x: original.rect.midX, y: original.rect.midY)
                item.magnifierSource = CGPoint(x: sample.x + item.rect.midX - original.rect.midX, y: sample.y + item.rect.midY - original.rect.midY)
            }
            next.annotations[index] = item
        case .erase:
            next = preview ?? gesture.base
            if let index = next.annotations.lastIndex(where: { AnnotationCanvasGeometry.hit($0, at: point, tolerance: 5 / viewport.scale) }) { next.annotations.remove(at: index) }
        case .cropCreate:
            let end = shift ? AnnotationCanvasGeometry.constrained(clampedPoint(point), from: gesture.start, line: false) : clampedPoint(point)
            next.crop = AnnotationCanvasGeometry.clampedCrop(AnnotationCanvasGeometry.rect(from: gesture.start, to: end), source: sourceRect) ?? gesture.base.crop
        case .cropMove:
            next.crop = AnnotationCanvasGeometry.movedCrop(gesture.base.crop ?? sourceRect, by: offset, source: sourceRect)
        case .cropResize(let handle):
            let crop = AnnotationCanvasGeometry.resizedRect(gesture.base.crop ?? sourceRect, handle: handle, to: clampedPoint(point), shift: shift)
            next.crop = AnnotationCanvasGeometry.clampedCrop(crop, source: sourceRect) ?? gesture.base.crop
        }
        preview = next; invalidateImage()
    }
    func endInteraction() {
        guard let gesture, var next = preview else { self.gesture = nil; return }
        self.gesture = nil
        var newText: UUID?
        if case .create = gesture.action, var item = next.annotations.last {
            let isClick = item.rect.width < 1 && item.rect.height < 1
            if isClick && item.kind != .pen && item.kind != .highlighter {
                guard clickCreatesShapes else { preview = nil; invalidateImage(); return }
                let size = CGSize(width: max(40, min(180, sourceRect.width / 3)), height: max(30, min(90, sourceRect.height / 4)))
                if item.kind == .line || item.kind == .arrow {
                    item.points = [gesture.start, CGPoint(x: gesture.start.x + size.width, y: gesture.start.y)]
                    item.rect = AnnotationCanvasGeometry.rect(from: item.points[0], to: item.points[1])
                } else { item.rect = CGRect(origin: gesture.start, size: size) }
            }
            if item.rect.width < 1 && ![.line, .arrow, .pen, .highlighter].contains(item.kind) { item.rect.size.width = 1 }
            if item.rect.height < 1 && ![.line, .arrow, .pen, .highlighter].contains(item.kind) { item.rect.size.height = 1 }
            next.annotations[next.annotations.count - 1] = item
            selectedID = item.id
            if [.text, .bubble, .note].contains(item.kind) { newText = item.id }
        }
        preview = next
        if let id = newText { beginTextEditing(id, isNew: true) }
        else { preview = nil; document.commit(state: next, label: L("Edit annotations")); invalidateImage() }
    }
    func cancelInteraction() { gesture = nil; preview = nil; invalidateImage() }
    private func clampedPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: max(0, min(sourceRect.width, p.x)), y: max(0, min(sourceRect.height, p.y))) }
    private func centeredRect(_ p: CGPoint, size: CGSize) -> CGRect { CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.buttonNumber == 2 || (tool == .hand && event.modifierFlags.contains(.option)) {
            finishTextEditing(); isPanning = true; lastPan = point; NSCursor.closedHand.set(); return
        }
        window?.makeFirstResponder(self)
        beginInteraction(at: viewport.sourcePoint(point), shift: event.modifierFlags.contains(.shift), clickCount: event.clickCount)
        if tool == .hand && gesture == nil && editor == nil { isPanning = true; lastPan = point; NSCursor.closedHand.set() }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPanning {
            viewport.origin.x += point.x - lastPan.x; viewport.origin.y += point.y - lastPan.y
            lastPan = point; fitted = true; updateEditorFrame(); invalidateImage()
        } else { updateInteraction(to: viewport.sourcePoint(point), shift: event.modifierFlags.contains(.shift)) }
    }
    override func mouseUp(with event: NSEvent) {
        if isPanning { isPanning = false; window?.invalidateCursorRects(for: self) }
        else { endInteraction() }
    }
    override func otherMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            zoom(to: viewport.scale * exp(-event.scrollingDeltaY * 0.01), anchor: convert(event.locationInWindow, from: nil))
        } else {
            viewport.origin.x += event.scrollingDeltaX; viewport.origin.y += event.scrollingDeltaY
            fitted = true; updateEditorFrame(); invalidateImage()
        }
    }
    override func magnify(with event: NSEvent) { zoom(to: viewport.scale * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil)) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: tool == .hand ? .openHand : .crosshair) }

    func editSelectedText() {
        guard let item = selectedAnnotation, [.text, .bubble, .note].contains(item.kind) else { return }
        finishTextEditing(); beginTextEditing(item.id, isNew: false)
    }
    private func beginTextEditing(_ id: UUID, isNew: Bool) {
        guard let item = state.annotations.first(where: { $0.id == id }) else { return }
        editingID = id; textIsNew = isNew
        if preview == nil { preview = document.state }
        let text = AnnotationTextView(frame: .zero)
        text.owner = self; text.delegate = self; text.isRichText = false; text.importsGraphics = false
        text.allowsUndo = true; text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainerInset = CGSize(width: 4, height: 4); text.textContainer?.widthTracksTextView = true
        text.drawsBackground = true; text.backgroundColor = item.style.backgroundColor.nsColor
        text.textColor = item.style.textColor.nsColor
        text.font = NSFont(name: item.style.fontName, size: item.style.fontSize * viewport.scale) ?? NSFont.systemFont(ofSize: max(1, item.style.fontSize * viewport.scale))
        text.string = item.text; text.setAccessibilityLabel(L("Annotation text"))
        editor = text; addSubview(text); updateEditorFrame(); window?.makeFirstResponder(text)
        text.selectAll(nil); invalidateImage()
    }
    private func updateEditorFrame() {
        guard let editor, let item = state.annotations.first(where: { $0.id == editingID }) else { return }
        var r = viewport.viewRect(item.rect)
        if item.kind == .bubble { r = r.insetBy(dx: 6 * viewport.scale, dy: 4 * viewport.scale) }
        if item.kind == .note { r.origin.y = r.maxY + 8; r.size = CGSize(width: max(200, r.width), height: 100) }
        r.size.width = max(40, r.width); r.size.height = max(30, r.height)
        editor.frame = r
        editor.font = NSFont(name: item.style.fontName, size: max(1, item.style.fontSize * viewport.scale)) ?? NSFont.systemFont(ofSize: max(1, item.style.fontSize * viewport.scale))
    }
    func textDidChange(_ notification: Notification) {
        guard let editor, let index = preview?.annotations.firstIndex(where: { $0.id == editingID }) else { return }
        preview?.annotations[index].text = editor.string
        invalidateImage()
    }
    func textDidEndEditing(_ notification: Notification) { if !finishingText { finishTextEditing() } }
    func finishTextEditing() {
        guard let editor, !finishingText else { return }
        finishingText = true
        editor.unmarkText()
        var next = preview ?? document.state
        if let index = next.annotations.firstIndex(where: { $0.id == editingID }) { next.annotations[index].text = editor.string }
        editor.delegate = nil; editor.removeFromSuperview(); self.editor = nil; editingID = nil
        preview = nil
        document.commit(state: next, label: textIsNew ? L("Add annotation") : L("Edit annotation text"))
        textIsNew = false; finishingText = false; invalidateImage()
        window?.makeFirstResponder(self)
    }
    private func escape() {
        if editor != nil { finishTextEditing() }
        else if gesture != nil { cancelInteraction() }
        else if selectedID != nil { selectedID = nil }
        else if isCropping { isCropping = false }
        else { onCancel?() }
    }
    override func cancelOperation(_ sender: Any?) { escape() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editor, window?.firstResponder === editor { return editor.performKeyEquivalent(with: event) }
        guard event.modifierFlags.intersection([.command, .option, .control]).contains(.command),
              !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": event.modifierFlags.contains(.shift) ? redo() : undo(); return true
        case "d": duplicateSelection(); return true
        case "c": requestCopy(); return true
        case "+", "=": zoomIn(); return true
        case "-": zoomOut(); return true
        case "0": fit(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: escape()
        case 51, 117: deleteSelection()
        case 36, 76, 49: finishTextEditing(); onFinish?()
        default: super.keyDown(with: event)
        }
    }
}

/// LSUIElement applications have no Edit menu to dispatch these native text commands.
@MainActor
private final class AnnotationTextView: NSTextView {
    weak var owner: AnnotationCanvas?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !hasMarkedText() else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a": selectAll(nil)
        case "c":
            if selectedRange().length > 0 { copy(nil) }
            else { owner?.requestCopy() }
        case "x": cut(nil)
        case "v": pasteAsPlainText(nil)
        case "z": modifiers.contains(.shift) ? undoManager?.redo() : undoManager?.undo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) }
        else { owner?.finishTextEditing() }
    }
}

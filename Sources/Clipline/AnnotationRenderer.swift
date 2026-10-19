import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private final class DrawPass {
        var effects: [Int: CGImage] = [:]
        let spotlights: [Annotation]
        init(_ state: AnnotationState) { spotlights = state.annotations.filter { $0.kind == .spotlight } }
    }

    static func normalized(_ image: CGImage, orientation: Int) throws -> CGImage {
        guard (1...8).contains(orientation) else { throw AnnotationFailure.unreadable }
        if orientation == 1 { return image }
        let transformed = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
        guard let result = ciContext.createCGImage(transformed, from: transformed.extent,
                                                   format: .RGBA8, colorSpace: rgbSpace(image)) else {
            throw AnnotationFailure.renderFailed
        }
        return result
    }

    static func cropRect(source: CGImage, state: AnnotationState) throws -> CGRect {
        let full = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard let crop = state.crop else { return full }
        guard finite(crop) else { throw AnnotationFailure.invalidGeometry }
        let result = crop.standardized.integral.intersection(full)
        guard !result.isNull, result.width >= 1, result.height >= 1 else { throw AnnotationFailure.invalidGeometry }
        return result
    }

    static func render(source: CGImage, state: AnnotationState, includeNotes: Bool = true) throws -> CGImage {
        try validate(state)
        let crop = try cropRect(source: source, state: state)
        let notes = includeNotes ? state.annotations.filter { $0.kind == .note && $0.bounds.intersects(crop) } : []
        let appendix = noteLayout(notes, width: crop.width, state: state)
        let height = Int(crop.height + appendix.height)
        let context = try bitmap(width: Int(crop.width), height: height, source: source)
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        do {
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: -crop.minX, y: -crop.minY)
            try draw(source: source, state: state, in: context)
        }
        if !notes.isEmpty {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: crop.height, width: crop.width, height: appendix.height))
            for entry in appendix.entries {
                drawText(entry.text, in: entry.rect.offsetBy(dx: 0, dy: crop.height),
                         font: .systemFont(ofSize: 14), color: .black, context: context)
            }
        }
        guard let result = context.makeImage() else { throw AnnotationFailure.renderFailed }
        return result
    }

    // Caller supplies a top-left, original-pixel coordinate system. No full-size canvas bitmap is created.
    // Only effects sample a bounded region of earlier composited content.
    static func draw(source: CGImage, state: AnnotationState, in context: CGContext) throws {
        try validate(state)
        try draw(source: source, state: state, in: context, pass: DrawPass(state))
    }
    private static func draw(source: CGImage, state: AnnotationState, in context: CGContext, pass: DrawPass) throws {
        let crop = try cropRect(source: source, state: state)
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: crop)
        drawImage(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height), context: context)
        var spotlightDrawn = false
        for (index, item) in state.annotations.enumerated() {
            context.saveGState()
            defer { context.restoreGState() }
            context.setAlpha(item.style.opacity)
            context.setStrokeColor(item.style.color.nsColor.cgColor)
            context.setFillColor(item.style.color.nsColor.cgColor)
            context.setLineWidth(item.style.lineWidth)
            context.setLineCap(.round); context.setLineJoin(.round)
            let rect = item.rect.standardized
            switch item.kind {
            case .hand, .eraser: break
            case .rectangle:
                shape(path: box(rect, style: item.style.boxStyle, radius: item.style.cornerRadius), style: item.style, context: context)
            case .ellipse:
                shape(path: CGPath(ellipseIn: rect, transform: nil), style: item.style, context: context)
            case .line:
                stroke(points: endpoints(item), context: context)
            case .arrow:
                arrow(item, context: context)
            case .pen, .highlighter:
                if item.kind == .highlighter {
                    context.setAlpha(item.style.opacity * 0.35)
                    context.setLineWidth(max(item.style.lineWidth, 12))
                    context.setLineCap(.butt)
                }
                if item.points.count == 1 {
                    let width = item.kind == .highlighter ? max(item.style.lineWidth, 12) : item.style.lineWidth
                    context.fillEllipse(in: CGRect(x: item.points[0].x - width / 2, y: item.points[0].y - width / 2, width: width, height: width))
                } else { stroke(points: item.points, context: context) }
            case .text:
                if item.style.filled {
                    context.setFillColor(item.style.backgroundColor.nsColor.cgColor); context.fill(rect)
                }
                drawText(item.text, in: rect, font: font(item.style), color: item.style.textColor.nsColor, context: context)
            case .bubble:
                bubble(item, context: context)
            case .pixelate:
                try mask(item, source: source, prior: Array(state.annotations.prefix(index)), crop: crop, context: context, index: index, pass: pass)
            case .magnify:
                try magnify(item, source: source, prior: Array(state.annotations.prefix(index)), crop: crop, context: context, index: index, pass: pass)
            case .step:
                badge("\(state.stepNumber(for: item.id) ?? 1)", center: CGPoint(x: rect.midX, y: rect.midY), style: item.style, context: context)
            case .stamp:
                drawText(item.text.isEmpty ? "👍" : item.text, in: rect,
                         font: .systemFont(ofSize: item.style.size), color: item.style.textColor.nsColor, context: context)
            case .spotlight:
                if !spotlightDrawn {
                    context.setAlpha(1)
                    spotlight(pass.spotlights, crop: crop, context: context)
                    spotlightDrawn = true
                }
            case .note:
                note(item, number: state.noteNumber(for: item.id) ?? 1, context: context)
            }
        }
    }

    // A fresh destination plus a small whitelist prevents original paths and hidden thumbnails from leaking.
    static func encode(_ image: CGImage, type: String = UTType.png.identifier,
                       properties: [CFString: Any] = [:]) throws -> Data {
        guard [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier].contains(type),
              (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(type) else {
            throw AnnotationFailure.unsupportedFormat
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            throw AnnotationFailure.unsupportedFormat
        }
        var safe: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let value = properties[key] as? NSNumber { safe[key] = value }
        }
        var output = image
        if type == UTType.jpeg.identifier {
            let context = try bitmap(width: image.width, height: image.height, source: image)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { throw AnnotationFailure.renderFailed }
            output = flattened
            safe[kCGImageDestinationLossyCompressionQuality] = 0.95
        }
        CGImageDestinationAddImage(destination, output, safe as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AnnotationFailure.writeFailed }
        return data as Data
    }

    private static func bitmap(width: Int, height: Int, source: CGImage) throws -> CGContext {
        guard width > 0, height > 0, width <= 32768, height <= 32768,
              width <= 200_000_000 / height,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: rgbSpace(source),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw AnnotationFailure.renderFailed }
        return context
    }
    private static func rgbSpace(_ source: CGImage) -> CGColorSpace {
        if let space = source.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
    private static func box(_ rect: CGRect, style: AnnotationBoxStyle, radius: CGFloat) -> CGPath {
        if style == .rounded || style == .roundedDashed {
            return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        return CGPath(rect: rect, transform: nil)
    }
    private static func shape(path: CGPath, style: AnnotationStyle, context: CGContext) {
        if style.boxStyle == .dashed || style.boxStyle == .roundedDashed {
            context.setLineDash(phase: 0, lengths: [max(style.lineWidth * 3, 6), max(style.lineWidth * 2, 4)])
        }
        context.addPath(path)
        context.drawPath(using: style.filled ? .fillStroke : .stroke)
    }
    private static func endpoints(_ item: Annotation) -> [CGPoint] {
        if item.points.count >= 2 { return [item.points[0], item.points[item.points.count - 1]] }
        return [item.rect.origin, CGPoint(x: item.rect.maxX, y: item.rect.maxY)]
    }
    private static func stroke(points: [CGPoint], context: CGContext) {
        guard let first = points.first, points.count > 1 else { return }
        context.beginPath(); context.move(to: first)
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }
    private static func arrow(_ item: Annotation, context: CGContext) {
        let ends = endpoints(item), a = ends[0], b = ends[1]
        let dx = b.x - a.x, dy = b.y - a.y, length = hypot(dx, dy)
        guard length > 0 else { return }
        let unit = CGPoint(x: dx / length, y: dy / length)
        let head = min(length / 2, max(item.style.lineWidth * 4, 12))
        let base = CGPoint(x: b.x - unit.x * head, y: b.y - unit.y * head)
        let left = CGPoint(x: base.x - unit.y * head / 2, y: base.y + unit.x * head / 2)
        let right = CGPoint(x: base.x + unit.y * head / 2, y: base.y - unit.x * head / 2)
        if item.style.arrowStyle == .dashed { context.setLineDash(phase: 0, lengths: [8, 6]) }
        if item.style.arrowStyle == .curved {
            let control = CGPoint(x: (a.x + b.x) / 2 - dy * 0.25, y: (a.y + b.y) / 2 + dx * 0.25)
            context.beginPath(); context.move(to: a); context.addQuadCurve(to: b, control: control); context.strokePath()
        } else { stroke(points: [a, item.style.arrowStyle == .emphasis ? base : b], context: context) }
        context.setLineDash(phase: 0, lengths: [])
        context.beginPath(); context.move(to: left); context.addLine(to: b); context.addLine(to: right)
        if item.style.arrowStyle == .emphasis { context.closePath(); context.fillPath() }
        else { context.strokePath() }
    }
    private static func font(_ style: AnnotationStyle) -> NSFont {
        NSFont(name: style.fontName, size: style.fontSize) ?? .systemFont(ofSize: style.fontSize)
    }
    private static func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        NSGraphicsContext.restoreGraphicsState()
    }
    private static func bubble(_ item: Annotation, context: CGContext) {
        let rect = item.rect.standardized
        let tail = item.points.last ?? CGPoint(x: rect.midX, y: rect.maxY + 18)
        context.setFillColor(item.style.backgroundColor.nsColor.cgColor)
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: item.style.cornerRadius, cornerHeight: item.style.cornerRadius)
        path.move(to: CGPoint(x: rect.midX - 8, y: rect.maxY - 1)); path.addLine(to: tail)
        path.addLine(to: CGPoint(x: rect.midX + 8, y: rect.maxY - 1)); path.closeSubpath()
        context.addPath(path); context.drawPath(using: .fillStroke)
        drawText(item.text, in: rect.insetBy(dx: 6, dy: 4), font: font(item.style), color: item.style.textColor.nsColor, context: context)
    }
    private static func badge(_ text: String, center: CGPoint, style: AnnotationStyle, context: CGContext) {
        let rect = CGRect(x: center.x - style.size / 2, y: center.y - style.size / 2, width: style.size, height: style.size)
        context.setFillColor(style.backgroundColor.nsColor.cgColor); context.fillEllipse(in: rect)
        context.setStrokeColor(style.color.nsColor.cgColor); context.strokeEllipse(in: rect)
        let font = NSFont.boldSystemFont(ofSize: style.size * 0.58)
        let size = (text as NSString).size(withAttributes: [.font: font])
        drawText(text, in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width + 1, height: size.height + 1),
                 font: font, color: style.textColor.nsColor, context: context)
    }
    private static func note(_ item: Annotation, number: Int, context: CGContext) {
        var styled = item
        switch item.style.noteStyle {
        case .solidFrame: styled.style.boxStyle = .square
        case .dashedFrame: styled.style.boxStyle = .dashed
        case .roundedFrame: styled.style.boxStyle = .rounded
        case .roundedDashedFrame: styled.style.boxStyle = .roundedDashed
        case .solidArrow: styled.style.arrowStyle = .open
        case .dashedArrow: styled.style.arrowStyle = .dashed
        case .curvedArrow: styled.style.arrowStyle = .curved
        }
        if [.solidArrow, .dashedArrow, .curvedArrow].contains(item.style.noteStyle) {
            arrow(styled, context: context)
        } else {
            styled.style.filled = false
            shape(path: box(item.rect.standardized, style: styled.style.boxStyle, radius: styled.style.cornerRadius), style: styled.style, context: context)
        }
        badge("\(number)", center: item.rect.origin, style: item.style, context: context)
    }
    private static func spotlight(_ items: [Annotation], crop: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        // Intersect outside-of-each-hole clips, so overlapping holes remain illuminated rather than XORing.
        for item in items {
            context.beginPath(); context.addRect(crop)
            if item.style.spotlightShape == .ellipse { context.addEllipse(in: item.rect.standardized) }
            else { context.addPath(CGPath(roundedRect: item.rect.standardized, cornerWidth: item.style.cornerRadius, cornerHeight: item.style.cornerRadius, transform: nil)) }
            context.clip(using: .evenOdd)
        }
        context.setFillColor(NSColor.black.withAlphaComponent(items.first?.style.spotlightDarkness ?? 0.55).cgColor)
        context.fill(crop)
    }
    private static func region(_ rect: CGRect, source: CGImage, prior: [Annotation], crop: CGRect, pass: DrawPass) throws -> CGImage? {
        let sample = rect.integral.intersection(crop)
        guard !sample.isNull, sample.width >= 1, sample.height >= 1 else { return nil }
        let context = try bitmap(width: Int(sample.width), height: Int(sample.height), source: source)
        context.translateBy(x: -sample.minX, y: sample.height + sample.minY); context.scaleBy(x: 1, y: -1)
        try draw(source: source, state: AnnotationState(annotations: prior, crop: crop), in: context, pass: pass)
        return context.makeImage()
    }
    private static func mask(_ item: Annotation, source: CGImage, prior: [Annotation], crop: CGRect, context: CGContext, index: Int, pass: DrawPass) throws {
        let rect = item.rect.standardized.intersection(crop)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        if item.style.maskStyle == .solid {
            context.setFillColor(item.style.color.nsColor.cgColor); context.fill(rect); return
        }
        let output: CGImage
        if let cached = pass.effects[index] { output = cached }
        else {
            guard let image = try region(rect, source: source, prior: prior, crop: crop, pass: pass) else { return }
            let input = CIImage(cgImage: image)
            let filtered: CIImage
            if item.style.maskStyle == .blur {
                filtered = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: item.style.blurRadius])
            } else {
                filtered = input.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: item.style.pixelSize])
            }
            guard let rendered = ciContext.createCGImage(filtered, from: input.extent, format: .RGBA8, colorSpace: rgbSpace(source)) else {
                throw AnnotationFailure.renderFailed
            }
            output = rendered
            pass.effects[index] = output
        }
        context.saveGState(); context.clip(to: rect)
        drawImage(output, in: rect.integral, context: context); context.restoreGState()
    }
    private static func magnify(_ item: Annotation, source: CGImage, prior: [Annotation], crop: CGRect, context: CGContext, index: Int, pass: DrawPass) throws {
        let rect = item.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        let center = item.magnifierSource ?? CGPoint(x: rect.midX, y: rect.midY)
        let sample = CGRect(x: center.x - rect.width / item.style.zoom / 2, y: center.y - rect.height / item.style.zoom / 2,
                            width: rect.width / item.style.zoom, height: rect.height / item.style.zoom)
        let clipped = sample.integral.intersection(crop)
        if item.style.magnifierLinked {
            stroke(points: [center, CGPoint(x: rect.midX, y: rect.midY)], context: context)
        }
        do {
            context.saveGState()
            defer { context.restoreGState() }
            context.addEllipse(in: rect); context.clip()
            context.setFillColor(item.style.backgroundColor.nsColor.cgColor); context.fill(rect)
            let image: CGImage?
            if let cached = pass.effects[index] { image = cached }
            else {
                image = try region(sample, source: source, prior: prior, crop: crop, pass: pass)
                if let image { pass.effects[index] = image }
            }
            if let image {
                let dest = CGRect(x: rect.minX + (clipped.minX - sample.minX) * item.style.zoom,
                                  y: rect.minY + (clipped.minY - sample.minY) * item.style.zoom,
                                  width: clipped.width * item.style.zoom, height: clipped.height * item.style.zoom)
                drawImage(image, in: dest, context: context)
            }
        }
        if item.style.lineWidth > 0 { context.strokeEllipse(in: rect) }
    }
    private static func noteLayout(_ notes: [Annotation], width: CGFloat, state: AnnotationState) -> (height: CGFloat, entries: [(text: String, rect: CGRect)]) {
        guard !notes.isEmpty else { return (0, []) }
        var y: CGFloat = 12
        var entries: [(text: String, rect: CGRect)] = []
        for note in notes {
            let text = "\(state.noteNumber(for: note.id) ?? 1). \(note.text)"
            let textWidth = max(1, width - 24)
            let size = (text as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                     attributes: [.font: NSFont.systemFont(ofSize: 14)]).size
            let height = ceil(size.height) + 2
            entries.append((text, CGRect(x: 12, y: y, width: textWidth, height: height)))
            y += height + 10
        }
        return (ceil(y + 2), entries)
    }
    private static func finite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy { $0.isFinite && abs($0) < 1_000_000 }
    }
    private static func validate(_ state: AnnotationState) throws {
        for item in state.annotations {
            let style = item.style
            guard finite(item.rect), item.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1_000_000 && abs($0.y) < 1_000_000 }),
                  item.magnifierSource.map({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1_000_000 && abs($0.y) < 1_000_000 }) ?? true,
                  [style.lineWidth, style.fontSize, style.opacity, style.cornerRadius, style.pixelSize, style.blurRadius,
                   style.zoom, style.size, style.spotlightDarkness].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10000 }),
                  style.fontSize > 0, style.size > 0, style.zoom >= 1, style.pixelSize >= 1,
                  style.opacity <= 1, style.spotlightDarkness <= 1,
                  [style.color, style.textColor, style.backgroundColor].allSatisfy({ color in
                      [color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
                  }) else { throw AnnotationFailure.invalidGeometry }
        }
    }
}

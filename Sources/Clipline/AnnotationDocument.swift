import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

// All geometry is in original, orientation-normalized pixels with the origin at the top left.
enum AnnotationKind: String, Codable, CaseIterable {
    case hand, rectangle, ellipse, line, arrow, text, bubble, pen, highlighter, pixelate, magnify, step, stamp, spotlight, note, eraser
}
enum AnnotationBoxStyle: String, Codable, CaseIterable { case square, rounded, dashed, roundedDashed }
enum AnnotationArrowStyle: String, Codable, CaseIterable { case open, emphasis, dashed, curved }
enum AnnotationMaskStyle: String, Codable, CaseIterable { case pixelate, blur, solid }
enum AnnotationSpotlightShape: String, Codable, CaseIterable { case ellipse, rectangle }
enum AnnotationNoteStyle: String, Codable, CaseIterable {
    case solidFrame, dashedFrame, roundedFrame, roundedDashedFrame, solidArrow, dashedArrow, curvedArrow
}

struct AnnotationColor: Equatable, Codable {
    enum Space: String, Codable { case sRGB, displayP3 }
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
    var space: Space
    init(_ color: NSColor) {
        let p3 = color.colorSpace == .displayP3
        let converted = color.usingColorSpace(p3 ? .displayP3 : .sRGB) ?? .black
        red = converted.redComponent; green = converted.greenComponent
        blue = converted.blueComponent; alpha = converted.alphaComponent
        space = p3 ? .displayP3 : .sRGB
    }
    var nsColor: NSColor {
        if space == .displayP3 { return NSColor(displayP3Red: red, green: green, blue: blue, alpha: alpha) }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    static let red = AnnotationColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    static let black = AnnotationColor(NSColor.black)
    static let white = AnnotationColor(NSColor.white)
    static let clear = AnnotationColor(NSColor.clear)
}

struct AnnotationStyle: Equatable, Codable {
    var color: AnnotationColor = .red
    var textColor: AnnotationColor = .black
    var backgroundColor: AnnotationColor = .white
    var lineWidth: CGFloat = 4
    var fontName: String = ""
    var fontSize: CGFloat = 24
    var opacity: CGFloat = 1
    var filled = false
    var boxStyle: AnnotationBoxStyle = .square
    var cornerRadius: CGFloat = 12
    var arrowStyle: AnnotationArrowStyle = .open
    var maskStyle: AnnotationMaskStyle = .pixelate
    var pixelSize: CGFloat = 12
    var blurRadius: CGFloat = 12
    var zoom: CGFloat = 2
    var magnifierLinked = false
    var size: CGFloat = 32
    var spotlightShape: AnnotationSpotlightShape = .ellipse
    var spotlightDarkness: CGFloat = 0.55
    var noteStyle: AnnotationNoteStyle = .solidFrame
}

struct Annotation: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var kind: AnnotationKind
    var rect: CGRect = .zero
    var points: [CGPoint] = []
    var text: String = ""
    var style: AnnotationStyle = AnnotationStyle()
    var magnifierSource: CGPoint? = nil

    var bounds: CGRect {
        var geometry: CGRect
        if !points.isEmpty && [.line, .arrow, .pen, .highlighter].contains(kind) {
            geometry = points.reduce(CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        } else { geometry = rect.standardized }
        if kind == .step {
            geometry = CGRect(x: rect.midX - style.size / 2, y: rect.midY - style.size / 2, width: style.size, height: style.size)
        } else if kind == .note {
            geometry = geometry.union(CGRect(x: rect.minX - style.size / 2, y: rect.minY - style.size / 2, width: style.size, height: style.size))
        } else if kind == .bubble {
            let tail = points.last ?? CGPoint(x: rect.midX, y: rect.maxY + 18)
            geometry = geometry.union(CGRect(origin: tail, size: .zero))
        }
        return geometry.insetBy(dx: -max(style.lineWidth, 4) / 2, dy: -max(style.lineWidth, 4) / 2)
    }
    func translated(by offset: CGSize) -> Annotation {
        var result = self
        result.rect = rect.offsetBy(dx: offset.width, dy: offset.height)
        result.points = points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        return result
    }
    func resized(to target: CGRect) -> Annotation {
        var result = self
        let old = rect.standardized
        let target = target.standardized
        result.rect = target
        if kind == .step || kind == .stamp {
            result.style.size = max(1, style.size * min(target.width / max(old.width, 1), target.height / max(old.height, 1)))
        }
        result.points = points.map { point in
            CGPoint(x: target.minX + (point.x - old.minX) * target.width / max(old.width, 1),
                    y: target.minY + (point.y - old.minY) * target.height / max(old.height, 1))
        }
        return result
    }
    func contains(_ point: CGPoint, tolerance: CGFloat = 4) -> Bool {
        if [.pen, .highlighter, .line, .arrow].contains(kind) {
            let path = points.count >= 2 ? points : [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)]
            let radius = max(style.lineWidth / 2, tolerance)
            for index in 1..<path.count {
                let a = path[index - 1], b = path[index]
                let dx = b.x - a.x, dy = b.y - a.y
                let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / max(dx * dx + dy * dy, 0.001)))
                if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= radius { return true }
            }
            return false
        }
        return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}

struct AnnotationState: Equatable, Codable {
    var annotations: [Annotation] = []
    var crop: CGRect? = nil
    func stepNumber(for id: UUID) -> Int? { number(for: id, kind: .step) }
    func noteNumber(for id: UUID) -> Int? { number(for: id, kind: .note) }
    private func number(for id: UUID, kind: AnnotationKind) -> Int? {
        annotations.filter { $0.kind == kind }.firstIndex { $0.id == id }.map { $0 + 1 }
    }
}

enum AnnotationFailure: LocalizedError {
    case unreadable, invalidGeometry, renderFailed, unsupportedFormat, changedSource, noSource, writeFailed
    var errorDescription: String? {
        switch self {
        case .unreadable: return L("The image could not be opened.")
        case .invalidGeometry: return L("The annotation geometry is invalid.")
        case .renderFailed: return L("The annotated image could not be rendered.")
        case .unsupportedFormat: return L("This image format cannot be overwritten safely. Save a PNG copy instead.")
        case .changedSource: return L("The original image was changed or removed. Save a copy instead.")
        case .noSource: return L("This image has no original file. Save a copy instead.")
        case .writeFailed: return L("The annotated image could not be saved.")
        }
    }
}

@MainActor
final class AnnotationDocument {
    let source: CGImage
    let sourceURL: URL?
    let sourceType: String?
    let sourceProperties: [CFString: Any]
    private(set) var state = AnnotationState()
    var onChange: (() -> Void)?
    private var past: [(AnnotationState, String)] = []
    private var future: [(AnnotationState, String)] = []
    private var savedState = AnnotationState()
    private var original: FileVersion?
    private var frameCount = 1
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var isDirty: Bool { state != savedState }
    var undoActionName: String? { past.last?.1 }
    var redoActionName: String? { future.last?.1 }

    init(image: CGImage) {
        source = image; sourceURL = nil; sourceType = nil; sourceProperties = [:]
    }
    init(url: URL) throws {
        let version = try FileVersion.read(url)
        guard let decoder = CGImageSourceCreateWithData(version.bytes as CFData, nil),
              let raw = CGImageSourceCreateImageAtIndex(decoder, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw AnnotationFailure.unreadable }
        sourceProperties = CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = sourceProperties[kCGImagePropertyOrientation] as? Int ?? 1
        source = try AnnotationRenderer.normalized(raw, orientation: orientation)
        sourceURL = url; original = version
        sourceType = CGImageSourceGetType(decoder) as String?
        frameCount = CGImageSourceGetCount(decoder)
    }
    func commit(state next: AnnotationState, label: String) {
        guard next != state else { return }
        past.append((state, label))
        if past.count > 100 { past.removeFirst(past.count - 100) }
        future.removeAll()
        state = next; onChange?()
    }
    func undo() {
        guard let previous = past.popLast() else { return }
        future.append((state, previous.1)); state = previous.0; onChange?()
    }
    func redo() {
        guard let next = future.popLast() else { return }
        past.append((state, next.1)); state = next.0; onChange?()
    }
    func render(includeNotes: Bool = true) throws -> CGImage {
        try AnnotationRenderer.render(source: source, state: state, includeNotes: includeNotes)
    }
    // Export never copies arbitrary source metadata, including embedded thumbnails, GPS or original URLs.
    func encodedData(type: String = UTType.png.identifier, includeNotes: Bool = true) throws -> Data {
        try AnnotationRenderer.encode(try render(includeNotes: includeNotes), type: type, properties: safeProperties)
    }
    private var safeProperties: [CFString: Any] {
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let value = sourceProperties[key] as? NSNumber { properties[key] = value }
        }
        return properties
    }
    func saveOriginal() throws {
        guard let url = sourceURL, let original else { throw AnnotationFailure.noSource }
        guard frameCount == 1, let type = sourceType,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier].contains(type)
        else { throw AnnotationFailure.unsupportedFormat }
        guard try FileVersion.read(url) == original else { throw AnnotationFailure.changedSource }
        let output = try encodedData(type: type)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".clipline-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AnnotationFailure.writeFailed }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var removeTemp = true
        defer { try? file.close(); if removeTemp { try? FileManager.default.removeItem(at: temp) } }
        try file.write(contentsOf: output); try file.synchronize(); try file.close()
        guard try FileVersion.read(url) == original else { throw AnnotationFailure.changedSource }
        let installed = try FileVersion.read(temp)
        // RENAME_SWAP requires an existing destination: a deleted source is never recreated.
        guard renameatx_np(AT_FDCWD, temp.path, AT_FDCWD, url.path, UInt32(RENAME_SWAP)) == 0 else {
            throw AnnotationFailure.changedSource
        }
        let displaced = try? FileVersion.read(temp)
        guard let displaced, displaced.sameContentAndIdentity(as: original) else {
            // A writer won the small check/swap race. Restore the displaced file before reporting conflict.
            removeTemp = false
            if let current = try? FileVersion.read(url), current.sameContentAndIdentity(as: installed),
               renameatx_np(AT_FDCWD, temp.path, AT_FDCWD, url.path, UInt32(RENAME_SWAP)) == 0 {
                // The rollback itself can race another replacement: only discard our own output.
                removeTemp = (try? installed.installedVersion(at: temp)) != nil
            }
            throw AnnotationFailure.changedSource
        }
        // Never adopt an external post-swap replacement as our next overwrite baseline.
        self.original = try installed.installedVersion(at: url)
        savedState = state; onChange?()
    }
}

struct FileVersion: Equatable {
    let device: dev_t
    let inode: ino_t
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    let bytes: Data
    static func read(_ url: URL) throws -> FileVersion {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw AnnotationFailure.changedSource }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG else { throw AnnotationFailure.changedSource }
        let bytes = try file.readToEnd() ?? Data()
        guard fstat(fd, &after) == 0, before.st_ino == after.st_ino, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        else { throw AnnotationFailure.changedSource }
        return FileVersion(device: after.st_dev, inode: after.st_ino,
                           modifiedSeconds: after.st_mtimespec.tv_sec, modifiedNanos: after.st_mtimespec.tv_nsec,
                           changedSeconds: after.st_ctimespec.tv_sec, changedNanos: after.st_ctimespec.tv_nsec, bytes: bytes)
    }
    func installedVersion(at url: URL) throws -> FileVersion {
        let current = try FileVersion.read(url)
        guard current.sameContentAndIdentity(as: self) else { throw AnnotationFailure.changedSource }
        return current
    }
    func sameContentAndIdentity(as other: FileVersion) -> Bool {
        device == other.device && inode == other.inode && bytes == other.bytes
    }
}

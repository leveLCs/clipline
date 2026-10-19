import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

@main
struct AnnotationTests {
    @MainActor static func main() {
        let tests = AnnotationTests()
        let cases: [(String, () throws -> Void)] = [
            ("Snapshot undo redo dirty and 100 limit", tests.history),
            ("Dynamic step numbering and Codable P3 style", tests.numbering),
            ("Exact crop excludes outside pixels", tests.crop),
            ("All eight EXIF orientations", tests.orientations),
            ("Actual source UTI and normalized metadata", tests.formats),
            ("Transparent and Display P3 rendering", tests.color),
            ("Changed deleted replaced sources refuse overwrite", tests.conflicts),
            ("Cancel writes nothing and private atomic output", tests.cancel),
            ("Rollback keeps a concurrently displaced foreign version", tests.rollbackVersion),
            ("Saved baseline accepts only this installed file", tests.installedBaseline),
            ("Spotlight overlap is a union", tests.spotlight),
            ("Three masks use earlier composited pixels", tests.masks),
            ("Magnifier independent source and crop privacy", tests.magnifier),
            ("Wrapped note appendix and bubble tail", tests.notes),
            ("Every drawing tool and frame variant", tests.tools),
            ("Box variants retain fill round corners and dash gaps", tests.boxVariants),
            ("Crop bounds every effect sampling source", tests.effectPrivacy),
            ("Note appendix numbers match cropped badges", tests.noteNumbers),
            ("Export strips hidden metadata and JPEG flattens alpha", tests.exportPrivacy),
            ("Geometry transforms preserve fixed samples and hit bounds", tests.geometry),
            ("Twenty effects finish within one pass budget", tests.effectBudget),
            ("Rectangle spotlight uses corner radius", tests.spotlightCorners),
            ("Invalid geometry fails safely", tests.invalid)
        ]
        for (name, run) in cases {
            let before = failures
            do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(cases.count) checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    @MainActor func history() throws {
        let doc = AnnotationDocument(image: try fixture())
        var notifications = 0
        doc.onChange = { notifications += 1 }
        let item = Annotation(kind: .rectangle, rect: CGRect(x: 2, y: 3, width: 20, height: 12))
        let state = AnnotationState(annotations: [item])
        doc.commit(state: state, label: "Add")
        expect(doc.isDirty && doc.canUndo && !doc.canRedo)
        doc.commit(state: state, label: "Same")
        expect(notifications == 1)
        doc.undo(); expect(doc.state.annotations.isEmpty && !doc.isDirty && doc.canRedo)
        doc.redo(); expect(doc.state == state && doc.isDirty)
        doc.commit(state: AnnotationState(), label: "Delete")
        expect(!doc.isDirty)
        for i in 0..<105 {
            doc.commit(state: AnnotationState(annotations: [Annotation(kind: .text, text: "\(i)")]), label: "Edit")
        }
        for _ in 0..<100 { doc.undo() }
        expect(!doc.canUndo && doc.state.annotations.first?.text == "4")
        doc.commit(state: state, label: "Branch"); expect(!doc.canRedo)
    }

    func numbering() throws {
        let one = Annotation(kind: .step)
        let two = Annotation(kind: .step)
        var state = AnnotationState(annotations: [one, Annotation(kind: .text), two])
        expect(state.stepNumber(for: two.id) == 2)
        state.annotations.removeFirst(); expect(state.stepNumber(for: two.id) == 1)
        var style = AnnotationStyle()
        style.color = AnnotationColor(NSColor(displayP3Red: 0.9, green: 0.2, blue: 0.1, alpha: 0.6))
        state.annotations[0].style = style
        let roundtrip = try JSONDecoder().decode(AnnotationState.self, from: JSONEncoder().encode(state))
        expect(roundtrip == state && roundtrip.annotations[0].style.color.space == .displayP3)
    }

    func crop() throws {
        let source = try fixture(width: 80, height: 50, bands: true)
        let state = AnnotationState(crop: CGRect(x: 30, y: 11, width: 17, height: 23))
        let result = try AnnotationRenderer.render(source: source, state: state)
        expect(result.width == 17 && result.height == 23)
        for point in [(0, 0), (16, 22), (8, 10)] {
            let p = pixel(result, point.0, point.1)
            expect(p.g > 240 && p.r < 15 && p.b < 15)
        }
        let clipped = try AnnotationRenderer.render(source: source, state: AnnotationState(crop: CGRect(x: -2, y: 3, width: 9, height: 8)))
        expect(clipped.width == 7 && clipped.height == 8)
    }

    @MainActor func orientations() throws {
        // Six unique 10x10 blocks in a 3x2 asymmetric grid; expected rows are hand-derived EXIF transforms.
        let source = try pattern()
        let expected: [[Int]] = [[1,2,3,4,5,6], [3,2,1,6,5,4], [6,5,4,3,2,1], [4,5,6,1,2,3],
                                 [1,4,2,5,3,6], [4,1,5,2,6,3], [6,3,5,2,4,1], [3,6,2,5,1,4]]
        try withFolder { folder in
            for orientation in 1...8 {
                let url = folder.appendingPathComponent("\(orientation).tiff")
                try encode(source, url, UTType.tiff.identifier, [kCGImagePropertyOrientation: orientation])
                let doc = try AnnotationDocument(url: url)
                let image = try doc.render(includeNotes: false)
                let columns = orientation >= 5 ? 2 : 3
                expect(image.width == columns * 10 && image.height == (6 / columns) * 10)
                let values = (0..<6).map { index in Int(pixel(image, (index % columns) * 10 + 5, (index / columns) * 10 + 5).r) / 30 }
                expect(values == expected[orientation - 1])
            }
        }
    }

    @MainActor func formats() throws {
        try withFolder { folder in
            for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier] {
                let url = folder.appendingPathComponent(UUID().uuidString + ".wrong")
                try encode(fixture(), url, type)
                let doc = try AnnotationDocument(url: url)
                doc.commit(state: AnnotationState(crop: CGRect(x: 2, y: 3, width: 21, height: 17)), label: "Crop")
                try doc.saveOriginal()
                let source = try require(CGImageSourceCreateWithURL(url as CFURL, nil))
                expect(CGImageSourceGetType(source) as String? == type)
                expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width == 21)
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                expect((properties?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
                expect(!doc.isDirty)
                doc.undo(); expect(doc.isDirty)
            }
            let multi = folder.appendingPathComponent("multi.tiff")
            let destination = try require(CGImageDestinationCreateWithURL(multi as CFURL, UTType.tiff.identifier as CFString, 2, nil))
            CGImageDestinationAddImage(destination, try fixture(), nil)
            CGImageDestinationAddImage(destination, try fixture(), nil)
            expect(CGImageDestinationFinalize(destination))
            let bytes = try Data(contentsOf: multi)
            let doc = try AnnotationDocument(url: multi)
            expectThrows { try doc.saveOriginal() }
            expect(try Data(contentsOf: multi) == bytes)
        }
    }

    func color() throws {
        let transparent = try fixture(alpha: true)
        let image = try AnnotationRenderer.render(source: transparent, state: AnnotationState())
        expect(pixel(image, 0, 0).a == 0)
        let p3 = try fixture(space: CGColorSpace(name: CGColorSpace.displayP3)!)
        let rendered = try AnnotationRenderer.render(source: p3, state: AnnotationState())
        expect(rendered.colorSpace?.name == CGColorSpace.displayP3)
        let encoded = try AnnotationRenderer.encode(rendered)
        let decoded = try require(CGImageSourceCreateWithData(encoded as CFData, nil))
        expect(CGImageSourceCreateImageAtIndex(decoded, 0, nil)?.colorSpace?.name == CGColorSpace.displayP3)
        let alphaData = try AnnotationRenderer.encode(image)
        let alphaSource = try require(CGImageSourceCreateWithData(alphaData as CFData, nil))
        expect(pixel(try require(CGImageSourceCreateImageAtIndex(alphaSource, 0, nil)), 0, 0).a == 0)
    }

    @MainActor func conflicts() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("source.png")
            try encode(fixture(), url, UTType.png.identifier)
            let original = try Data(contentsOf: url)
            let changed = try AnnotationDocument(url: url)
            try encode(fixture(width: 90), url, UTType.png.identifier)
            let newBytes = try Data(contentsOf: url)
            expectThrows { try changed.saveOriginal() }; expect(try Data(contentsOf: url) == newBytes)
            try original.write(to: url)
            let deleted = try AnnotationDocument(url: url)
            try FileManager.default.removeItem(at: url)
            expectThrows { try deleted.saveOriginal() }; expect(!FileManager.default.fileExists(atPath: url.path))
            try original.write(to: url)
            let replaced = try AnnotationDocument(url: url)
            try FileManager.default.removeItem(at: url); try original.write(to: url)
            expectThrows { try replaced.saveOriginal() }
        }
    }

    @MainActor func cancel() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("source.png")
            try encode(fixture(), url, UTType.png.identifier)
            let original = try Data(contentsOf: url)
            let doc = try AnnotationDocument(url: url)
            doc.commit(state: AnnotationState(annotations: [Annotation(kind: .text, text: "Secret")]), label: "Edit")
            _ = try doc.render()
            expect(try Data(contentsOf: url) == original)
            expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
            try doc.saveOriginal()
            expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            expectThrows { try AnnotationDocument(image: fixture()).saveOriginal() }
        }
    }

    func rollbackVersion() throws {
        try withFolder { folder in
            let target = folder.appendingPathComponent("target")
            let temp = folder.appendingPathComponent("temp")
            let installedBytes = Data("our encoded output".utf8)
            let displacedBytes = Data("first external version".utf8)
            let laterBytes = Data("second external version".utf8)
            // The rollback precheck sees our output, then another writer replaces it before RENAME_SWAP.
            try installedBytes.write(to: target)
            let installed = try FileVersion.read(target)
            _ = try installed.installedVersion(at: target)
            try displacedBytes.write(to: temp)
            try laterBytes.write(to: target, options: .atomic)
            expect(renameatx_np(AT_FDCWD, temp.path, AT_FDCWD, target.path, UInt32(RENAME_SWAP)) == 0)
            if (try? installed.installedVersion(at: temp)) != nil { try FileManager.default.removeItem(at: temp) }
            expect(try Data(contentsOf: target) == displacedBytes)
            expect(FileManager.default.fileExists(atPath: temp.path))
            if FileManager.default.fileExists(atPath: temp.path) { expect(try Data(contentsOf: temp) == laterBytes) }

            // Without the intervening writer the rollback temp really is ours and can be removed.
            let ownTarget = folder.appendingPathComponent("own-target")
            let ownTemp = folder.appendingPathComponent("own-temp")
            try installedBytes.write(to: ownTarget)
            let own = try FileVersion.read(ownTarget)
            try displacedBytes.write(to: ownTemp)
            expect(renameatx_np(AT_FDCWD, ownTemp.path, AT_FDCWD, ownTarget.path, UInt32(RENAME_SWAP)) == 0)
            if (try? own.installedVersion(at: ownTemp)) != nil { try FileManager.default.removeItem(at: ownTemp) }
            expect(!FileManager.default.fileExists(atPath: ownTemp.path))
            expect(try Data(contentsOf: ownTarget) == displacedBytes)
        }
    }

    func installedBaseline() throws {
        try withFolder { folder in
            let target = folder.appendingPathComponent("target")
            let bytes = Data("our encoded output".utf8)
            try bytes.write(to: target)
            let installed = try FileVersion.read(target)
            expect(try installed.installedVersion(at: target).sameContentAndIdentity(as: installed))
            let external = Data("external post-swap replacement".utf8)
            let writer = try FileHandle(forWritingTo: target)
            try writer.truncate(atOffset: 0); try writer.write(contentsOf: external); try writer.close()
            expectThrows { _ = try installed.installedVersion(at: target) }
            expect(try Data(contentsOf: target) == external)
            try external.write(to: target, options: .atomic)
            expectThrows { _ = try installed.installedVersion(at: target) }
            expect(try Data(contentsOf: target) == external)
            // Matching bytes on a different inode still belong to another writer.
            try bytes.write(to: target, options: .atomic)
            expectThrows { _ = try installed.installedVersion(at: target) }
            try FileManager.default.removeItem(at: target)
            expectThrows { _ = try installed.installedVersion(at: target) }
        }
    }

    func spotlight() throws {
        var style = AnnotationStyle(); style.spotlightShape = .rectangle; style.spotlightDarkness = 0.6
        let image = try AnnotationRenderer.render(source: fixture(), state: AnnotationState(annotations: [
            Annotation(kind: .spotlight, rect: CGRect(x: 5, y: 5, width: 35, height: 30), style: style),
            Annotation(kind: .spotlight, rect: CGRect(x: 25, y: 5, width: 35, height: 30), style: style)]))
        expect(pixel(image, 10, 10).r > 245 && pixel(image, 30, 10).r > 245 && pixel(image, 50, 10).r > 245)
        expect(abs(Int(pixel(image, 65, 40).r) - 102) < 5)
    }

    func masks() throws {
        for mode in AnnotationMaskStyle.allCases {
            var style = AnnotationStyle(); style.color = .red; style.filled = true; style.lineWidth = 0
            let prior = Annotation(kind: .rectangle, rect: CGRect(x: 4, y: 4, width: 48, height: 30), style: style)
            style.maskStyle = mode; style.color = .black; style.pixelSize = 8; style.blurRadius = 4
            let mask = Annotation(kind: .pixelate, rect: CGRect(x: 8, y: 8, width: 35, height: 20), style: style)
            let image = try AnnotationRenderer.render(source: fixture(), state: AnnotationState(annotations: [prior, mask]))
            let center = pixel(image, 25, 18)
            if mode == .solid { expect(center.r < 10 && center.g < 10) }
            else { expect(center.r > 230 && center.g < 25) }
            expect(pixel(image, 65, 40).r > 245)
        }
    }

    func magnifier() throws {
        var style = AnnotationStyle(); style.lineWidth = 0; style.zoom = 2
        let glass = Annotation(kind: .magnify, rect: CGRect(x: 45, y: 10, width: 24, height: 24), style: style,
                               magnifierSource: CGPoint(x: 10, y: 20))
        let source = try fixture(width: 80, height: 50, bands: true)
        let image = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [glass]))
        expect(pixel(image, 57, 22).r > 240 && pixel(image, 57, 22).g < 15)
        let cropped = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [glass], crop: CGRect(x: 30, y: 0, width: 50, height: 50)))
        let center = pixel(cropped, 27, 22)
        expect(!(center.r > 240 && center.g < 15 && center.b < 15))
    }

    func notes() throws {
        let short = Annotation(kind: .note, rect: CGRect(x: 5, y: 4, width: 15, height: 20), text: "Short")
        var long = short; long.text = String(repeating: "A wrapped note with words. ", count: 30)
        let source = try fixture(width: 220, height: 70)
        let first = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [short]))
        let second = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [long]))
        expect(second.height > first.height + 100)
        expect(try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [long]), includeNotes: false).height == 70)
        var style = AnnotationStyle(); style.filled = true; style.backgroundColor = .red; style.color = .red
        let bubble = Annotation(kind: .bubble, rect: CGRect(x: 20, y: 5, width: 35, height: 20),
                                points: [CGPoint(x: 35, y: 40)], style: style)
        let image = try AnnotationRenderer.render(source: fixture(), state: AnnotationState(annotations: [bubble]))
        expect(pixel(image, 35, 33).g < 100)
    }

    func tools() throws {
        let source = try fixture(width: 150, height: 100)
        for kind in AnnotationKind.allCases where ![.hand, .eraser, .spotlight].contains(kind) {
            let item = Annotation(kind: kind, rect: CGRect(x: 20, y: 20, width: 65, height: 45),
                                  points: [CGPoint(x: 20, y: 30), CGPoint(x: 85, y: 50)], text: kind == .stamp ? "✅" : "Hello")
            let image = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [item]), includeNotes: false)
            // Each tool must alter at least one source pixel in its geometry.
            var count = 0
            for y in stride(from: 15, to: 75, by: 3) { for x in stride(from: 15, to: 100, by: 3) {
                let value = pixel(image, x, y); if value.r < 235 || value.g < 235 || value.b < 235 { count += 1 }
            } }
            if kind != .pixelate && kind != .magnify { expect(count > 0) }
        }
        for variant in AnnotationNoteStyle.allCases {
            var style = AnnotationStyle(); style.noteStyle = variant
            let note = Annotation(kind: .note, rect: CGRect(x: 15, y: 15, width: 65, height: 35), text: "A note", style: style)
            _ = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [note]))
        }
    }

    func boxVariants() throws {
        let source = try fixture()
        var style = AnnotationStyle(); style.lineWidth = 2
        let rect = CGRect(x: 10, y: 10, width: 50, height: 30)
        func draw(_ value: AnnotationStyle) throws -> CGImage {
            try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [Annotation(kind: .rectangle, rect: rect, style: value)]))
        }
        let square = try draw(style)
        expect(pixel(square, 10, 10).g < 100 && pixel(square, 30, 25).g > 240)
        style.boxStyle = .rounded; style.cornerRadius = 12
        let rounded = try draw(style)
        expect(pixel(rounded, 10, 10).g > 240 && pixel(rounded, 35, 10).g < 100)
        style.boxStyle = .dashed
        let dashed = try draw(style)
        let samples = (14..<55).map { pixel(dashed, $0, 10).g }
        expect(samples.contains { $0 < 100 } && samples.contains { $0 > 240 })
        style.filled = true
        expect(pixel(try draw(style), 30, 25).g < 100)
    }

    func effectPrivacy() throws {
        let source = try fixture(width: 80, height: 50, bands: true)
        let crop = CGRect(x: 30, y: 11, width: 17, height: 23)
        for mode in [AnnotationMaskStyle.blur, .pixelate] {
            var style = AnnotationStyle(); style.maskStyle = mode; style.blurRadius = 12; style.pixelSize = 16
            let mask = Annotation(kind: .pixelate, rect: CGRect(x: 20, y: 0, width: 40, height: 50), style: style)
            let image = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [mask], crop: crop))
            for point in [(0, 0), (16, 22), (8, 10)] {
                let p = pixel(image, point.0, point.1)
                expect(p.g > 240 && p.r < 15 && p.b < 15)
            }
        }
        var glassStyle = AnnotationStyle(); glassStyle.lineWidth = 0
        let glass = Annotation(kind: .magnify, rect: CGRect(x: 45, y: 10, width: 24, height: 24), style: glassStyle,
                               magnifierSource: CGPoint(x: 10, y: 20))
        var maskStyle = AnnotationStyle(); maskStyle.maskStyle = .blur; maskStyle.blurRadius = 1
        let mask = Annotation(kind: .pixelate, rect: CGRect(x: 51, y: 16, width: 12, height: 12), style: maskStyle)
        let layered = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [glass, mask]))
        expect(pixel(layered, 57, 22).r > 240 && pixel(layered, 57, 22).g < 15)
    }

    func noteNumbers() throws {
        let source = try fixture(width: 220, height: 70)
        let visible = Annotation(kind: .note, rect: CGRect(x: 30, y: 20, width: 30, height: 20), text: "Visible note")
        let outside = Annotation(kind: .note, rect: CGRect(x: -150, y: -150, width: 20, height: 20), text: "Hidden note")
        let one = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [visible]))
        let two = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [outside, visible]))
        let appendix = CGRect(x: 0, y: 70, width: one.width, height: one.height - 70)
        expect(try AnnotationRenderer.encode(require(one.cropping(to: appendix))) != AnnotationRenderer.encode(require(two.cropping(to: appendix))))
    }

    @MainActor func exportPrivacy() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("private.png")
            try encode(fixture(), url, UTType.png.identifier, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: url.absoluteString],
                                                               kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144])
            let doc = try AnnotationDocument(url: url)
            let data = try doc.encodedData()
            expect(data.range(of: Data(url.absoluteString.utf8)) == nil)
            let decoder = try require(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any]
            expect((properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0 > 143)
            let jpeg = try AnnotationRenderer.encode(fixture(alpha: true), type: UTType.jpeg.identifier)
            let decoded = try require(CGImageSourceCreateWithData(jpeg as CFData, nil))
            let image = try require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            expect(pixel(image, 10, 10).r > 245 && pixel(image, 10, 10).g > 245)
            if (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(UTType.heic.identifier) {
                let heic = try AnnotationRenderer.encode(fixture(), type: UTType.heic.identifier)
                expect(CGImageSourceGetType(try require(CGImageSourceCreateWithData(heic as CFData, nil))) as String? == UTType.heic.identifier)
            }
        }
    }

    func geometry() throws {
        let item = Annotation(kind: .magnify, rect: CGRect(x: 20, y: 10, width: 20, height: 20),
                              magnifierSource: CGPoint(x: 5, y: 6))
        let moved = item.translated(by: CGSize(width: 10, height: 4))
        expect(moved.rect.origin == CGPoint(x: 30, y: 14) && moved.magnifierSource == CGPoint(x: 5, y: 6))
        let step = Annotation(kind: .step, rect: CGRect(x: 20, y: 20, width: 10, height: 10))
        expect(step.contains(CGPoint(x: 11, y: 25), tolerance: 0))
        expect(step.resized(to: CGRect(x: 20, y: 20, width: 20, height: 20)).style.size == 64)
        let bubble = Annotation(kind: .bubble, rect: CGRect(x: 10, y: 5, width: 20, height: 15), points: [CGPoint(x: 20, y: 40)])
        expect(bubble.bounds.contains(CGPoint(x: 20, y: 39)))
        let line = Annotation(kind: .line, rect: CGRect(x: 0, y: 0, width: 40, height: 20),
                              points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20)])
        expect(line.contains(CGPoint(x: 20, y: 10)) && !line.contains(CGPoint(x: 1, y: 19)))
        expect(line.resized(to: CGRect(x: 10, y: 10, width: 80, height: 40)).points.last == CGPoint(x: 90, y: 50))
    }

    func effectBudget() throws {
        let source = try fixture()
        var style = AnnotationStyle(); style.maskStyle = .blur; style.blurRadius = 1
        let annotations = (0..<20).map { _ in Annotation(kind: .pixelate, rect: CGRect(x: 10, y: 10, width: 16, height: 16), style: style) }
        let finished = DispatchSemaphore(value: 0)
        let outcome = RenderOutcome()
        DispatchQueue.global().async {
            defer { finished.signal() }
            if let image = try? AnnotationRenderer.render(source: source, state: AnnotationState(annotations: annotations)) {
                outcome.succeeded = image.width == 80 && image.height == 50
            }
        }
        if finished.wait(timeout: .now() + 3) == .success { expect(outcome.succeeded) }
        else { expect(false) }
    }

    func spotlightCorners() throws {
        var style = AnnotationStyle(); style.spotlightShape = .rectangle
        style.cornerRadius = 10; style.spotlightDarkness = 0.6
        let spot = Annotation(kind: .spotlight, rect: CGRect(x: 10, y: 10, width: 30, height: 30), style: style)
        let image = try AnnotationRenderer.render(source: fixture(), state: AnnotationState(annotations: [spot]))
        expect(pixel(image, 11, 11).r < 130 && pixel(image, 25, 12).r > 245)
    }

    func invalid() throws {
        let source = try fixture()
        expectThrows { _ = try AnnotationRenderer.render(source: source, state: AnnotationState(crop: .zero)) }
        expectThrows { _ = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [Annotation(kind: .line, rect: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10))])) }
    }
}

private final class RenderOutcome { var succeeded = false }
private var failures = 0
private struct MissingValue: Error {}
private func require<T>(_ value: T?) throws -> T { guard let value else { throw MissingValue() }; return value }
private func expect(_ condition: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition { failures += 1; print("FAIL \(file):\(line)") }
}
private func expectThrows(_ body: () throws -> Void) { do { try body(); expect(false) } catch {} }
private func withFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}
private func encode(_ image: CGImage, _ url: URL, _ type: String, _ props: [CFString: Any] = [:]) throws {
    let destination = try require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, props as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw MissingValue() }
}
private func fixture(width: Int = 80, height: Int = 50, alpha: Bool = false, bands: Bool = false,
                     space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> CGImage {
    let ctx = try require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    if !alpha { ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    if bands {
        ctx.setFillColor(CGColor(colorSpace: space, components: [1, 0, 0, 1])!); ctx.fill(CGRect(x: 0, y: 0, width: 25, height: height))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0, 1, 0, 1])!); ctx.fill(CGRect(x: 25, y: 0, width: 30, height: height))
        ctx.setFillColor(CGColor(colorSpace: space, components: [0, 0, 1, 1])!); ctx.fill(CGRect(x: 55, y: 0, width: 25, height: height))
    }
    return try require(ctx.makeImage())
}
private func pattern() throws -> CGImage {
    let ctx = try require(CGContext(data: nil, width: 30, height: 20, bitsPerComponent: 8, bytesPerRow: 120,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.translateBy(x: 0, y: 20); ctx.scaleBy(x: 1, y: -1)
    for i in 0..<6 {
        ctx.setFillColor(CGColor(red: CGFloat((i + 1) * 30) / 255, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: (i % 3) * 10, y: (i / 3) * 10, width: 10, height: 10))
    }
    return try require(ctx.makeImage())
}
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    var bytes = [UInt8](repeating: 0, count: 4)
    bytes.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: -CGFloat(x), y: CGFloat(y) - CGFloat(image.height) + 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return (bytes[0], bytes[1], bytes[2], bytes[3])
}

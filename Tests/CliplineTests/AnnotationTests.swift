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
            ("Saved annotations reopen as editable elements over the original", tests.persistence),
            ("Editable archives survive rename and copies remain independent", tests.archiveCopies),
            ("Identical flat images retain distinct editable documents", tests.archiveIdentity),
            ("Archive failure and external image changes preserve originals", tests.archiveFailures),
            ("System metadata changes do not block unchanged image saves", tests.archiveSystemMetadata),
            ("Missing corrupt and unsupported archives never silently restore", tests.archiveRecovery),
            ("Archive keeps crop notes P3 and transparency while exports stay flat", tests.archivePrivacy),
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
            ("Note appendix uses each note font for wrapping and glyphs", tests.noteTypography),
            ("Every drawing tool and frame variant", tests.tools),
            ("Box variants retain fill round corners and dash gaps", tests.boxVariants),
            ("Crop bounds every effect sampling source", tests.effectPrivacy),
            ("Note appendix numbers match cropped badges", tests.noteNumbers),
            ("Export strips hidden metadata and JPEG flattens alpha", tests.exportPrivacy),
            ("Geometry transforms preserve fixed samples and hit bounds", tests.geometry),
            ("Twenty effects finish within one pass budget", tests.effectBudget),
            ("Rectangle spotlight uses corner radius", tests.spotlightCorners),
            ("Invalid geometry fails safely", tests.invalid),
            ("Canvas source transforms and pointer zoom roundtrip", tests.canvasCoordinates),
            ("Canvas reverse drag Shift and crop geometry", tests.canvasGeometry),
            ("Canvas degenerate lines and point pen hit geometry", tests.canvasDegenerate),
            ("Canvas gestures create every tool and commit once", tests.canvasGestures),
            ("Canvas move magnifier resize crop and history", tests.canvasEditing),
            ("Canvas reselect old annotations across drawing tools", tests.canvasReselect),
            ("Canvas selection preserves nested drawing and brush strokes", tests.canvasSelectionDrawing),
            ("Badge background and text color share style semantics", tests.badgeColors),
            ("Renderer throwing effects restore caller clipping", tests.throwingEffects),
            ("Blur and pixelation change high contrast source pixels", tests.patternMasks),
            ("Native text composition and image copy routing", tests.canvasText),
            ("Canvas crop handles source sample and point clicks", tests.canvasHandles),
            ("Curved arrows select and erase visible geometry", tests.curvedArrowHit),
            ("Shift crop remains square against source edges", tests.squareCropEdges),
            ("Arrow notes retain gesture direction and tail badges", tests.noteArrowGestures),
            ("Fractional crop matches output through gestures and square edges", tests.fractionalCrop)
        ]
        for (name, run) in cases {
            let before = failures
            do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(cases.count) checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    @MainActor func persistence() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("editable.png")
            try encode(fixture(width: 800, height: 600), url, UTType.png.identifier)
            let doc = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            let arrow = Annotation(kind: .arrow, rect: CGRect(x: 40, y: 50, width: 200, height: 100),
                                   points: [CGPoint(x: 40, y: 50), CGPoint(x: 240, y: 150)])
            let line = Annotation(kind: .line, points: [CGPoint(x: 300, y: 200), CGPoint(x: 500, y: 200)])
            let text = Annotation(kind: .text, rect: CGRect(x: 30, y: 300, width: 250, height: 80), text: "可繼續編輯")
            let state = AnnotationState(annotations: [arrow, line, text], crop: CGRect(x: 10, y: 20, width: 650, height: 500))
            doc.commit(state: state, label: "Fixture")
            let expected = try doc.encodedData()
            try doc.saveOriginal()
            let reopened = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            expect(reopened.state == state)
            expect(reopened.source.width == 800 && reopened.source.height == 600)
            expect(!reopened.isDirty && !reopened.canUndo && !reopened.canRedo)
            expect(try reopened.encodedData() == expected)
            let canvas = AnnotationCanvas(document: reopened)
            canvas.selectTool(.hand)
            canvas.beginInteraction(at: CGPoint(x: 140, y: 100))
            canvas.updateInteraction(to: CGPoint(x: 160, y: 120)); canvas.endInteraction()
            expect(reopened.state.annotations[0].points == [CGPoint(x: 60, y: 70), CGPoint(x: 260, y: 170)])
            canvas.beginInteraction(at: CGPoint(x: 260, y: 170))
            canvas.updateInteraction(to: CGPoint(x: 280, y: 190)); canvas.endInteraction()
            expect(reopened.state.annotations[0].points.last == CGPoint(x: 280, y: 190))
            canvas.selectedID = text.id; canvas.updateSelectedText("再次編輯")
            let edited = reopened.state
            let secondOutput = try reopened.encodedData()
            try reopened.saveOriginal()
            let second = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            expect(second.state == edited && second.state.annotations.count == 3)
            expect(try second.encodedData() == secondOutput)
            var cleared = second.state; cleared.annotations = []; cleared.crop = nil
            second.commit(state: cleared, label: "Remove all")
            expect(try second.encodedData() == AnnotationRenderer.encode(fixture(width: 800, height: 600)))
        }
    }

    @MainActor func archiveCopies() throws {
        try withFolder { folder in
            let archives = folder.appendingPathComponent("archives")
            let url = folder.appendingPathComponent("original.png"), renamed = folder.appendingPathComponent("renamed.png")
            let copy = folder.appendingPathComponent("copy.png")
            try encode(fixture(), url, UTType.png.identifier)
            let doc = try AnnotationDocument(url: url, archiveDirectory: archives)
            let state = AnnotationState(annotations: [Annotation(kind: .text, text: "One")])
            doc.commit(state: state, label: "Fixture"); try doc.saveOriginal()
            let firstID = try require(FileVersion.read(url).annotationID)
            try FileManager.default.moveItem(at: url, to: renamed)
            try FileManager.default.copyItem(at: renamed, to: copy)
            let moved = try AnnotationDocument(url: renamed, archiveDirectory: archives)
            let copied = try AnnotationDocument(url: copy, archiveDirectory: archives)
            expect(moved.state == state && copied.state == state)
            var changed = state; changed.annotations[0].text = "Independent"
            copied.commit(state: changed, label: "Edit copy"); try copied.saveOriginal()
            expect(try FileVersion.read(copy).annotationID != firstID)
            expect(try AnnotationDocument(url: renamed, archiveDirectory: archives).state == state)
            expect(try AnnotationDocument(url: copy, archiveDirectory: archives).state == changed)
            expect(FileManager.default.fileExists(atPath: archives.appendingPathComponent(firstID + ".json").path))
        }
    }

    @MainActor func archiveIdentity() throws {
        try withFolder { folder in
            let archives = folder.appendingPathComponent("archives")
            let a = folder.appendingPathComponent("a.png"), b = folder.appendingPathComponent("b.png")
            try encode(fixture(bands: false), a, UTType.png.identifier)
            try encode(fixture(bands: true), b, UTType.png.identifier)
            let first = try AnnotationDocument(url: a, archiveDirectory: archives)
            let second = try AnnotationDocument(url: b, archiveDirectory: archives)
            var mask = Annotation(kind: .pixelate, rect: CGRect(x: 0, y: 0, width: 80, height: 50))
            mask.style.maskStyle = .solid; mask.style.color = .black
            first.commit(state: AnnotationState(annotations: [mask]), label: "Mask")
            mask.id = UUID()
            second.commit(state: AnnotationState(annotations: [mask]), label: "Mask")
            try first.saveOriginal(); try second.saveOriginal()
            expect(try Data(contentsOf: a) == Data(contentsOf: b))
            expect(try FileVersion.read(a).annotationID != FileVersion.read(b).annotationID)
            let reopenedA = try AnnotationDocument(url: a, archiveDirectory: archives)
            let reopenedB = try AnnotationDocument(url: b, archiveDirectory: archives)
            expect(reopenedA.state == first.state && reopenedB.state == second.state)
            expect(pixel(reopenedA.source, 5, 5).g > 240 && pixel(reopenedB.source, 5, 5).g < 15)
        }
    }

    @MainActor func archiveFailures() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("source.png"), archives = folder.appendingPathComponent("archives")
            try encode(fixture(), url, UTType.png.identifier)
            let before = try FileVersion.read(url)
            try Data("blocked directory".utf8).write(to: archives)
            let doc = try AnnotationDocument(url: url, archiveDirectory: archives)
            doc.commit(state: AnnotationState(annotations: [Annotation(kind: .text, text: "Keep edits")]), label: "Edit")
            expectThrows { try doc.saveOriginal() }
            expect(try FileVersion.read(url) == before && doc.isDirty)
            try FileManager.default.removeItem(at: archives)
            try doc.saveOriginal()
            let saved = try FileVersion.read(url)
            let id = try require(saved.annotationID)
            let archive = archives.appendingPathComponent(id + ".json"), archiveBytes = try Data(contentsOf: archive)
            let current = try AnnotationDocument(url: url, archiveDirectory: archives)
            // A content-only external edit preserves xattrs but must never resurrect the old pixels.
            let foreign = try AnnotationRenderer.encode(fixture(width: 90))
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0); try handle.write(contentsOf: foreign); try handle.close()
            expectThrows { try current.saveOriginal() }
            let external = try AnnotationDocument(url: url, archiveDirectory: archives)
            expect(external.state.annotations.isEmpty && external.source.width == 90 && external.restorationNotice != nil)
            expect(try Data(contentsOf: archive) == archiveBytes && Data(contentsOf: url) == foreign)
            // Attribute-only changes are also a conflicting version.
            let baseline = try FileVersion.read(url)
            let fd = open(url.path, O_WRONLY); defer { close(fd) }
            try AnnotationArchive.attach(UUID().uuidString, to: fd)
            expect(try FileVersion.read(url) != baseline)
            expectThrows { _ = try baseline.installedVersion(at: url) }
            expectThrows { try AnnotationArchive.attach(id, to: -1) }
        }
    }

    @MainActor func archiveSystemMetadata() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("image.png"), archives = folder.appendingPathComponent("archives")
            try encode(fixture(), url, UTType.png.identifier)
            let doc = try AnnotationDocument(url: url, archiveDirectory: archives)
            doc.commit(state: AnnotationState(annotations: [Annotation(kind: .text, text: "Keep")]), label: "Edit")
            let before = try FileVersion.read(url)
            let fd = open(url.path, O_WRONLY); defer { close(fd) }
            let metadata = Data("system metadata fixture".utf8)
            expect(metadata.withUnsafeBytes { fsetxattr(fd, "io.github.leveLCs.Clipline.test", $0.baseAddress, $0.count, 0, 0) } == 0)
            expect(try FileVersion.read(url) != before)
            try doc.saveOriginal()
            expect(!doc.isDirty)
            expect(try AnnotationDocument(url: url, archiveDirectory: archives).state == doc.state)
        }
    }

    @MainActor func archiveRecovery() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("image.png"), archives = folder.appendingPathComponent("archives")
            try encode(fixture(), url, UTType.png.identifier)
            let doc = try AnnotationDocument(url: url, archiveDirectory: archives)
            doc.commit(state: AnnotationState(annotations: [Annotation(kind: .text, text: "Saved")]), label: "Edit")
            try doc.saveOriginal()
            let image = try FileVersion.read(url)
            let id = try require(image.annotationID), archive = archives.appendingPathComponent(id + ".json")
            let bytes = try Data(contentsOf: archive)
            try FileManager.default.removeItem(at: archive)
            let flat = try AnnotationDocument(url: url, archiveDirectory: archives)
            expect(flat.state.annotations.isEmpty && flat.restorationNotice != nil)
            try Data("broken".utf8).write(to: archive)
            expectThrows { _ = try AnnotationDocument(url: url, archiveDirectory: archives) }
            var record = try JSONDecoder().decode(AnnotationArchive.Record.self, from: bytes)
            record.version = 999
            try JSONEncoder().encode(record).write(to: archive)
            expectThrows { _ = try AnnotationDocument(url: url, archiveDirectory: archives) }
            record.version = 1; record.state.annotations[0].style.zoom = -1
            try JSONEncoder().encode(record).write(to: archive)
            expectThrows { _ = try AnnotationDocument(url: url, archiveDirectory: archives) }
            expect(try FileVersion.read(url) == image)
            try bytes.write(to: archive)
            expect(try AnnotationDocument(url: url, archiveDirectory: archives).state == doc.state)
            expectThrows { _ = try AnnotationArchive.load("../../escape", in: archives) }
            let fd = open(url.path, O_WRONLY); defer { close(fd) }
            let invalid = Data("../../escape".utf8)
            expect(invalid.withUnsafeBytes { fsetxattr(fd, AnnotationArchive.attribute, $0.baseAddress, $0.count, 0, 0) } == 0)
            expectThrows { _ = try AnnotationDocument(url: url, archiveDirectory: archives) }
        }
    }

    @MainActor func archivePrivacy() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("image.png"), archives = folder.appendingPathComponent("archives")
            try encode(fixture(width: 400, height: 300, alpha: true, space: CGColorSpace(name: CGColorSpace.displayP3)!), url, UTType.png.identifier)
            let doc = try AnnotationDocument(url: url, archiveDirectory: archives)
            let note = Annotation(kind: .note, rect: CGRect(x: 50, y: 50, width: 80, height: 40), text: "Private editable note")
            doc.commit(state: AnnotationState(annotations: [note], crop: CGRect(x: 30, y: 30, width: 220, height: 160)), label: "Crop and note")
            let output = try doc.encodedData()
            try doc.saveOriginal()
            let opened = try AnnotationDocument(url: url, archiveDirectory: archives)
            expect(opened.source.width == 400 && opened.source.height == 300 && opened.state == doc.state)
            expect(opened.source.colorSpace?.name == CGColorSpace.displayP3 && pixel(opened.source, 0, 0).a == 0)
            expect(try opened.encodedData() == output)
            try opened.saveOriginal()
            expect(try Data(contentsOf: url) == output)
            let id = try require(FileVersion.read(url).annotationID)
            let archive = archives.appendingPathComponent(id + ".json")
            expect((try FileManager.default.attributesOfItem(atPath: archives.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            expect((try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            for type in [UTType.png.identifier, UTType.jpeg.identifier] {
                let exported = folder.appendingPathComponent(UUID().uuidString)
                try opened.encodedData(type: type).write(to: exported)
                expect(try FileVersion.read(exported).annotationID == nil)
                let flat = try AnnotationDocument(url: exported, archiveDirectory: archives)
                expect(flat.state.annotations.isEmpty && flat.restorationNotice == nil)
                expect(flat.source.width == 220 && flat.source.height > 160)
                let metadata = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(exported as CFURL, nil)!, 0, nil) as? [String: Any]
                expect(!String(describing: metadata).contains("sourcePNG") && !String(describing: metadata).contains(id))
            }
        }
    }

    func canvasCoordinates() throws {
        var transform = AnnotationViewport(scale: 0.375, origin: CGPoint(x: 31, y: 74))
        let pixel = CGPoint(x: 2003, y: 1507)
        let view = transform.viewPoint(pixel)
        expect(hypot(transform.sourcePoint(view).x - pixel.x, transform.sourcePoint(view).y - pixel.y) < 0.00001)
        transform.zoom(to: 1.7, anchor: view)
        expect(hypot(transform.viewPoint(pixel).x - view.x, transform.viewPoint(pixel).y - view.y) < 0.00001)
        // NSView points, including a Retina backing conversion, never multiply source pixels twice.
        let backing = CGPoint(x: view.x * 2, y: view.y * 2)
        expect(AnnotationViewport(scale: 0.375, origin: CGPoint(x: 31, y: 74)).sourcePoint(CGPoint(x: backing.x / 2, y: backing.y / 2)) == pixel)
    }
    func canvasGeometry() throws {
        let a = CGPoint(x: 80, y: 70), b = CGPoint(x: 10, y: 20)
        let arrow = AnnotationCanvasGeometry.created(kind: .arrow, from: a, to: b, style: AnnotationStyle(), shift: false)
        expect(arrow.points == [a, b] && arrow.rect == CGRect(x: 10, y: 20, width: 70, height: 50))
        let square = AnnotationCanvasGeometry.created(kind: .rectangle, from: a, to: b, style: AnnotationStyle(), shift: true)
        expect(square.rect == CGRect(x: 10, y: 0, width: 70, height: 70))
        let diagonal = AnnotationCanvasGeometry.constrained(b, from: a, line: true)
        expect(abs(abs(diagonal.x - a.x) - abs(diagonal.y - a.y)) < 0.0001)
        let source = CGRect(x: 0, y: 0, width: 100, height: 80)
        expect(AnnotationCanvasGeometry.clampedCrop(CGRect(x: -20, y: -10, width: 80, height: 50), source: source) == CGRect(x: 0, y: 0, width: 60, height: 40))
        expect(AnnotationCanvasGeometry.movedCrop(CGRect(x: 10, y: 10, width: 60, height: 40), by: CGSize(width: 100, height: -100), source: source) == CGRect(x: 40, y: 0, width: 60, height: 40))
    }
    func canvasDegenerate() throws {
        let line = Annotation(kind: .arrow, rect: CGRect(x: 10, y: 20, width: 70, height: 0), points: [CGPoint(x: 80, y: 20), CGPoint(x: 10, y: 20)])
        let resized = AnnotationCanvasGeometry.resized(line, handle: .end, to: CGPoint(x: 10, y: 70), shift: false)
        expect(resized.points == [CGPoint(x: 80, y: 20), CGPoint(x: 10, y: 70)])
        let vertical = Annotation(kind: .line, rect: CGRect(x: 10, y: 20, width: 0, height: 70), points: [CGPoint(x: 10, y: 20), CGPoint(x: 10, y: 90)])
        expect(AnnotationCanvasGeometry.resized(vertical, handle: .start, to: CGPoint(x: 30, y: 25), shift: false).points.first == CGPoint(x: 30, y: 25))
        let dot = Annotation(kind: .pen, points: [CGPoint(x: 75, y: 60)])
        expect(dot.contains(CGPoint(x: 75, y: 60)) && !dot.contains(.zero))
    }
    @MainActor func canvasGestures() throws {
        let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
        let canvas = AnnotationCanvas(document: doc)
        var changes = 0
        canvas.onDocumentChanged = { changes += 1 }
        for kind in AnnotationKind.allCases where kind != .hand && kind != .eraser {
            canvas.selectTool(kind)
            canvas.beginInteraction(at: CGPoint(x: 20, y: 20))
            canvas.updateInteraction(to: CGPoint(x: 120, y: 90))
            canvas.updateInteraction(to: CGPoint(x: 150, y: 110))
            expect(changes == doc.state.annotations.count)
            canvas.endInteraction()
            canvas.finishTextEditing()
            expect(doc.state.annotations.last?.kind == kind)
        }
        expect(changes == 14 && doc.state.annotations.count == 14)
        canvas.undo(); expect(doc.state.annotations.count == 13)
        canvas.redo(); expect(doc.state.annotations.count == 14)
        canvas.selectedID = nil
        canvas.selectTool(.eraser)
        canvas.beginInteraction(at: CGPoint(x: 50, y: 50)); canvas.endInteraction()
        expect(doc.state.annotations.count == 13)
    }
    @MainActor func canvasEditing() throws {
        let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
        let canvas = AnnotationCanvas(document: doc)
        var item = Annotation(kind: .magnify, rect: CGRect(x: 100, y: 100, width: 80, height: 80), magnifierSource: CGPoint(x: 40, y: 40))
        doc.commit(state: AnnotationState(annotations: [item]), label: "Fixture")
        canvas.selectTool(.hand)
        canvas.beginInteraction(at: CGPoint(x: 140, y: 140)); canvas.updateInteraction(to: CGPoint(x: 160, y: 150)); canvas.endInteraction()
        expect(doc.state.annotations[0].rect.origin == CGPoint(x: 120, y: 110) && doc.state.annotations[0].magnifierSource == CGPoint(x: 40, y: 40))
        canvas.undo(); item.style.magnifierLinked = true
        doc.commit(state: AnnotationState(annotations: [item]), label: "Linked")
        canvas.beginInteraction(at: CGPoint(x: 140, y: 140)); canvas.updateInteraction(to: CGPoint(x: 160, y: 150)); canvas.endInteraction()
        expect(doc.state.annotations[0].magnifierSource == CGPoint(x: 60, y: 50))
        canvas.setCrop(CGRect(x: -10, y: 20, width: 100, height: 60))
        expect(doc.state.crop == CGRect(x: 0, y: 20, width: 90, height: 60))
        canvas.undo(); expect(doc.state.crop == nil)
        canvas.duplicateSelection(); expect(doc.state.annotations.count == 2)
        canvas.deleteSelection(); expect(doc.state.annotations.count == 1)
    }

    @MainActor func canvasReselect() throws {
        let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
        let canvas = AnnotationCanvas(document: doc)
        canvas.selectTool(.arrow)
        canvas.beginInteraction(at: CGPoint(x: 100, y: 100)); canvas.updateInteraction(to: CGPoint(x: 300, y: 100)); canvas.endInteraction()
        let arrow = try require(doc.state.annotations.first)
        canvas.selectTool(.line)
        canvas.beginInteraction(at: CGPoint(x: 100, y: 250)); canvas.updateInteraction(to: CGPoint(x: 300, y: 250)); canvas.endInteraction()
        let line = try require(doc.state.annotations.last)
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.endInteraction()
        expect(canvas.selectedID == arrow.id && doc.state.annotations == [arrow, line] && canvas.tool == .line)
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.updateInteraction(to: CGPoint(x: 220, y: 140)); canvas.endInteraction()
        let moved = arrow.translated(by: CGSize(width: 20, height: 40))
        expect(doc.state.annotations == [moved, line])
        canvas.beginInteraction(at: CGPoint(x: 320, y: 140)); canvas.updateInteraction(to: CGPoint(x: 400, y: 180)); canvas.endInteraction()
        expect(doc.state.annotations[0].points == [CGPoint(x: 120, y: 140), CGPoint(x: 400, y: 180)])
        expect(doc.state.annotations[1] == line)
        canvas.undo(); expect(doc.state.annotations == [moved, line])
        canvas.undo(); expect(doc.state.annotations == [arrow, line])
        canvas.undo(); expect(doc.state.annotations == [arrow])
        canvas.redo(); expect(doc.state.annotations == [arrow, line])

        canvas.selectedID = nil
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.updateInteraction(to: CGPoint(x: 260, y: 190)); canvas.endInteraction()
        expect(doc.state.annotations.count == 3 && doc.state.annotations[0] == arrow)
        canvas.undo()

        // Click tolerance follows the view scale, and selection never writes history.
        canvas.selectedID = nil; canvas.zoom(to: 0.5)
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.updateInteraction(to: CGPoint(x: 204, y: 100)); canvas.endInteraction()
        expect(canvas.selectedID == arrow.id && doc.state.annotations == [arrow, line])
        canvas.selectedID = nil
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.updateInteraction(to: CGPoint(x: 220, y: 180)); canvas.updateInteraction(to: CGPoint(x: 200, y: 100)); canvas.endInteraction()
        expect(doc.state.annotations.count == 3 && doc.state.annotations.last?.kind == .line)
        canvas.undo(); canvas.selectedID = nil
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.updateInteraction(to: CGPoint(x: 250, y: 170)); canvas.cancelInteraction()
        expect(doc.state.annotations == [arrow, line])

        var upper = arrow; upper.id = UUID()
        doc.commit(state: AnnotationState(annotations: [arrow, upper]), label: "Overlap")
        canvas.selectedID = nil
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.endInteraction()
        expect(canvas.selectedID == upper.id && doc.state.annotations.count == 2)
    }

    @MainActor func canvasSelectionDrawing() throws {
        for kind in [AnnotationKind.rectangle, .ellipse, .spotlight] {
            let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
            let canvas = AnnotationCanvas(document: doc)
            let outer = Annotation(kind: kind, rect: CGRect(x: 100, y: 100, width: 300, height: 300))
            doc.commit(state: AnnotationState(annotations: [outer]), label: "Outer")
            canvas.selectTool(.rectangle); canvas.selectedID = outer.id
            canvas.beginInteraction(at: CGPoint(x: 200, y: 200)); canvas.updateInteraction(to: CGPoint(x: 280, y: 280)); canvas.endInteraction()
            expect(doc.state.annotations.count == 2 && doc.state.annotations[0] == outer)
            canvas.beginInteraction(at: CGPoint(x: 250, y: 100)); canvas.endInteraction()
            expect(canvas.selectedID == outer.id && doc.state.annotations.count == 2)
            if kind == .rectangle {
                canvas.beginInteraction(at: CGPoint(x: 160, y: 100)); canvas.updateInteraction(to: CGPoint(x: 180, y: 120)); canvas.endInteraction()
                expect(doc.state.annotations[0].rect.origin == CGPoint(x: 120, y: 120))
            }
        }
        for kind in [AnnotationKind.pen, .highlighter] {
            let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
            let canvas = AnnotationCanvas(document: doc); canvas.selectTool(kind)
            canvas.beginInteraction(at: CGPoint(x: 100, y: 100)); canvas.updateInteraction(to: CGPoint(x: 300, y: 200)); canvas.endInteraction()
            let first = try require(doc.state.annotations.first)
            canvas.beginInteraction(at: CGPoint(x: 200, y: 150)); canvas.updateInteraction(to: CGPoint(x: 300, y: 280)); canvas.endInteraction()
            expect(doc.state.annotations.count == 2 && doc.state.annotations[0] == first)
        }
    }

    func badgeColors() throws {
        for kind in [AnnotationKind.step, .note] {
            var style = AnnotationStyle(); style.backgroundColor = AnnotationColor(.blue); style.textColor = AnnotationColor(.green); style.size = 36
            let image = try AnnotationRenderer.render(source: fixture(width: 100, height: 100), state: AnnotationState(annotations: [Annotation(kind: kind, rect: CGRect(x: 40, y: 40, width: 20, height: 20), style: style)]), includeNotes: false)
            let center = kind == .step ? 50 : 40
            var greens = 0, blues = 0
            for y in (center - 16)...(center + 16) { for x in (center - 16)...(center + 16) {
                let p = pixel(image, x, y)
                if p.g > 180 && p.r < 80 && p.b < 80 { greens += 1 }
                if p.b > 180 && p.r < 80 && p.g < 80 { blues += 1 }
            } }
            expect(greens > 10 && blues > 100)
        }
    }
    func throwingEffects() throws {
        let source = try fixture(width: 40000, height: 4)
        for kind in [AnnotationKind.pixelate, .magnify] {
            let ctx = try require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.clip(to: CGRect(x: 2, y: 2, width: 90, height: 90))
            let original = ctx.boundingBoxOfClipPath
            var style = AnnotationStyle(); style.zoom = 1
            let item = Annotation(kind: kind, rect: CGRect(x: 0, y: 0, width: 35000, height: 4), style: style, magnifierSource: CGPoint(x: 17500, y: 2))
            expectThrows { try AnnotationRenderer.draw(source: source, state: AnnotationState(annotations: [item]), in: ctx) }
            expect(ctx.boundingBoxOfClipPath == original)
            ctx.setFillColor(NSColor.green.cgColor); ctx.fill(CGRect(x: 20, y: 20, width: 10, height: 10))
            expect(pixel(try require(ctx.makeImage()), 25, 75).g > 200)
        }
    }
    func patternMasks() throws {
        let ctx = try require(CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 320,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<15 { for x in 0..<20 {
            ctx.setFillColor((x + y) % 2 == 0 ? NSColor.black.cgColor : NSColor.white.cgColor)
            ctx.fill(CGRect(x: x * 4, y: y * 4, width: 4, height: 4))
        } }
        let source = try require(ctx.makeImage())
        for mode in [AnnotationMaskStyle.pixelate, .blur] {
            var style = AnnotationStyle(); style.maskStyle = mode; style.pixelSize = 11; style.blurRadius = 3; style.lineWidth = 0
            let image = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [Annotation(kind: .pixelate, rect: CGRect(x: 8, y: 8, width: 64, height: 44), style: style)]))
            var changed = 0
            for y in 15..<45 { for x in 15..<65 { if abs(Int(pixel(image, x, y).r) - Int(pixel(source, x, y).r)) > 30 { changed += 1 } } }
            expect(changed > 100)
            expect(pixel(source, 2, 2).r == pixel(image, 2, 2).r)
        }
    }

    @MainActor func canvasText() throws {
        let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
        let canvas = AnnotationCanvas(document: doc)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.contentView = nil }
        canvas.selectTool(.text); canvas.beginInteraction(at: CGPoint(x: 50, y: 50)); canvas.endInteraction()
        expect(canvas.isEditingText && doc.state.annotations.isEmpty)
        let text = try require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        text.setMarkedText("注音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(text.hasMarkedText() && doc.state.annotations.isEmpty)
        text.insertText("正體中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.finishTextEditing()
        expect(doc.state.annotations.count == 1 && doc.state.annotations[0].text == "正體中文")
        canvas.undo(); expect(doc.state.annotations.isEmpty)
        canvas.redo()
        canvas.selectTool(.line)
        let bounds = doc.state.annotations[0].rect
        canvas.beginInteraction(at: CGPoint(x: bounds.midX, y: bounds.midY), clickCount: 2)
        expect(canvas.isEditingText && doc.state.annotations.count == 1 && canvas.tool == .line)
        let second = try require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        second.setSelectedRange(NSRange(location: 0, length: 0))
        var copies = 0; canvas.onCopy = { copies += 1 }
        let commandC = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        expect(second.performKeyEquivalent(with: commandC))
        expect(copies == 1 && !canvas.isEditingText)
    }
    @MainActor func canvasHandles() throws {
        let doc = AnnotationDocument(image: try fixture(width: 800, height: 600))
        let canvas = AnnotationCanvas(document: doc)
        let sample = Annotation(kind: .magnify, rect: CGRect(x: 200, y: 200, width: 100, height: 100), magnifierSource: CGPoint(x: 60, y: 60))
        doc.commit(state: AnnotationState(annotations: [sample]), label: "Fixture")
        canvas.selectedID = sample.id
        canvas.beginInteraction(at: CGPoint(x: 60, y: 60)); canvas.updateInteraction(to: CGPoint(x: 90, y: 80)); canvas.endInteraction()
        expect(doc.state.annotations[0].magnifierSource == CGPoint(x: 90, y: 80) && doc.state.annotations[0].rect == sample.rect)
        canvas.beginInteraction(at: CGPoint(x: 300, y: 300)); canvas.updateInteraction(to: CGPoint(x: 350, y: 350)); canvas.endInteraction()
        expect(doc.state.annotations[0].rect == CGRect(x: 200, y: 200, width: 150, height: 150))
        expect(doc.state.annotations[0].magnifierSource == CGPoint(x: 90, y: 80))
        canvas.setCrop(CGRect(x: 100, y: 100, width: 200, height: 200)); canvas.isCropping = true
        canvas.beginInteraction(at: CGPoint(x: 300, y: 300)); canvas.updateInteraction(to: CGPoint(x: 900, y: 700)); canvas.endInteraction()
        expect(doc.state.crop == CGRect(x: 100, y: 100, width: 700, height: 500))
        canvas.undo(); expect(doc.state.crop == CGRect(x: 100, y: 100, width: 200, height: 200))
        canvas.beginInteraction(at: CGPoint(x: 150, y: 150)); canvas.updateInteraction(to: CGPoint(x: -500, y: -500)); canvas.endInteraction()
        expect(doc.state.crop == CGRect(x: 0, y: 0, width: 200, height: 200))
        canvas.setCrop(nil); canvas.selectTool(.step); canvas.clickCreatesShapes = false
        canvas.beginInteraction(at: CGPoint(x: 400, y: 400)); canvas.endInteraction()
        expect(doc.state.annotations.last?.kind == .step && doc.state.annotations.last?.rect.width == canvas.style.size)
        canvas.selectTool(.rectangle); canvas.beginInteraction(at: CGPoint(x: 400, y: 400)); canvas.endInteraction()
        expect(doc.state.annotations.count == 2)
        canvas.clickCreatesShapes = true; canvas.beginInteraction(at: CGPoint(x: 600, y: 400)); canvas.endInteraction()
        expect(doc.state.annotations.count == 3 && doc.state.annotations.last!.rect.width > 1)
    }

    @MainActor func curvedArrowHit() throws {
        var style = AnnotationStyle(); style.arrowStyle = .curved
        let arrow = Annotation(kind: .arrow, rect: CGRect(x: 100, y: 100, width: 200, height: 0), points: [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100)], style: style)
        expect(AnnotationCanvasGeometry.hit(arrow, at: CGPoint(x: 200, y: 125), tolerance: 5))
        expect(!AnnotationCanvasGeometry.hit(arrow, at: CGPoint(x: 200, y: 100), tolerance: 5))
        expect(AnnotationCanvasGeometry.hit(arrow, at: CGPoint(x: 284, y: 108), tolerance: 2))
        var note = arrow; note.kind = .note; note.style.arrowStyle = .open; note.style.noteStyle = .curvedArrow
        expect(AnnotationCanvasGeometry.hit(note, at: CGPoint(x: 200, y: 125), tolerance: 5))
        expect(!AnnotationCanvasGeometry.hit(note, at: CGPoint(x: 200, y: 100), tolerance: 5))
        let doc = AnnotationDocument(image: try fixture(width: 400, height: 300))
        let canvas = AnnotationCanvas(document: doc)
        doc.commit(state: AnnotationState(annotations: [arrow]), label: "Fixture")
        canvas.beginInteraction(at: CGPoint(x: 200, y: 125)); canvas.endInteraction()
        expect(canvas.selectedID == arrow.id)
        canvas.selectedID = nil
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.endInteraction()
        expect(canvas.selectedID == nil)
        canvas.selectTool(.eraser)
        canvas.beginInteraction(at: CGPoint(x: 200, y: 100)); canvas.endInteraction()
        expect(doc.state.annotations.count == 1)
        canvas.beginInteraction(at: CGPoint(x: 200, y: 125)); canvas.endInteraction()
        expect(doc.state.annotations.isEmpty)
    }
    @MainActor func squareCropEdges() throws {
        let doc = AnnotationDocument(image: try fixture(width: 100, height: 80))
        let canvas = AnnotationCanvas(document: doc)
        canvas.isCropping = true
        canvas.beginInteraction(at: CGPoint(x: 80, y: 70)); canvas.updateInteraction(to: CGPoint(x: 100, y: 80), shift: true); canvas.endInteraction()
        expect(doc.state.crop == CGRect(x: 80, y: 70, width: 10, height: 10))
        canvas.setCrop(CGRect(x: 20, y: 10, width: 20, height: 20))
        canvas.beginInteraction(at: CGPoint(x: 40, y: 30)); canvas.updateInteraction(to: CGPoint(x: 100, y: 80), shift: true); canvas.endInteraction()
        expect(doc.state.crop == CGRect(x: 20, y: 10, width: 70, height: 70))
        canvas.setCrop(CGRect(x: 20, y: 30, width: 20, height: 20))
        canvas.beginInteraction(at: CGPoint(x: 20, y: 30)); canvas.updateInteraction(to: CGPoint(x: -100, y: -100), shift: true); canvas.endInteraction()
        expect(doc.state.crop == CGRect(x: 0, y: 10, width: 40, height: 40))
    }

    @MainActor func noteArrowGestures() throws {
        let source = try fixture(width: 400, height: 300, alpha: true)
        for variant in [AnnotationNoteStyle.solidArrow, .dashedArrow, .curvedArrow] {
            for (a, b) in [(CGPoint(x: 300, y: 220), CGPoint(x: 70, y: 60)),
                           (CGPoint(x: 70, y: 220), CGPoint(x: 300, y: 60))] {
                let doc = AnnotationDocument(image: source), canvas = AnnotationCanvas(document: AnnotationDocument(image: source))
                let drawing = AnnotationCanvas(document: doc)
                drawing.selectTool(.note); drawing.style.noteStyle = variant
                drawing.beginInteraction(at: a); drawing.updateInteraction(to: b); drawing.endInteraction(); drawing.finishTextEditing()
                let note = try require(doc.state.annotations.first)
                expect(note.points == [a, b])
                let output = try doc.render(includeNotes: false)
                let badge = pixel(output, Int(a.x + 10), Int(a.y))
                expect(badge.r > 200 && badge.g > 200 && badge.a > 200)
                expect(note.contains(CGPoint(x: a.x + 10, y: a.y), tolerance: 0))
                expect(note.bounds.contains(CGPoint(x: a.x + 15, y: a.y)))
                drawing.selectTool(.hand); drawing.selectedID = note.id
                let end = CGPoint(x: b.x + 20, y: b.y + 30)
                drawing.beginInteraction(at: b); drawing.updateInteraction(to: end); drawing.endInteraction()
                expect(doc.state.annotations[0].points == [a, end])
                var expected = note; expected.points = [a, end]; expected.rect = AnnotationCanvasGeometry.rect(from: a, to: end)
                expect(try AnnotationRenderer.encode(doc.render(includeNotes: false)) == AnnotationRenderer.encode(AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [expected]), includeNotes: false)))
                canvas.selectTool(.note); canvas.style.noteStyle = variant
                canvas.beginInteraction(at: a); canvas.updateInteraction(to: b, shift: true); canvas.endInteraction(); canvas.finishTextEditing()
                expect(canvas.document.state.annotations[0].points == [a, AnnotationCanvasGeometry.constrained(b, from: a, line: true)])
            }
        }
    }

    @MainActor func fractionalCrop() throws {
        let doc = AnnotationDocument(image: try fixture(width: 240, height: 180))
        let canvas = AnnotationCanvas(document: AnnotationDocument(image: doc.source))
        let drawing = AnnotationCanvas(document: doc)
        canvas.frame = CGRect(x: 0, y: 0, width: 493, height: 381); canvas.fit()
        drawing.frame = canvas.frame; drawing.fit()
        expect(AnnotationCanvasGeometry.clampedCrop(CGRect(x: 10.3, y: 20.4, width: 0.4, height: 2), source: CGRect(x: 0, y: 0, width: 240, height: 180)) == nil)
        drawing.setCrop(CGRect(x: 10.3, y: 20.4, width: 100.4, height: 70.2))
        expect(doc.state.crop == CGRect(x: 10, y: 20, width: 101, height: 71))
        func matchesOutput(_ state: AnnotationState) throws {
            let frame = try require(state.crop), rendered = try AnnotationRenderer.render(source: doc.source, state: state)
            expect(frame == frame.integral && frame.width == CGFloat(rendered.width) && frame.height == CGFloat(rendered.height))
        }
        try matchesOutput(doc.state)
        drawing.isCropping = true
        drawing.beginInteraction(at: CGPoint(x: 111, y: 91)); drawing.updateInteraction(to: CGPoint(x: 132.7, y: 112.2)); drawing.endInteraction()
        try matchesOutput(doc.state)
        drawing.beginInteraction(at: CGPoint(x: 50, y: 50)); drawing.updateInteraction(to: CGPoint(x: 50.4, y: 50.6)); drawing.endInteraction()
        try matchesOutput(doc.state)
        for (anchor, end) in [(CGPoint(x: 20.3, y: 30.7), CGPoint(x: 240, y: 180)),
                              (CGPoint(x: 220.3, y: 150.7), CGPoint.zero),
                              (CGPoint(x: 20.3, y: 150.7), CGPoint(x: 240, y: 0)),
                              (CGPoint(x: 220.3, y: 30.7), CGPoint(x: 0, y: 180))] {
            canvas.setCrop(nil); canvas.isCropping = true
            let viewAnchor = canvas.viewPoint(fromSource: anchor)
            canvas.beginInteraction(at: canvas.sourcePoint(fromView: viewAnchor)); canvas.updateInteraction(to: end, shift: true); canvas.endInteraction()
            let crop = try require(canvas.document.state.crop)
            expect(crop == crop.integral && crop.width == crop.height && CGRect(x: 0, y: 0, width: 240, height: 180).contains(crop))
            try matchesOutput(canvas.document.state)
            canvas.beginInteraction(at: CGPoint(x: crop.maxX, y: crop.maxY)); canvas.updateInteraction(to: CGPoint(x: 240, y: 180), shift: true); canvas.endInteraction()
            let resized = try require(canvas.document.state.crop)
            expect(resized == resized.integral && resized.width == resized.height)
        }
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
                let doc = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
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
            for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier] {
                let url = folder.appendingPathComponent(UUID().uuidString + ".wrong")
                try encode(fixture(), url, type)
                let doc = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
                let originalPixels = try AnnotationRenderer.encode(doc.source)
                doc.commit(state: AnnotationState(crop: CGRect(x: 2, y: 3, width: 21, height: 17)), label: "Crop")
                try doc.saveOriginal()
                let source = try require(CGImageSourceCreateWithURL(url as CFURL, nil))
                expect(CGImageSourceGetType(source) as String? == type)
                expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width == 21)
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                expect((properties?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
                expect(!doc.isDirty)
                let reopened = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
                expect(reopened.state == doc.state && reopened.sourceType == type)
                expect(try AnnotationRenderer.encode(reopened.source) == originalPixels)
                try reopened.saveOriginal()
                expect(try AnnotationRenderer.encode(AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives")).source) == originalPixels)
                doc.undo(); expect(doc.isDirty)
            }
            let multi = folder.appendingPathComponent("multi.tiff")
            let destination = try require(CGImageDestinationCreateWithURL(multi as CFURL, UTType.tiff.identifier as CFString, 2, nil))
            CGImageDestinationAddImage(destination, try fixture(), nil)
            CGImageDestinationAddImage(destination, try fixture(), nil)
            expect(CGImageDestinationFinalize(destination))
            let bytes = try Data(contentsOf: multi)
            let doc = try AnnotationDocument(url: multi, archiveDirectory: folder.appendingPathComponent("archives"))
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
            let changed = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            try encode(fixture(width: 90), url, UTType.png.identifier)
            let newBytes = try Data(contentsOf: url)
            expectThrows { try changed.saveOriginal() }; expect(try Data(contentsOf: url) == newBytes)
            try original.write(to: url)
            let deleted = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            try FileManager.default.removeItem(at: url)
            expectThrows { try deleted.saveOriginal() }; expect(!FileManager.default.fileExists(atPath: url.path))
            try original.write(to: url)
            let replaced = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            try FileManager.default.removeItem(at: url); try original.write(to: url)
            expectThrows { try replaced.saveOriginal() }
        }
    }

    @MainActor func cancel() throws {
        try withFolder { folder in
            let url = folder.appendingPathComponent("source.png")
            try encode(fixture(), url, UTType.png.identifier)
            let original = try Data(contentsOf: url)
            let doc = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
            doc.commit(state: AnnotationState(annotations: [Annotation(kind: .text, text: "Secret")]), label: "Edit")
            _ = try doc.render()
            expect(try Data(contentsOf: url) == original)
            expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
            try doc.saveOriginal()
            expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
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

    func noteTypography() throws {
        let source = try fixture(width: 220, height: 70)
        var note = Annotation(kind: .note, rect: CGRect(x: 5, y: 4, width: 15, height: 20), text: String(repeating: "iiii WWWW wrapped words. ", count: 4))
        note.style.fontSize = 12
        let small = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [note]))
        note.style.fontSize = 32
        let large = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [note]))
        expect(large.height > small.height * 2)
        func ink(_ image: CGImage) -> Int {
            var count = 0
            for y in stride(from: 70, to: image.height, by: 2) { for x in stride(from: 0, to: image.width, by: 2) {
                if pixel(image, x, y).r < 128 { count += 1 }
            } }
            return count
        }
        expect(ink(large) > ink(small) * 2)
        note.style.fontName = NSFont.monospacedSystemFont(ofSize: 32, weight: .regular).fontName
        let mono = try AnnotationRenderer.render(source: source, state: AnnotationState(annotations: [note]))
        var different = 0
        for y in stride(from: 82, to: min(115, large.height, mono.height), by: 2) { for x in stride(from: 0, to: 220, by: 2) {
            if abs(Int(pixel(large, x, y).r) - Int(pixel(mono, x, y).r)) > 50 { different += 1 }
        } }
        expect(different > 20)
        expect(pixel(large, 0, large.height - 1).r == 255 && pixel(large, 0, large.height - 1).a == 255)
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
            let doc = try AnnotationDocument(url: url, archiveDirectory: folder.appendingPathComponent("archives"))
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

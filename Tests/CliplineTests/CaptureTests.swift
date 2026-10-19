import AppKit

@main
struct CaptureTests {
    @MainActor
    static func main() {
        let tests = CaptureTests()
        let cases: [(String, () throws -> Void)] = [
            ("Retina crop and mode", tests.testRetinaCropFlipsYAndUsesMouseUpCommand),
            ("Reverse drag on left display", tests.testReverseDragOnDisplayLeftOfMain),
            ("Clamped crop above main display", tests.testClampsToStartingDisplayAboveMain),
            ("Invalid selection", tests.testClickAndInvalidGeometryDoNotCapture),
            ("Clipboard preservation", tests.testEmptyRecognitionPreservesClipboardAndSuccessfulTextReplacesIt),
            ("Real Vision Chinese and English", tests.testVisionRecognizesTraditionalChineseAndEnglish),
            ("Blank OCR", tests.testBlankImageHasNoText),
            ("Private PNG storage", tests.testStoredPNGIsPrivateUniqueAndDecodable)
        ]
        for (name, run) in cases {
            let before = failures
            do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
            if before == failures { print("PASS \(name)") }
        }
        print("\(cases.count) checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    func testRetinaCropFlipsYAndUsesMouseUpCommand() throws {
        let capture = try require(CaptureSelection(
            start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 70),
            screenFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
            pixelSize: CGSize(width: 400, height: 200), modifiers: [.command]))
        expect(capture.rect == CGRect(x: 10, y: 20, width: 100, height: 50))
        expect(capture.pixelRect == CGRect(x: 20, y: 60, width: 200, height: 100))
        expect(capture.hang)
    }

    func testReverseDragOnDisplayLeftOfMain() throws {
        let capture = try require(CaptureSelection(
            start: CGPoint(x: -10, y: 80), end: CGPoint(x: -110, y: 20),
            screenFrame: CGRect(x: -200, y: 0, width: 200, height: 100),
            pixelSize: CGSize(width: 200, height: 100), modifiers: [.shift]))
        expect(capture.rect == CGRect(x: -110, y: 20, width: 100, height: 60))
        expect(capture.pixelRect == CGRect(x: 90, y: 20, width: 100, height: 60))
        expect(!capture.hang)
    }

    func testClampsToStartingDisplayAboveMain() throws {
        let capture = try require(CaptureSelection(
            start: CGPoint(x: 10, y: 150), end: CGPoint(x: 250, y: 250),
            screenFrame: CGRect(x: 0, y: 100, width: 200, height: 100),
            pixelSize: CGSize(width: 300, height: 150), modifiers: []))
        expect(capture.rect == CGRect(x: 10, y: 150, width: 190, height: 50))
        expect(capture.pixelRect == CGRect(x: 15, y: 0, width: 285, height: 75))
    }

    func testClickAndInvalidGeometryDoNotCapture() {
        for end in [CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 30), CGPoint(x: CGFloat.nan, y: 40)] {
            expect(CaptureSelection(start: CGPoint(x: 10, y: 10), end: end,
                screenFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
                pixelSize: CGSize(width: 400, height: 200), modifiers: []) == nil)
        }
    }

    @MainActor
    func testEmptyRecognitionPreservesClipboardAndSuccessfulTextReplacesIt() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep this", forType: .string)
        expect(!TextRecognition.copy(nil, to: pasteboard))
        expect(!TextRecognition.copy(" \n ", to: pasteboard))
        expect(pasteboard.string(forType: .string) == "keep this")
        expect(TextRecognition.copy("繁體中文\nHello Clipline", to: pasteboard))
        expect(pasteboard.string(forType: .string) == "繁體中文\nHello Clipline")
    }

    @MainActor
    func testVisionRecognizesTraditionalChineseAndEnglish() throws {
        let image = try fixture(text: "繁體中文測試\nHello Clipline 2468")
        let text = try require(TextRecognition.recognize(image))
        expect(text.contains("繁體中文測試"))
        expect(text.contains("Hello Clipline 2468"))
    }

    @MainActor
    func testBlankImageHasNoText() throws {
        expect(try TextRecognition.recognize(fixture(text: "")) == nil)
    }

    @MainActor
    func testStoredPNGIsPrivateUniqueAndDecodable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try fixture(text: "Clipline")
        let first = try CaptureStorage.save(image, folder: folder)
        let second = try CaptureStorage.save(image, folder: folder)
        expect(first != second)
        let decoded = try require(NSBitmapImageRep(data: Data(contentsOf: first)))
        expect(decoded.pixelsWide == 900)
        expect(decoded.pixelsHigh == 240)
        let attributes = try FileManager.default.attributesOfItem(atPath: first.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @MainActor
    private func fixture(text: String) throws -> CGImage {
        let bitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900,
            pixelsHigh: 240, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 240).fill()
        (text as NSString).draw(in: NSRect(x: 40, y: 30, width: 820, height: 180), withAttributes: [
            .font: NSFont.systemFont(ofSize: 52), .foregroundColor: NSColor.black
        ])
        NSGraphicsContext.restoreGraphicsState()
        return try require(bitmap.cgImage)
    }
}

private var failures = 0
private struct MissingValue: Error {}
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw MissingValue() }
    return value
}
private func expect(_ condition: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition { failures += 1; print("FAIL \(file):\(line)") }
}

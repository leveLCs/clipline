import AppKit

/// One private, short-lived worker per capture. Images only travel through pipes.
final class DdddOCR: @unchecked Sendable {
    enum Failure: Error, LocalizedError {
        case unavailable, failed, timedOut, cancelled
        var errorDescription: String? {
            switch self {
            case .unavailable: return L("ddddocr is unavailable. Reinstall its local runtime, or capture without Option to use Apple Vision.")
            case .failed: return L("ddddocr could not recognize this image. The clipboard was not changed.")
            case .timedOut: return L("ddddocr timed out. Try a smaller selection.")
            case .cancelled: return L("Capture cancelled.")
            }
        }
    }

    static let pythonURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Clipline/OCR/ddddocr-1.6.1/bin/python3")
    private let pythonURL: URL
    private let workerURL: URL?
    private let timeout: TimeInterval
    private let process = Process()
    private let lock = NSLock()
    private var stopped: Failure?

    init(pythonURL: URL = DdddOCR.pythonURL,
         workerURL: URL? = Bundle.main.url(forResource: "ddddocr_worker", withExtension: "py"),
         timeout: TimeInterval = 15) {
        self.pythonURL = pythonURL
        self.workerURL = workerURL
        self.timeout = timeout
    }

    func recognize(_ image: CGImage) throws -> String? {
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path),
              let workerURL, FileManager.default.isReadableFile(atPath: workerURL.path) else {
            throw Failure.unavailable
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure.failed
        }
        let input = Pipe(), output = Pipe()
        process.executableURL = pythonURL
        process.arguments = ["-I", "-B", workerURL.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // An early worker exit must throw EPIPE, not terminate Clipline with SIGPIPE.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw Failure.failed
        }
        try lock.withLock {
            if let stopped { throw stopped }
            do { try process.run() } catch { throw Failure.unavailable }
        }
        let deadline = DispatchWorkItem { [weak self] in self?.stop(.timedOut) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            process.waitUntilExit()
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: png)
            try input.fileHandleForWriting.close()
            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            if let stopped = lock.withLock({ stopped }) { throw stopped }
            guard process.terminationStatus == 0 else { throw Failure.failed }
            struct Result: Decodable { let text: String }
            let text = try JSONDecoder().decode(Result.self, from: data).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            let failure = lock.withLock { stopped } ?? (error as? Failure) ?? .failed
            stop(failure)
            throw failure
        }
    }

    func cancel() { stop(.cancelled) }

    private func stop(_ reason: Failure) {
        lock.withLock {
            guard stopped == nil else { return }
            stopped = reason
            // The worker has no state to flush; stop synchronously even when Clipline is exiting.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

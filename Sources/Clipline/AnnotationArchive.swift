import AppKit
import CryptoKit
import ImageIO
import Darwin

// Only the opaque revision ID travels with the image; editable pixels stay on this Mac.
enum AnnotationArchive {
    static let attribute = "io.github.leveLCs.Clipline.annotation"
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipline/Annotations", isDirectory: true)
    }
    struct Record: Codable {
        var version = 1
        var sourcePNG: Data
        var state: AnnotationState
        var renderedHash: Data
    }
    static func hash(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }

    static func readID(from fd: Int32) throws -> String? {
        var bytes = [UInt8](repeating: 0, count: 36)
        let count = fgetxattr(fd, attribute, &bytes, bytes.count, 0, 0)
        if count < 0 && [ENOATTR, ENOTSUP].contains(errno) { return nil }
        guard count == 36, let id = String(bytes: bytes, encoding: .utf8),
              UUID(uuidString: id)?.uuidString == id else { throw AnnotationFailure.invalidAnnotationData }
        return id
    }
    static func attach(_ id: String, to fd: Int32) throws {
        let bytes = Array(id.utf8)
        guard bytes.withUnsafeBytes({ fsetxattr(fd, attribute, $0.baseAddress, $0.count, 0, 0) }) == 0
        else { throw AnnotationFailure.writeFailed }
    }
    static func load(_ id: String, in directory: URL) throws -> Record? {
        guard UUID(uuidString: id)?.uuidString == id else { throw AnnotationFailure.invalidAnnotationData }
        let url = directory.appendingPathComponent(id + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let record = try JSONDecoder().decode(Record.self, from: FileVersion.read(url).bytes)
            guard record.version == 1 else { throw AnnotationFailure.invalidAnnotationData }
            return record
        } catch { throw AnnotationFailure.invalidAnnotationData }
    }
    static func save(source: CGImage, state: AnnotationState, output: Data, in directory: URL) throws -> String {
        let record = Record(sourcePNG: try AnnotationRenderer.encode(source), state: state, renderedHash: hash(output))
        let bytes = try JSONEncoder().encode(record)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let dir = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard dir >= 0 else { throw AnnotationFailure.writeFailed }
        defer { close(dir) }
        guard fchmod(dir, 0o700) == 0 else { throw AnnotationFailure.writeFailed }
        let id = UUID().uuidString, name = id + ".json"
        let fd = openat(dir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AnnotationFailure.writeFailed }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var complete = false
        defer { try? file.close(); if !complete { unlinkat(dir, name, 0) } }
        try file.write(contentsOf: bytes); try file.synchronize(); try file.close()
        complete = true
        // shortcut: retain old revisions for copied/trashed images; add explicit cleanup when requested.
        return id
    }
}

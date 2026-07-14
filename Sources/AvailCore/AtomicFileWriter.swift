import Foundation

enum AtomicFileWriter {
    static func write<T: Encodable>(_ value: T, to destination: URL, encoder: JSONEncoder = JSONEncoder()) throws {
        try write(encoder.encode(value), to: destination)
    }

    static func write(_ data: Data, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporary = destination.appendingPathExtension("tmp")
        if fileManager.fileExists(atPath: temporary.path) {
            try fileManager.removeItem(at: temporary)
        }
        try data.write(to: temporary)

        let handle = try FileHandle(forWritingTo: temporary)
        handle.synchronizeFile()
        try handle.close()

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }
}

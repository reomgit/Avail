import Foundation
import ImageIO

actor ArtworkStore {
    nonisolated let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func persist(_ data: Data?, bookID: UUID) -> String? {
        let relativePath = "\(bookID.uuidString)/cover"
        let destination = rootURL.appending(path: relativePath)
        guard let data,
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(imageSource) > 0,
            CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil
        else {
            return FileManager.default.fileExists(atPath: destination.path) ? relativePath : nil
        }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
            return relativePath
        } catch {
            return FileManager.default.fileExists(atPath: destination.path) ? relativePath : nil
        }
    }

    nonisolated func fileURL(for relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return rootURL.appending(path: relativePath)
    }

    func remove(bookID: UUID) {
        try? FileManager.default.removeItem(at: rootURL.appending(path: bookID.uuidString))
    }
}

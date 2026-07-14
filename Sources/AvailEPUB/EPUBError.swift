import Foundation

public enum EPUBError: Error, Equatable, LocalizedError, Sendable {
    case invalidContainer
    case missingPackage
    case encrypted
    case emptySpine
    case unreadableContent(String)

    public var errorDescription: String? {
        switch self {
        case .invalidContainer:
            "This EPUB has an invalid container file."
        case .missingPackage:
            "This EPUB is missing its package document."
        case .encrypted:
            "Encrypted or DRM-protected EPUB files are not supported."
        case .emptySpine:
            "No readable book content was found in this EPUB."
        case let .unreadableContent(path):
            "Avail could not read EPUB content at \(path)."
        }
    }
}

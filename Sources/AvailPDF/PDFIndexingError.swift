import Foundation

public enum PDFIndexingError: Error, Equatable, LocalizedError, Sendable {
    case unreadable
    case locked
    case noSelectableText
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "This PDF could not be opened."
        case .locked:
            "Password-protected PDFs are not supported in this version of Avail."
        case .noSelectableText:
            "This PDF appears to contain scanned images without selectable text. OCR is not included yet."
        case .cancelled:
            "PDF indexing was cancelled."
        }
    }
}

import Foundation

enum LibraryError: Error, Equatable, LocalizedError {
    case noLibraryLocation
    case unsupportedFormat
    case sourceUnreadable
    case destinationInvalid
    case missingRecord
    case fileOperation(String)

    var errorDescription: String? {
        switch self {
        case .noLibraryLocation:
            "Reconnect your Avail library folder to continue."
        case .unsupportedFormat:
            "Avail currently imports EPUB and PDF files."
        case .sourceUnreadable:
            "The selected book could not be read."
        case .destinationInvalid:
            "The selected library location is not a writable folder."
        case .missingRecord:
            "This book is no longer in the Avail library."
        case let .fileOperation(message):
            message
        }
    }
}

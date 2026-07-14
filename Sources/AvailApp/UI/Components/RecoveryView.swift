import AvailEPUB
import AvailPDF
import Foundation
import SwiftUI

enum RecoveryIssue: Equatable {
    case bookmarkReconnect
    case unsupportedType
    case corruptEPUB
    case protectedEPUB
    case lockedPDF
    case scannedPDF
    case missingSource
    case diskFull
    case indexInterrupted
    case frontierBuffering
    case voiceUnavailable
}

enum RecoveryAction: Equatable {
    case reconnectLibrary
    case chooseAnotherFile
    case unlockPDFElsewhere
    case removeFromLibrary
    case freeDiskSpace
    case retryIndex
    case waitForIndex
    case chooseVoice
}

struct RecoveryPresentation: Equatable {
    let title: String
    let explanation: String
    let primaryButtonTitle: String
    let systemImage: String
    let action: RecoveryAction
    let isDestructive: Bool

    init(_ issue: RecoveryIssue) {
        switch issue {
        case .bookmarkReconnect:
            self.init("Reconnect Library", "macOS can no longer access the folder you previously selected. Choose that folder again to restore access.", "Choose Library Folder…", "externaldrive.badge.questionmark", .reconnectLibrary)
        case .unsupportedType:
            self.init("Unsupported Book Type", "Avail currently reads EPUB and PDF files.", "Choose Another File…", "doc.badge.ellipsis", .chooseAnotherFile)
        case .corruptEPUB:
            self.init("EPUB Could Not Be Read", "The book package is incomplete or damaged. Try a fresh copy from its original source.", "Choose Another File…", "book.closed.trianglebadge.exclamationmark", .chooseAnotherFile)
        case .protectedEPUB:
            self.init("Protected EPUB", "This EPUB is encrypted or DRM-protected and can’t be narrated by Avail.", "Choose Another File…", "lock.fill", .chooseAnotherFile)
        case .lockedPDF:
            self.init("PDF Is Locked", "Remove the PDF password in its source application, then import the unlocked copy.", "Open an Unlocked Copy…", "lock.doc", .unlockPDFElsewhere)
        case .scannedPDF:
            self.init("No Selectable Text", "This PDF appears to contain scanned page images. OCR is not included in the MVP.", "Choose Another File…", "doc.viewfinder", .chooseAnotherFile)
        case .missingSource:
            self.init("Book File Is Missing", "The managed book file was moved or deleted outside Avail. Reconnect it or remove the stale entry.", "Remove from Library…", "questionmark.folder", .removeFromLibrary, destructive: true)
        case .diskFull:
            self.init("Not Enough Disk Space", "Avail couldn’t finish copying or indexing this book. Free space, then retry.", "Review Storage", "externaldrive.badge.exclamationmark", .freeDiskSpace)
        case .indexInterrupted:
            self.init("Preparation Was Interrupted", "The committed reading index is safe. Retry to continue from the last completed frontier.", "Resume Preparing", "arrow.clockwise", .retryIndex)
        case .frontierBuffering:
            self.init("Preparing the Next Passage", "You reached the readable frontier while Avail continues indexing locally.", "Keep Waiting", "hourglass", .waitForIndex)
        case .voiceUnavailable:
            self.init("Voice Is No Longer Installed", "macOS can’t find the saved voice. Choose another installed voice; your reading position is unchanged.", "Choose Voice", "waveform.badge.exclamationmark", .chooseVoice)
        }
    }

    private init(
        _ title: String,
        _ explanation: String,
        _ primaryButtonTitle: String,
        _ systemImage: String,
        _ action: RecoveryAction,
        destructive: Bool = false
    ) {
        self.title = title
        self.explanation = explanation
        self.primaryButtonTitle = primaryButtonTitle
        self.systemImage = systemImage
        self.action = action
        self.isDestructive = destructive
    }

    static func issue(for error: Error) -> RecoveryIssue {
        switch error {
        case LibraryError.noLibraryLocation: .bookmarkReconnect
        case LibraryError.unsupportedFormat: .unsupportedType
        case LibraryError.sourceUnreadable: .missingSource
        case EPUBError.encrypted: .protectedEPUB
        case EPUBError.invalidContainer, EPUBError.missingPackage, EPUBError.emptySpine, EPUBError.unreadableContent: .corruptEPUB
        case PDFIndexingError.locked: .lockedPDF
        case PDFIndexingError.noSelectableText: .scannedPDF
        case PDFIndexingError.unreadable: .missingSource
        case let error as CocoaError where error.code == .fileWriteOutOfSpace: .diskFull
        default: .indexInterrupted
        }
    }
}

struct DestructiveRemovalRequest: Equatable {
    let bookID: UUID
    let requiresConfirmation = true
    let mode: LibraryRemovalMode = .moveFileToTrash
}

struct RecoveryView: View {
    let issue: RecoveryIssue
    let perform: (RecoveryAction) -> Void
    @State private var confirmsDestructiveAction = false

    var body: some View {
        let presentation = RecoveryPresentation(issue)
        ContentUnavailableView {
            Label(presentation.title, systemImage: presentation.systemImage)
        } description: {
            Text(presentation.explanation)
        } actions: {
            Button(presentation.primaryButtonTitle, role: presentation.isDestructive ? .destructive : nil) {
                if presentation.isDestructive {
                    confirmsDestructiveAction = true
                } else {
                    perform(presentation.action)
                }
            }
        }
        .confirmationDialog(
            "Move this book to the Trash?",
            isPresented: $confirmsDestructiveAction
        ) {
            Button("Move to Trash", role: .destructive) { perform(presentation.action) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is never permanently deleted by Avail.")
        }
    }
}

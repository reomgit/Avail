import AvailCore
import Foundation
import PDFKit

struct PDFMetadataReader {
    func metadata(for document: PDFDocument, fileURL: URL) -> BookMetadata {
        let attributes = document.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle =
            title.flatMap { $0.isEmpty ? nil : $0 }
            ?? fileURL.deletingPathExtension().lastPathComponent
        let resolvedAuthors = author.flatMap { $0.isEmpty ? nil : $0 }.map { [$0] } ?? []
        return BookMetadata(
            title: resolvedTitle,
            authors: resolvedAuthors
        )
    }

    func outlineTitles(for document: PDFDocument) -> [Int: String] {
        guard let root = document.outlineRoot else { return [:] }
        var result: [Int: String] = [:]
        visit(root, document: document, result: &result)
        return result
    }

    private func visit(_ outline: PDFOutline, document: PDFDocument, result: inout [Int: String]) {
        for index in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: index) else { continue }
            let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
            if let page = destination?.page {
                let pageIndex = document.index(for: page)
                if pageIndex >= 0, let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    result[pageIndex] = label
                }
            }
            visit(child, document: document, result: &result)
        }
    }
}

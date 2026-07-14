import Foundation
import SwiftSoup

struct EPUBContent {
    let title: String?
    let text: String
}

struct EPUBContentParser {
    func parse(data: Data, path: String) throws -> EPUBContent {
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else {
            throw EPUBError.unreadableContent(path)
        }

        do {
            let document = try SwiftSoup.parse(html)
            try document.select("script, style, noscript, template, [hidden], [aria-hidden=true]").remove()
            let blocks = try document.select("h1, h2, h3, h4, h5, h6, p, li, pre, figcaption, td, th")
            var orderedText: [String] = []
            var title: String?
            for element in blocks.array() {
                let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if title == nil, element.tagName().lowercased().hasPrefix("h") {
                    title = text
                }
                orderedText.append(text)
            }

            if orderedText.isEmpty {
                let bodyText = try document.body()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !bodyText.isEmpty { orderedText.append(bodyText) }
            }
            return EPUBContent(title: title, text: orderedText.joined(separator: "\n\n"))
        } catch let error as EPUBError {
            throw error
        } catch {
            throw EPUBError.unreadableContent(path)
        }
    }
}

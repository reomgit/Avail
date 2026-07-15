import Foundation
import ZIPFoundation

struct EPUBManifestItem: Sendable {
    let id: String
    let path: String
    let mediaType: String
    let properties: Set<String>
}

struct EPUBPackage: Sendable {
    let title: String?
    let authors: [String]
    let languageCode: String?
    let manifest: [String: EPUBManifestItem]
    let spineIDs: [String]
    let coverPath: String?
}

struct EPUBArchiveReader {
    private enum Storage {
        case archive(Archive)
        case directory(URL)
    }

    private let storage: Storage

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            storage = .directory(url)
        } else {
            storage = .archive(try Archive(url: url, accessMode: .read))
        }
    }

    func contains(_ path: String) -> Bool {
        guard isSafeArchivePath(path) else { return false }
        switch storage {
        case let .archive(archive):
            return archive[path] != nil
        case let .directory(root):
            guard let url = resolvedURL(for: path, in: root) else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
    }

    func data(at path: String, maximumSize: Int64 = 64 * 1_024 * 1_024) throws -> Data {
        guard isSafeArchivePath(path) else { throw EPUBError.unreadableContent(path) }
        switch storage {
        case let .archive(archive):
            guard let entry = archive[path], Int64(entry.uncompressedSize) <= maximumSize else {
                throw EPUBError.unreadableContent(path)
            }

            var result = Data()
            result.reserveCapacity(Int(entry.uncompressedSize))
            do {
                _ = try archive.extract(entry) { chunk in
                    guard Int64(result.count + chunk.count) <= maximumSize else {
                        throw EPUBError.unreadableContent(path)
                    }
                    result.append(chunk)
                }
            } catch let error as EPUBError {
                throw error
            } catch {
                throw EPUBError.unreadableContent(path)
            }
            return result
        case let .directory(root):
            guard let url = resolvedURL(for: path, in: root) else { throw EPUBError.unreadableContent(path) }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true,
                values.isSymbolicLink != true,
                Int64(values.fileSize ?? 0) <= maximumSize
            else {
                throw EPUBError.unreadableContent(path)
            }
            let result = try Data(contentsOf: url, options: .mappedIfSafe)
            guard Int64(result.count) <= maximumSize else { throw EPUBError.unreadableContent(path) }
            return result
        }
    }

    private func isSafeArchivePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    private func resolvedURL(for path: String, in root: URL) -> URL? {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedURL = root.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedURL.path.hasPrefix(rootPrefix) else { return nil }
        return resolvedURL
    }
}

struct EPUBPackageParser {
    func packagePath(in archive: EPUBArchiveReader) throws -> String {
        guard let xml = String(data: try archive.data(at: "META-INF/container.xml", maximumSize: 1_024 * 1_024), encoding: .utf8) else {
            throw EPUBError.invalidContainer
        }
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.packagePath, isSafeResolvedPath(path) else {
            throw EPUBError.invalidContainer
        }
        return path
    }

    func parsePackage(data: Data, packagePath: String) throws -> EPUBPackage {
        let delegate = PackageXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse(), !delegate.spineIDs.isEmpty else {
            throw EPUBError.missingPackage
        }

        let basePath = (packagePath as NSString).deletingLastPathComponent
        var manifest: [String: EPUBManifestItem] = [:]
        for item in delegate.manifestItems {
            let resolved = try resolve(item.href, relativeTo: basePath)
            manifest[item.id] = EPUBManifestItem(
                id: item.id,
                path: resolved,
                mediaType: item.mediaType,
                properties: item.properties
            )
        }

        let coverID = delegate.coverID
        let coverPath =
            manifest.values.first(where: { $0.properties.contains("cover-image") })?.path
            ?? coverID.flatMap { manifest[$0]?.path }
        return EPUBPackage(
            title: delegate.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            authors: delegate.authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            languageCode: delegate.language?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            manifest: manifest,
            spineIDs: delegate.spineIDs,
            coverPath: coverPath
        )
    }

    private func resolve(_ href: String, relativeTo basePath: String) throws -> String {
        let decoded = href.removingPercentEncoding ?? href
        let withoutFragment = decoded.split(separator: "#", maxSplits: 1).first.map(String.init) ?? decoded
        let combined = basePath.isEmpty ? withoutFragment : "\(basePath)/\(withoutFragment)"
        var components: [Substring] = []
        for component in combined.split(separator: "/") {
            switch component {
            case ".", "":
                continue
            case "..":
                guard !components.isEmpty else { throw EPUBError.unreadableContent(href) }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        let result = components.joined(separator: "/")
        guard isSafeResolvedPath(result) else { throw EPUBError.unreadableContent(href) }
        return result
    }

    private func isSafeResolvedPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var packagePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "rootfile" || qName == "rootfile" else { return }
        packagePath = attributeDict["full-path"]
    }
}

private final class PackageXMLDelegate: NSObject, XMLParserDelegate {
    struct Item {
        let id: String
        let href: String
        let mediaType: String
        let properties: Set<String>
    }

    var title: String?
    var authors: [String] = []
    var language: String?
    var manifestItems: [Item] = []
    var spineIDs: [String] = []
    var coverID: String?

    private var capturedElement: String?
    private var capturedText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        switch name {
        case "title", "creator", "language":
            capturedElement = name
            capturedText = ""
        case "item":
            guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
            manifestItems.append(
                Item(
                    id: id,
                    href: href,
                    mediaType: attributeDict["media-type"] ?? "",
                    properties: Set((attributeDict["properties"] ?? "").split(separator: " ").map(String.init))
                ))
        case "itemref":
            if let idref = attributeDict["idref"] { spineIDs.append(idref) }
        case "meta":
            if attributeDict["name"]?.lowercased() == "cover" {
                coverID = attributeDict["content"]
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturedElement != nil { capturedText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        guard capturedElement == name else { return }
        switch name {
        case "title":
            if title == nil { title = capturedText }
        case "creator":
            authors.append(capturedText)
        case "language":
            if language == nil { language = capturedText }
        default:
            break
        }
        capturedElement = nil
        capturedText = ""
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import UniformTypeIdentifiers

enum BookImportContentTypes {
    static let all: [UTType] = {
        var types: [UTType] = [.pdf]
        if let epubFile = UTType(filenameExtension: "epub") {
            types.append(epubFile)
        }
        if let unpackedEPUBPackage = UTType("com.apple.ibooks.epub") {
            types.append(unpackedEPUBPackage)
        }
        return types
    }()
}

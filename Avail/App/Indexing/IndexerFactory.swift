import AvailCore
import AvailEPUB
import AvailPDF

protocol IndexerProviding: Sendable {
    func indexer(for format: BookFormat) -> any DocumentIndexer
}

struct IndexerFactory: IndexerProviding {
    func indexer(for format: BookFormat) -> any DocumentIndexer {
        switch format {
        case .epub:
            EPUBIndexer()
        case .pdf:
            PDFIndexer()
        }
    }
}

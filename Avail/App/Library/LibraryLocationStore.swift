import Foundation

final class LibraryAccessLease {
    let url: URL
    private let didStartSecurityScope: Bool

    init(url: URL, didStartSecurityScope: Bool) {
        self.url = url
        self.didStartSecurityScope = didStartSecurityScope
    }

    deinit {
        if didStartSecurityScope {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

@MainActor
final class LibraryLocationStore {
    private let defaults: UserDefaults
    private let creationOptions: URL.BookmarkCreationOptions
    private let resolutionOptions: URL.BookmarkResolutionOptions
    private let bookmarkKey = "librarySecurityScopedBookmark"

    init(
        defaults: UserDefaults = .standard,
        creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope],
        resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
    ) {
        self.defaults = defaults
        self.creationOptions = creationOptions
        self.resolutionOptions = resolutionOptions
    }

    func select(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LibraryError.destinationInvalid
        }
        let bookmark = try url.bookmarkData(
            options: creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    func resolve() throws -> URL? {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            try select(url)
        }
        return url
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    func beginAccess() throws -> LibraryAccessLease {
        guard let url = try resolve() else { throw LibraryError.noLibraryLocation }
        let requiresSecurityScope = resolutionOptions.contains(.withSecurityScope)
        let didStart = requiresSecurityScope ? url.startAccessingSecurityScopedResource() : false
        guard !requiresSecurityScope || didStart else { throw LibraryError.noLibraryLocation }
        return LibraryAccessLease(url: url, didStartSecurityScope: didStart)
    }

    func withAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        let lease = try beginAccess()
        return try operation(lease.url)
    }
}

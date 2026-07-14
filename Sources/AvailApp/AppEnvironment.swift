import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    enum LaunchState: Equatable {
        case needsLibraryLocation
        case loading
        case ready
        case failed(String)
    }

    var launchState: LaunchState
    var selectedBookID: UUID?

    init(launchState: LaunchState = .needsLibraryLocation) {
        self.launchState = launchState
    }

    static func bootstrapForTesting() -> AppEnvironment {
        AppEnvironment()
    }
}

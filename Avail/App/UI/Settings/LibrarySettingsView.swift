import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibrarySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var currentURL: URL?
    @State private var isChoosingDestination = false
    @State private var pendingDestination: URL?
    @State private var confirmsRelocation = false
    @State private var isRelocating = false

    var body: some View {
        Form {
            Section("Managed Library") {
                LabeledContent("Location", value: currentURL?.path(percentEncoded: false) ?? "Not connected")
                    .textSelection(.enabled)
                HStack {
                    Button("Reveal in Finder") {
                        if let currentURL { NSWorkspace.shared.activateFileViewerSelecting([currentURL]) }
                    }
                    .disabled(currentURL == nil)
                    Button("Move Library…") { isChoosingDestination = true }
                        .disabled(currentURL == nil || isRelocating)
                }
                if isRelocating {
                    ProgressView("Moving books safely…")
                }
            }

            Section {
                Text("Avail copies imported books into this folder. If relocation fails, the original folder and bookmark remain unchanged.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { refreshLocation() }
        .fileImporter(
            isPresented: $isChoosingDestination,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            pendingDestination = url
            confirmsRelocation = true
        }
        .confirmationDialog("Move the Avail library?", isPresented: $confirmsRelocation) {
            Button("Move Library") { relocate() }
            Button("Cancel", role: .cancel) { pendingDestination = nil }
        } message: {
            Text("Avail copies every managed book first and switches locations only after the copy succeeds.")
        }
    }

    private func refreshLocation() {
        currentURL = try? environment.locationStore.resolve()
    }

    private func relocate() {
        guard let destination = pendingDestination, let store = environment.libraryStore else { return }
        pendingDestination = nil
        isRelocating = true
        Task {
            let didAccess = destination.startAccessingSecurityScopedResource()
            defer { if didAccess { destination.stopAccessingSecurityScopedResource() } }
            do {
                try await store.relocate(to: destination)
                refreshLocation()
            } catch {
                environment.lastActionError = "The library could not be moved. Your original library is unchanged."
            }
            isRelocating = false
        }
    }
}

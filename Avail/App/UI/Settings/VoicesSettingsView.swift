import SwiftUI
import UniformTypeIdentifiers

struct LocalVoiceServerDraft {
    enum Host: String, CaseIterable, Identifiable {
        case ipv4 = "127.0.0.1"
        case ipv6 = "::1"

        var id: String { rawValue }
        var label: String { self == .ipv4 ? "127.0.0.1 (IPv4)" : "::1 (IPv6)" }
    }

    var name = ""
    var host: Host = .ipv4
    var port = "8080"
    var modelID = ""
    var voiceID = ""
    var token = ""

    func baseURL() throws -> URL {
        guard let number = Int(port), (1...65_535).contains(number), port == String(number) else {
            throw VoiceModelCatalogError.invalidServer
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host == .ipv6 ? "[::1]" : host.rawValue
        components.port = number
        guard let url = components.url else { throw VoiceModelCatalogError.invalidServer }
        return url
    }

    func withPort(_ value: String) -> Self {
        var copy = self
        copy.port = value
        return copy
    }

    func withHost(_ value: Host) -> Self {
        var copy = self
        copy.host = value
        return copy
    }
}

struct VoicePickerGroups {
    let imported: [VoiceModelEntry]
    let servers: [VoiceModelEntry]

    init(entries: [VoiceModelEntry]) {
        imported = entries.filter { $0.source == .linked || $0.source == .managed }
        servers = entries.filter { $0.source == .loopbackServer }
    }
}

struct VoicesSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isLinking = false
    @State private var isCopying = false
    @State private var isReconnecting = false
    @State private var reconnectID: UUID?
    @State private var pendingManagedRemoval: UUID?
    @State private var confirmsManagedRemoval = false
    @State private var draft = LocalVoiceServerDraft()
    @State private var editingServerID: UUID?
    @State private var removesSavedToken = false
    @State private var isBusy = false
    @State private var actionError: String?
    @State private var previewingID: UUID?
    @State private var inaccessibleIDs: Set<UUID> = []

    private var catalog: VoiceModelCatalog? { environment.voiceModelCatalog }

    var body: some View {
        Form {
            if let error = environment.voiceCatalogError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Fish Audio S2 Pro MLX") {
                Text("Use a Fish Audio S2 Pro MLX model folder already on your Mac. Avail never downloads model weights.")
                    .foregroundStyle(.secondary)
                if !environment.supportsLocalNeuralNarration {
                    Text("Custom voices require Apple Silicon. macOS system voices remain available.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Link Existing Folder…") { isLinking = true }
                    Button("Copy into Avail…") { isCopying = true }
                }
                .disabled(catalog == nil || isBusy || !environment.supportsLocalNeuralNarration)
                Link("Built with Fish Audio · License", destination: URL(string: "https://github.com/fishaudio/fish-speech/blob/main/LICENSE")!)
            }

            Section("Local TTS Server") {
                Text("Connect to a server you run on this Mac. The server receives passage text and manages its own privacy behavior.")
                    .foregroundStyle(.secondary)
                if !environment.supportsLocalNeuralNarration {
                    Text("Custom voices require Apple Silicon. macOS system voices remain available.")
                        .foregroundStyle(.secondary)
                }
                TextField("Display name", text: $draft.name)
                    .accessibilityLabel("Server display name")
                Picker("Host", selection: $draft.host) {
                    ForEach(LocalVoiceServerDraft.Host.allCases) { host in
                        Text(host.label).tag(host)
                    }
                }
                TextField("Port", text: $draft.port)
                    .accessibilityLabel("Local server port")
                TextField("Model ID", text: $draft.modelID)
                TextField("Voice ID", text: $draft.voiceID)
                SecureField("Optional access token", text: $draft.token)
                    .disabled(removesSavedToken)
                    .accessibilityHint("Stored in macOS Keychain. Leave blank to keep the current token when editing.")
                if editingServerID != nil {
                    Toggle("Remove saved access token", isOn: $removesSavedToken)
                }
                HStack {
                    Button(editingServerID == nil ? "Add Server" : "Save Server") { saveServer() }
                        .disabled(catalog == nil || isBusy || !environment.supportsLocalNeuralNarration)
                    if editingServerID != nil {
                        Button("Cancel Editing") { clearServerDraft() }
                    }
                }
            }

            if let catalog {
                Section("Your Voices") {
                    if catalog.entries.isEmpty {
                        Text("No custom voices yet. System voices remain available in each book.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(catalog.entries) { entry in
                        entryRow(entry)
                    }
                }
            }

            if isBusy {
                ProgressView("Preparing voice…")
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(isPresented: $isLinking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            perform { try catalog?.linkModel(at: url) }
        }
        .fileImporter(isPresented: $isCopying, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            isBusy = true
            Task {
                defer { isBusy = false }
                do { _ = try await catalog?.copyModel(from: url) } catch { actionError = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $isReconnecting, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first, let id = reconnectID else { return }
            reconnectID = nil
            perform {
                try catalog?.reconnectLinkedModel(id: id, at: url)
                inaccessibleIDs.remove(id)
            }
        }
        .confirmationDialog("Move this model to Trash?", isPresented: $confirmsManagedRemoval) {
            Button("Move to Trash", role: .destructive) {
                guard let id = pendingManagedRemoval else { return }
                pendingManagedRemoval = nil
                perform { try catalog?.remove(id: id, confirmedManagedDeletion: true) }
            }
            Button("Cancel", role: .cancel) { pendingManagedRemoval = nil }
        } message: {
            Text("The model copy stored by Avail will be moved to Trash. Your original folder, if any, is unaffected.")
        }
        .alert(
            "Voice action failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK") { actionError = nil }
        } message: {
            Text("\(actionError ?? "The voice could not be changed.") Check the model folder or local server settings and try again.")
        }
        .onChange(of: catalog?.entries, initial: true) { _, entries in
            refreshAccess(entries ?? [])
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: VoiceModelEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name).font(.headline)
                Spacer()
                if inaccessibleIDs.contains(entry.id) {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Text(sourceDescription(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(previewingID == entry.id ? "Testing…" : "Test Voice") { preview(entry) }
                    .disabled(isBusy || previewingID != nil || inaccessibleIDs.contains(entry.id) || !environment.supportsLocalNeuralNarration)
                if entry.source == .linked {
                    Button("Reconnect…") {
                        reconnectID = entry.id
                        isReconnecting = true
                    }
                }
                if entry.source == .loopbackServer {
                    Button("Edit") { editServer(entry) }
                }
                Button("Remove", role: .destructive) { remove(entry) }
                    .disabled(isBusy)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func sourceDescription(_ entry: VoiceModelEntry) -> String {
        switch entry.source {
        case .linked: "Linked Fish Audio model · Built with Fish Audio"
        case .managed: "Copied Fish Audio model · Built with Fish Audio"
        case .loopbackServer: "Local server · \(entry.serverURL?.absoluteString ?? "Address unavailable")"
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { actionError = error.localizedDescription }
    }

    private func saveServer() {
        guard let catalog else { return }
        perform {
            let url = try draft.baseURL()
            if let editingServerID {
                try catalog.updateServer(
                    id: editingServerID, name: draft.name, baseURL: url,
                    modelID: draft.modelID, voiceID: draft.voiceID,
                    authToken: removesSavedToken ? "" : (draft.token.isEmpty ? nil : draft.token)
                )
            } else {
                try catalog.addServer(
                    name: draft.name, baseURL: url, modelID: draft.modelID,
                    voiceID: draft.voiceID, authToken: draft.token.isEmpty ? nil : draft.token
                )
            }
            clearServerDraft()
        }
    }

    private func editServer(_ entry: VoiceModelEntry) {
        editingServerID = entry.id
        removesSavedToken = false
        draft = LocalVoiceServerDraft(
            name: entry.name,
            host: entry.serverHost == "::1" ? .ipv6 : .ipv4,
            port: entry.serverPort.map(String.init) ?? "8080",
            modelID: entry.modelID ?? "",
            voiceID: entry.voiceID ?? "",
            token: ""
        )
    }

    private func clearServerDraft() {
        editingServerID = nil
        removesSavedToken = false
        draft = LocalVoiceServerDraft()
    }

    private func remove(_ entry: VoiceModelEntry) {
        if entry.source == .managed {
            pendingManagedRemoval = entry.id
            confirmsManagedRemoval = true
        } else {
            perform { try catalog?.remove(id: entry.id) }
        }
    }

    private func preview(_ entry: VoiceModelEntry) {
        previewingID = entry.id
        Task {
            defer { previewingID = nil }
            do { try await environment.previewVoice(id: entry.providerVoiceID) } catch { actionError = error.localizedDescription }
        }
    }

    private func refreshAccess(_ entries: [VoiceModelEntry]) {
        guard let catalog else { return }
        inaccessibleIDs = Set(
            entries.filter { entry in
                guard entry.source != .loopbackServer else { return false }
                return (try? catalog.beginModelAccess(id: entry.id)) == nil
            }.map(\.id))
    }
}

import AvailPlayback
import Foundation

@MainActor
final class CompositeNarrationEngine: NarrationEngine {
    private let system: SystemNarrationEngine
    private let generated: GeneratedNarrationEngine
    private let catalog: VoiceModelCatalog
    private let helper = NeuralHelperClient()
    private let stream: AsyncStream<NarrationEvent>
    private let continuation: AsyncStream<NarrationEvent>.Continuation
    private var systemEventsTask: Task<Void, Never>?
    private var generatedEventsTask: Task<Void, Never>?
    private var activeIsGenerated = false

    var voices: [NarrationVoice] {
        let systemVoices = system.voices.map {
            NarrationVoice(id: "system:\($0.id)", name: $0.name, languageCode: $0.languageCode)
        }
        #if arch(arm64)
            return systemVoices
                + catalog.entries.map {
                    NarrationVoice(id: $0.providerVoiceID, name: $0.name, languageCode: "")
                }
        #else
            return systemVoices
        #endif
    }

    var events: AsyncStream<NarrationEvent> { stream }

    init(catalog: VoiceModelCatalog, cacheURL: URL) {
        self.catalog = catalog
        system = SystemNarrationEngine()
        (stream, continuation) = AsyncStream.makeStream(of: NarrationEvent.self)
        generated = GeneratedNarrationEngine(
            cacheURL: cacheURL,
            available: { [weak catalog] in
                catalog?.entries.map { NarrationVoice(id: $0.providerVoiceID, name: $0.name, languageCode: "") } ?? []
            },
            cacheIdentity: { [weak catalog] voiceID in
                guard let catalog else { return voiceID }
                return try await catalog.synthesisCacheIdentity(forProviderVoiceID: voiceID)
            },
            prepare: { [weak catalog, helper] voiceID in
                guard let catalog,
                    let modelID = UUID(uuidString: String(voiceID.dropFirst("neural:".count))),
                    let entry = catalog.entries.first(where: { $0.id == modelID })
                else { throw VoiceModelCatalogError.missingEntry }
                guard entry.source == .linked || entry.source == .managed else { return }
                let lease: VoiceModelAccessLease
                do {
                    lease = try catalog.beginModelAccess(id: entry.id)
                } catch {
                    throw VoiceModelCatalogError.inaccessibleModel
                }
                let bookmark: Data
                do {
                    bookmark = try lease.makeHelperTransferBookmark()
                } catch {
                    throw VoiceModelCatalogError.inaccessibleModel
                }
                try await helper.prepareModel(bookmark: bookmark)
            },
            generate: { [weak catalog, helper] voiceID, text in
                guard let catalog,
                    let modelID = UUID(uuidString: String(voiceID.dropFirst("neural:".count))),
                    let entry = catalog.entries.first(where: { $0.id == modelID })
                else { throw VoiceModelCatalogError.missingEntry }
                switch entry.source {
                case .linked, .managed:
                    let lease: VoiceModelAccessLease
                    do {
                        lease = try catalog.beginModelAccess(id: entry.id)
                    } catch {
                        throw VoiceModelCatalogError.inaccessibleModel
                    }
                    let bookmark: Data
                    do {
                        bookmark = try lease.makeHelperTransferBookmark()
                    } catch {
                        throw VoiceModelCatalogError.inaccessibleModel
                    }
                    let result = try await helper.synthesize(requestID: UUID(), bookmark: bookmark, text: text)
                    return GeneratedAudio(wavData: result.wav, sampleRate: result.sampleRate)
                case .loopbackServer:
                    guard let url = entry.serverURL, let model = entry.modelID, let voice = entry.voiceID else {
                        throw VoiceModelCatalogError.invalidServerFields
                    }
                    let configuration = try LocalSpeechServerConfiguration(
                        baseURL: url, modelID: model, voiceID: voice, authToken: try catalog.authToken(for: entry.id)
                    )
                    return try await LocalSpeechServerClient(configuration: configuration).synthesize(text: text)
                }
            })
        let systemEvents = system.events
        systemEventsTask = Task { [weak self] in
            for await event in systemEvents {
                guard let self else { return }
                if case let .voiceFallback(requested, selected) = event {
                    self.continuation.yield(
                        .voiceFallback(
                            requestedIdentifier: requested,
                            selectedIdentifier: selected.map { "system:\($0)" }
                        ))
                } else {
                    self.continuation.yield(event)
                }
            }
        }
        let generatedEvents = generated.events
        generatedEventsTask = Task { [weak self] in
            for await event in generatedEvents { self?.continuation.yield(event) }
        }
    }

    func speak(_ request: NarrationRequest) {
        if let id = request.voiceIdentifier, id.hasPrefix("neural:") {
            system.stop()
            activeIsGenerated = true
            generated.speak(request)
        } else {
            generated.stop()
            activeIsGenerated = false
            let rawID =
                request.voiceIdentifier?.hasPrefix("system:") == true
                ? String(request.voiceIdentifier!.dropFirst("system:".count))
                : request.voiceIdentifier
            system.speak(
                NarrationRequest(
                    chunk: request.chunk, voiceIdentifier: rawID, languageCode: request.languageCode,
                    rate: request.rate, speedMultiplier: request.speedMultiplier,
                    startUTF16Offset: request.startUTF16Offset
                ))
        }
    }

    func pause() { activeIsGenerated ? generated.pause() : system.pause() }
    func resume() { activeIsGenerated ? generated.resume() : system.resume() }
    func stop() {
        generated.stop()
        system.stop()
    }

    func synthesizePreview(voiceID: String, text: String) async throws -> GeneratedAudio {
        guard voiceID.hasPrefix("neural:") else { throw VoiceModelCatalogError.missingEntry }
        guard let entryID = UUID(uuidString: String(voiceID.dropFirst("neural:".count))),
            let entry = catalog.entries.first(where: { $0.id == entryID })
        else { throw VoiceModelCatalogError.missingEntry }
        switch entry.source {
        case .linked, .managed:
            let lease: VoiceModelAccessLease
            do {
                lease = try catalog.beginModelAccess(id: entry.id)
            } catch {
                throw VoiceModelCatalogError.inaccessibleModel
            }
            let bookmark: Data
            do {
                bookmark = try lease.makeHelperTransferBookmark()
            } catch {
                throw VoiceModelCatalogError.inaccessibleModel
            }
            try await helper.prepareModel(bookmark: bookmark)
            let result = try await helper.synthesize(requestID: UUID(), bookmark: bookmark, text: text)
            return GeneratedAudio(wavData: result.wav, sampleRate: result.sampleRate)
        case .loopbackServer:
            guard let url = entry.serverURL, let model = entry.modelID, let voice = entry.voiceID else {
                throw VoiceModelCatalogError.invalidServerFields
            }
            let configuration = try LocalSpeechServerConfiguration(
                baseURL: url, modelID: model, voiceID: voice, authToken: try catalog.authToken(for: entry.id)
            )
            return try await LocalSpeechServerClient(configuration: configuration).synthesize(text: text)
        }
    }
}

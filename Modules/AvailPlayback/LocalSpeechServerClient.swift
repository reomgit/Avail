import Foundation

public enum LocalSpeechServerError: LocalizedError, Sendable {
    case invalidEndpoint
    case invalidRequest
    case unavailable(Int)
    case invalidAudio
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Choose a server at literal 127.0.0.1 or ::1 with an HTTP port."
        case .invalidRequest: "Enter a model and voice ID, and try a shorter passage."
        case .unavailable(let status): "The local voice server returned HTTP \(status). Check it in Voices settings."
        case .invalidAudio: "The local voice server did not return a playable WAV file."
        case .responseTooLarge: "The local voice server returned more audio than Avail can play for one phrase."
        }
    }
}

public struct GeneratedAudio: Sendable {
    public let wavData: Data
    public let sampleRate: Int

    public init(wavData: Data, sampleRate: Int) {
        self.wavData = wavData
        self.sampleRate = sampleRate
    }
}

public struct LocalSpeechServerConfiguration: Sendable {
    public let baseURL: URL
    public let modelID: String
    public let voiceID: String
    public let authToken: String?

    public init(baseURL: URL, modelID: String, voiceID: String, authToken: String? = nil) throws {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            components.scheme == "http",
            let host = components.host,
            host == "127.0.0.1" || host == "[::1]",
            let port = components.port,
            (1...65_535).contains(port),
            components.user == nil,
            components.password == nil,
            components.path.isEmpty || components.path == "/",
            components.query == nil,
            components.fragment == nil
        else { throw LocalSpeechServerError.invalidEndpoint }
        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty, !trimmedVoice.isEmpty else { throw LocalSpeechServerError.invalidRequest }
        self.baseURL = baseURL
        self.modelID = trimmedModel
        self.voiceID = trimmedVoice
        self.authToken = authToken?.isEmpty == false ? authToken : nil
    }

    func makeRequest(text: String) throws -> URLRequest {
        guard !text.isEmpty, text.utf16.count <= 1_000 else { throw LocalSpeechServerError.invalidRequest }
        var request = URLRequest(url: baseURL.appending(path: "v1/audio/speech"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/wav", forHTTPHeaderField: "Accept")
        if let authToken { request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "voice": voiceID,
            "input": text,
            "response_format": "wav",
        ])
        return request
    }
}

public final class LocalSpeechServerClient: @unchecked Sendable {
    private let configuration: LocalSpeechServerConfiguration
    private let session: URLSession
    private static let maximumResponseBytes = 16 * 1_024 * 1_024

    public init(
        configuration: LocalSpeechServerConfiguration,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.configuration = configuration
        let copy = sessionConfiguration.copy() as! URLSessionConfiguration
        copy.httpShouldSetCookies = false
        copy.httpCookieAcceptPolicy = .never
        copy.requestCachePolicy = .reloadIgnoringLocalCacheData
        copy.urlCache = nil
        session = URLSession(configuration: copy, delegate: RejectRedirectDelegate(), delegateQueue: nil)
    }

    public func synthesize(text: String) async throws -> GeneratedAudio {
        let request = try configuration.makeRequest(text: text)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse,
            http.url?.host == request.url?.host,
            http.url?.port == request.url?.port
        else { throw LocalSpeechServerError.invalidEndpoint }
        guard http.statusCode == 200 else { throw LocalSpeechServerError.unavailable(http.statusCode) }
        if http.expectedContentLength > Self.maximumResponseBytes {
            throw LocalSpeechServerError.responseTooLarge
        }
        var data = Data()
        data.reserveCapacity(max(0, min(Int(http.expectedContentLength), Self.maximumResponseBytes)))
        for try await byte in bytes {
            guard data.count < Self.maximumResponseBytes else { throw LocalSpeechServerError.responseTooLarge }
            data.append(byte)
        }
        guard let sampleRate = Self.wavSampleRate(data) else { throw LocalSpeechServerError.invalidAudio }
        return GeneratedAudio(wavData: data, sampleRate: sampleRate)
    }

    private static func wavSampleRate(_ data: Data) -> Int? {
        guard data.count >= 36,
            String(data: data[0..<4], encoding: .ascii) == "RIFF",
            String(data: data[8..<12], encoding: .ascii) == "WAVE"
        else { return nil }
        var offset = 12
        var sampleRate: Int?
        var hasAudio = false
        while offset + 8 <= data.count {
            let name = String(data: data[offset..<(offset + 4)], encoding: .ascii)
            let size = Int(readUInt32(data, at: offset + 4))
            let start = offset + 8
            guard size <= data.count - start else { return nil }
            if name == "fmt ", size >= 16 {
                sampleRate = Int(readUInt32(data, at: start + 4))
            } else if name == "data", size > 0 {
                hasAudio = true
            }
            offset = start + size + (size & 1)
        }
        guard hasAudio, let sampleRate, (8_000...192_000).contains(sampleRate) else { return nil }
        return sampleRate
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private final class RejectRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

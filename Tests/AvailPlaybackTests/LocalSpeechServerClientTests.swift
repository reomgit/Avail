import Foundation
import XCTest
@testable import AvailPlayback

final class LocalSpeechServerClientTests: XCTestCase {
    func testRejectsNonLoopbackAndMalformedEndpoints() {
        for url in [
            "http://192.168.1.3:8080",
            "https://127.0.0.1:8080",
            "http://localhost:8080",
            "http://127.0.0.1:8080/custom",
            "http://127.0.0.1:8080?next=example.com",
        ] {
            XCTAssertThrowsError(
                try LocalSpeechServerConfiguration(
                    baseURL: URL(string: url)!,
                    modelID: "voice-model",
                    voiceID: "narrator"
                ),
                url
            )
        }
    }

    func testSpeechRequestUsesOnlyConfiguredLoopbackEndpoint() throws {
        let configuration = try LocalSpeechServerConfiguration(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            modelID: "fish-local",
            voiceID: "reader",
            authToken: "local-secret"
        )
        let request = try configuration.makeRequest(text: "Synthetic narration sample.")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8080/v1/audio/speech")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-secret")
        XCTAssertEqual(json["model"] as? String, "fish-local")
        XCTAssertEqual(json["voice"] as? String, "reader")
        XCTAssertEqual(json["input"] as? String, "Synthetic narration sample.")
        XCTAssertEqual(json["response_format"] as? String, "wav")
    }

    func testRejectsRemoteRedirectWithoutFollowingIt() async throws {
        let configuration = try LocalSpeechServerConfiguration(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            modelID: "fish-local",
            voiceID: "reader"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RedirectProtocol.self]
        RedirectProtocol.requests = []
        let client = LocalSpeechServerClient(configuration: configuration, sessionConfiguration: sessionConfiguration)

        do {
            _ = try await client.synthesize(text: "Synthetic narration sample.")
            XCTFail("Expected a rejected redirect")
        } catch {
            XCTAssertEqual(RedirectProtocol.requests.count, 1)
            XCTAssertEqual(RedirectProtocol.requests.first?.host, "127.0.0.1")
        }
    }

    func testReportsActionableServerHTTPFailure() async throws {
        let configuration = try LocalSpeechServerConfiguration(
            baseURL: URL(string: "http://127.0.0.1:8080")!, modelID: "fish-local", voiceID: "reader"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [FailureProtocol.self]
        let client = LocalSpeechServerClient(configuration: configuration, sessionConfiguration: sessionConfiguration)

        do {
            _ = try await client.synthesize(text: "Synthetic narration sample.")
            XCTFail("Expected the stopped server to report an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The local voice server returned HTTP 503. Check it in Voices settings.")
        }
    }
}

private final class RedirectProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.append(url)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://example.com/receive-book-text"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

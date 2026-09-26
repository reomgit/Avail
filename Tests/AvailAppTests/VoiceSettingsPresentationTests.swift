import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class VoiceSettingsPresentationTests: XCTestCase {
    func testServerDraftAcceptsOnlyLiteralLoopbackHostAndPort() throws {
        let draft = LocalVoiceServerDraft(
            name: "Desk voice", host: .ipv4, port: "8080", modelID: "fish-speech", voiceID: "default", token: ""
        )

        XCTAssertEqual(try draft.baseURL().absoluteString, "http://127.0.0.1:8080")
        XCTAssertThrowsError(try draft.withPort("0").baseURL())
        XCTAssertThrowsError(try draft.withPort("65536").baseURL())
        XCTAssertThrowsError(try draft.withPort("abc").baseURL())
        XCTAssertEqual(try draft.withHost(.ipv6).baseURL().absoluteString, "http://[::1]:8080")
    }

    func testVoiceGroupsKeepSystemAndImportedVoicesSeparate() {
        let linked = VoiceModelEntry(
            id: UUID(), name: "Fish local", source: .linked, modelID: nil, voiceID: nil,
            serverURL: nil, bookmarkData: Data(), managedDirectoryName: nil
        )
        let server = VoiceModelEntry(
            id: UUID(), name: "Desk server", source: .loopbackServer, modelID: "fish", voiceID: "default",
            serverURL: URL(string: "http://127.0.0.1:8080"), bookmarkData: nil, managedDirectoryName: nil
        )
        let groups = VoicePickerGroups(entries: [server, linked])

        XCTAssertEqual(groups.imported.map(\.id), [linked.id])
        XCTAssertEqual(groups.servers.map(\.id), [server.id])
        XCTAssertEqual(groups.imported.first?.providerVoiceID, "neural:\(linked.id.uuidString)")
    }
}

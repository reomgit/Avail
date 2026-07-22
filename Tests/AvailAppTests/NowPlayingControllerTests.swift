import Foundation
import MediaPlayer
import XCTest
@testable import AvailApp

@MainActor
final class NowPlayingControllerTests: XCTestCase {
    func testSnapshotPopulatesNativeNowPlayingKeysAndMapsPlaybackState() {
        let infoCenter = FakeNowPlayingInfoCenter()
        let commands = FakeRemoteCommandDriver()
        let controller = NowPlayingController(infoCenter: infoCenter, remoteCommands: commands)
        let snapshot = NowPlayingSnapshot(
            title: "The Book",
            artist: "The Author",
            chapterTitle: "A Beginning",
            chapterNumber: 2,
            artworkData: nil,
            estimatedDuration: 3_600,
            elapsedTime: 125,
            playbackRate: 1.25
        )

        controller.update(snapshot)
        controller.updatePlaybackState(.playing)

        XCTAssertEqual(infoCenter.info?[MPMediaItemPropertyTitle] as? String, "The Book")
        XCTAssertEqual(infoCenter.info?[MPMediaItemPropertyArtist] as? String, "The Author")
        XCTAssertEqual(infoCenter.info?[MPMediaItemPropertyAlbumTitle] as? String, "A Beginning")
        XCTAssertEqual(infoCenter.info?[MPNowPlayingInfoPropertyChapterNumber] as? Int, 2)
        XCTAssertEqual(infoCenter.info?[MPMediaItemPropertyPlaybackDuration] as? Double, 3_600)
        XCTAssertEqual(infoCenter.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 125)
        XCTAssertEqual(infoCenter.info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.25)
        XCTAssertEqual(infoCenter.state, .playing)

        controller.updatePlaybackState(.paused)
        XCTAssertEqual(infoCenter.state, .paused)
        controller.updatePlaybackState(.bufferingForIndex)
        XCTAssertEqual(infoCenter.state, .paused)
        controller.updatePlaybackState(.stopped)
        XCTAssertEqual(infoCenter.state, .stopped)
        XCTAssertNil(infoCenter.info)
    }

    func testRemoteHandlersAreInstalledAndTeardownRemovesTargets() {
        let infoCenter = FakeNowPlayingInfoCenter()
        let commands = FakeRemoteCommandDriver()
        let controller = NowPlayingController(infoCenter: infoCenter, remoteCommands: commands)
        var playCount = 0
        var pauseCount = 0
        var changedPosition: TimeInterval?
        let handlers = NowPlayingHandlers(
            play: { playCount += 1 },
            pause: { pauseCount += 1 },
            toggle: {},
            nextChapter: {},
            previousChapter: {},
            skipForward: {},
            skipBackward: {},
            changePosition: { changedPosition = $0 }
        )

        controller.installRemoteCommands(handlers)
        commands.handlers?.play()
        commands.handlers?.pause()
        commands.handlers?.changePosition(42)

        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(pauseCount, 1)
        XCTAssertEqual(changedPosition, 42)

        controller.teardown()
        XCTAssertEqual(commands.teardownCallCount, 1)
        XCTAssertNil(infoCenter.info)
    }
}

@MainActor
private final class FakeNowPlayingInfoCenter: NowPlayingInfoCenterDriving {
    var info: [String: Any]?
    var state: SystemNowPlayingState = .stopped
    func setNowPlayingInfo(_ info: [String: Any]?) { self.info = info }
    func setPlaybackState(_ state: SystemNowPlayingState) { self.state = state }
}

@MainActor
private final class FakeRemoteCommandDriver: RemoteCommandDriving {
    private(set) var handlers: NowPlayingHandlers?
    private(set) var teardownCallCount = 0
    func install(_ handlers: NowPlayingHandlers) { self.handlers = handlers }
    func teardown() {
        handlers = nil
        teardownCallCount += 1
    }
}

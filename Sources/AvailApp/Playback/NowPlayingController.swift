import AppKit
import Foundation
@preconcurrency import MediaPlayer

struct NowPlayingSnapshot: Equatable {
    var title: String
    var artist: String?
    var chapterTitle: String?
    var chapterNumber: Int?
    var artworkData: Data?
    var estimatedDuration: TimeInterval
    var elapsedTime: TimeInterval
    var playbackRate: Double
}

struct NowPlayingHandlers {
    var play: @MainActor () -> Void
    var pause: @MainActor () -> Void
    var toggle: @MainActor () -> Void
    var nextChapter: @MainActor () -> Void
    var previousChapter: @MainActor () -> Void
    var skipForward: @MainActor () -> Void
    var skipBackward: @MainActor () -> Void
    var changePosition: @MainActor (TimeInterval) -> Void
}

enum SystemNowPlayingState: Equatable {
    case stopped
    case playing
    case paused
}

@MainActor
protocol NowPlayingInfoCenterDriving: AnyObject {
    func setNowPlayingInfo(_ info: [String: Any]?)
    func setPlaybackState(_ state: SystemNowPlayingState)
}

@MainActor
protocol RemoteCommandDriving: AnyObject {
    func install(_ handlers: NowPlayingHandlers)
    func teardown()
}

@MainActor
protocol NowPlayingControlling: AnyObject {
    func update(_ snapshot: NowPlayingSnapshot)
    func updatePlaybackState(_ state: PlaybackState)
    func installRemoteCommands(_ handlers: NowPlayingHandlers)
    func teardown()
}

@MainActor
final class NowPlayingController: NowPlayingControlling {
    private let infoCenter: any NowPlayingInfoCenterDriving
    private let remoteCommands: any RemoteCommandDriving

    convenience init() {
        self.init(
            infoCenter: SystemNowPlayingInfoCenter(),
            remoteCommands: MediaRemoteCommandDriver()
        )
    }

    init(
        infoCenter: any NowPlayingInfoCenterDriving,
        remoteCommands: any RemoteCommandDriving
    ) {
        self.infoCenter = infoCenter
        self.remoteCommands = remoteCommands
    }

    func update(_ snapshot: NowPlayingSnapshot) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyPlaybackDuration: snapshot.estimatedDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
        ]
        if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
        if let chapterTitle = snapshot.chapterTitle { info[MPMediaItemPropertyAlbumTitle] = chapterTitle }
        if let chapterNumber = snapshot.chapterNumber {
            info[MPNowPlayingInfoPropertyChapterNumber] = chapterNumber
        }
        if let artworkData = snapshot.artworkData, let image = NSImage(data: artworkData) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        infoCenter.setNowPlayingInfo(info)
    }

    func updatePlaybackState(_ state: PlaybackState) {
        switch state {
        case .playing:
            infoCenter.setPlaybackState(.playing)
        case .paused, .bufferingForIndex, .seeking:
            infoCenter.setPlaybackState(.paused)
        case .stopped, .failed:
            infoCenter.setPlaybackState(.stopped)
        }
    }

    func installRemoteCommands(_ handlers: NowPlayingHandlers) {
        remoteCommands.install(handlers)
    }

    func teardown() {
        remoteCommands.teardown()
        infoCenter.setPlaybackState(.stopped)
        infoCenter.setNowPlayingInfo(nil)
    }
}

@MainActor
private final class SystemNowPlayingInfoCenter: NowPlayingInfoCenterDriving {
    private let center = MPNowPlayingInfoCenter.default()

    func setNowPlayingInfo(_ info: [String: Any]?) {
        center.nowPlayingInfo = info
    }

    func setPlaybackState(_ state: SystemNowPlayingState) {
        switch state {
        case .stopped: center.playbackState = .stopped
        case .playing: center.playbackState = .playing
        case .paused: center.playbackState = .paused
        }
    }
}

@MainActor
private final class MediaRemoteCommandDriver: RemoteCommandDriving {
    private struct Registration {
        let command: MPRemoteCommand
        let target: Any
    }

    private let center = MPRemoteCommandCenter.shared()
    private var registrations: [Registration] = []

    func install(_ handlers: NowPlayingHandlers) {
        teardown()
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]

        register(center.playCommand) { _ in
            handlers.play()
            return .success
        }
        register(center.pauseCommand) { _ in
            handlers.pause()
            return .success
        }
        register(center.togglePlayPauseCommand) { _ in
            handlers.toggle()
            return .success
        }
        register(center.nextTrackCommand) { _ in
            handlers.nextChapter()
            return .success
        }
        register(center.previousTrackCommand) { _ in
            handlers.previousChapter()
            return .success
        }
        register(center.skipForwardCommand) { _ in
            handlers.skipForward()
            return .success
        }
        register(center.skipBackwardCommand) { _ in
            handlers.skipBackward()
            return .success
        }
        register(center.changePlaybackPositionCommand) { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            handlers.changePosition(positionEvent.positionTime)
            return .success
        }
    }

    func teardown() {
        for registration in registrations {
            registration.command.removeTarget(registration.target)
        }
        registrations.removeAll(keepingCapacity: true)
    }

    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        registrations.append(Registration(command: command, target: target))
    }
}

import MediaPlayer
import MetronomeCore

/// 锁屏和控制中心的播放控制。
final class NowPlayingBridge {
    private var targets: [(MPRemoteCommand, Any)] = []

    func connect(play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void) {
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
            command.isEnabled = true
            targets.append((command, command.addTarget { _ in
                action()
                return .success
            }))
        }
        bind(center.playCommand, play)
        bind(center.pauseCommand, pause)
        bind(center.togglePlayPauseCommand, toggle)
        for unused in [center.nextTrackCommand, center.previousTrackCommand, center.skipForwardCommand,
                       center.skipBackwardCommand, center.changePlaybackPositionCommand] {
            unused.isEnabled = false
        }
    }

    func update(config: MetronomeConfig, isPlaying: Bool) {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: String(localized: "节拍器 · \(Int(config.bpm)) BPM", bundle: .appLanguage, locale: .appLanguage),
            MPMediaItemPropertyArtist: "\(config.timeSignature.displayName) · \(config.subdivision.title) · \(config.sound.title)",
            MPMediaItemPropertyAlbumTitle: (Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"]
                ?? Bundle.main.infoDictionary?["CFBundleDisplayName"]) as? String ?? "",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

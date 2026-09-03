import Foundation
import UIKit
import KSPlayer
import AVFoundation

protocol KSPlaybackEngineDelegate: AnyObject {
    func engineDidDetectNativeVideoSize(_ size: CGSize)
    func engineDidStop()
}

typealias VLCPlaybackEngineDelegate = KSPlaybackEngineDelegate

// MARK: - Playback Record & History Manager

public struct PlaybackRecord: Codable {
    public let key: String
    public let savedTime: Double
    public let totalDuration: Double
    public let date: Date
    
    public init(key: String, savedTime: Double, totalDuration: Double, date: Date = Date()) {
        self.key = key
        self.savedTime = savedTime
        self.totalDuration = totalDuration
        self.date = date
    }
}

public final class PlaybackHistoryManager {
    public static let shared = PlaybackHistoryManager()
    
    private let userDefaultsKey = "SwiftyTorrent_PlaybackHistory_v1"
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    public func key(for url: URL?, title: String?) -> String? {
        if let url = url {
            let path = url.path
            if let range = path.range(of: "/Downloads/") {
                return String(path[range.upperBound...])
            }
            if !url.lastPathComponent.isEmpty {
                return url.lastPathComponent
            }
        }
        if let title = title, !title.isEmpty {
            return title
        }
        return nil
    }
    
    public func getRecord(for key: String) -> PlaybackRecord? {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let dict = try? JSONDecoder().decode([String: PlaybackRecord].self, from: data) else {
            return nil
        }
        return dict[key]
    }
    
    public func savePosition(for key: String, currentTime: Double, totalDuration: Double) {
        guard currentTime >= 5.0 else { return }
        
        var dict: [String: PlaybackRecord] = [:]
        if let data = defaults.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: PlaybackRecord].self, from: data) {
            dict = decoded
        }
        
        if totalDuration > 0 && currentTime >= (totalDuration - 15.0) {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = PlaybackRecord(key: key, savedTime: currentTime, totalDuration: totalDuration)
        }
        
        if let encoded = try? JSONEncoder().encode(dict) {
            defaults.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    public func clearPosition(for key: String) {
        guard let data = defaults.data(forKey: userDefaultsKey),
              var dict = try? JSONDecoder().decode([String: PlaybackRecord].self, from: data) else {
            return
        }
        dict.removeValue(forKey: key)
        if let encoded = try? JSONEncoder().encode(dict) {
            defaults.set(encoded, forKey: userDefaultsKey)
        }
    }
}

final class KSVideoHostView: PlayerView {
    
    private weak var currentVideoView: UIView?
    
    override func set(url: URL, options: KSOptions) {
        super.set(url: url, options: options)
        attachCurrentPlayerView()
    }
    
    override func player(layer: KSPlayerLayer, state: KSPlayerState) {
        super.player(layer: layer, state: state)
        attachCurrentPlayerView()
    }
    
    func attachCurrentPlayerView() {
        guard let layer = playerLayer, let videoView = layer.player.view else {
            return
        }
        if videoView != currentVideoView || videoView.superview != self {
            currentVideoView?.removeFromSuperview()
            currentVideoView = videoView
            videoView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(videoView)
            sendSubviewToBack(videoView)
            NSLayoutConstraint.activate([
                videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
                videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
                videoView.topAnchor.constraint(equalTo: topAnchor),
                videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            print("[KSVideoHostView] Successfully attached videoView (\(type(of: videoView))) to KSVideoHostView (bounds: \(bounds))")
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        attachCurrentPlayerView()
    }
}

final class KSPlaybackEngine: NSObject, PlayerControllerDelegate {
    
    let playerView: KSVideoHostView
    weak var delegate: KSPlaybackEngineDelegate?
    private let playerVM: PlayerViewModel
    
    public var currentMediaKey: String?
    private var resumeAttempts = 0
    public var pendingResumeTime: Double? {
        didSet {
            resumeAttempts = 0
        }
    }
    private var activeRoute: PlaybackRoute?
    
    private var hasDetectedVideoSize = false
    private var addedAudioTracks = false
    private var addedSubsTracks = false
    private var lastRecordedSecond: Int = -1
    
    public var isPlaying: Bool {
        return playerVM.isPlaying
    }
    
    public var position: Float {
        return playerVM.progress.position
    }
    
    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
        self.playerView = KSVideoHostView()
        super.init()
        
        // Hide default KSPlayer toolbars so SwiftyTorrent's custom controls overlay takes over
        self.playerView.toolBar.isHidden = true
        self.playerView.delegate = self
    }
    
    public func load(url: URL?, title: String?) {
        print("[KSPlaybackEngine] load called with url: \(url?.absoluteString ?? "nil"), title: \(title ?? "nil")")
        self.currentMediaKey = PlaybackHistoryManager.shared.key(for: url, title: title)
        
        activeRoute?.cleanup()
        activeRoute = nil
        
        if let url = url {
            let route = PlaybackRouter.resolveRoute(for: url)
            self.activeRoute = route
            
            let options = KSOptions()
            options.videoDisable = false
            KSOptions.isAutoPlay = false
            
            switch route {
            case .directAVPlayer(let targetURL):
                KSOptions.firstPlayerType = KSAVPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                playerView.set(url: targetURL, options: options)
                
            case .transmuxedHLS(_, let hlsURL, _):
                // AVPlayer handles HLS natively with hardware Dolby Vision and Dolby Atmos
                KSOptions.firstPlayerType = KSAVPlayer.self
                KSOptions.secondPlayerType = KSMEPlayer.self
                options.preferredForwardBufferDuration = 1.0
                playerView.set(url: hlsURL, options: options)
                
            case .ffmpegDirect(let targetURL):
                KSOptions.firstPlayerType = KSMEPlayer.self
                KSOptions.secondPlayerType = KSAVPlayer.self
                options.probesize = 5_000_000
                options.maxAnalyzeDuration = 2_000_000
                if url.isFileURL {
                    options.preferredForwardBufferDuration = 0.5
                    options.isSecondOpen = true
                    options.isAccurateSeek = false
                    options.syncDecodeVideo = true
                    options.seekFlags = Int32(1) // AVSEEK_FLAG_BACKWARD
                }
                playerView.set(url: targetURL, options: options)
            }
            
            playerView.attachCurrentPlayerView()
            playerVM.fileName = url.lastPathComponent
        }
        if let title = title {
            playerVM.title = title
        }
        
        playerVM.isBuffering = true
        playerVM.isPlaying = false
        playerVM.isControlsVisible = true
        hasDetectedVideoSize = false
        addedAudioTracks = false
        addedSubsTracks = false
    }
    
    public func play() {
        guard !playerVM.showResumePrompt else {
            print("[KSPlaybackEngine] play() suppressed because showResumePrompt is active")
            return
        }
        print("[KSPlaybackEngine] play() called")
        playerView.play()
        playerVM.isPlaying = true
        playerVM.isBuffering = false
    }
    
    public func pause() {
        print("[KSPlaybackEngine] pause() called")
        playerView.pause()
        playerVM.isPlaying = false
        saveCurrentProgress()
    }
    
    public func stop() {
        print("[KSPlaybackEngine] stop() called")
        saveCurrentProgress()
        playerView.resetPlayer()
        playerVM.isPlaying = false
        activeRoute?.cleanup()
        activeRoute = nil
    }
    
    public func cleanup() {
        print("[KSPlaybackEngine] cleanup() called")
        saveCurrentProgress()
        stop()
        activeRoute?.cleanup()
        activeRoute = nil
        playerView.delegate = nil
    }
    
    private func saveCurrentProgress() {
        guard pendingResumeTime == nil else { return }
        if let key = currentMediaKey {
            PlaybackHistoryManager.shared.savePosition(
                for: key,
                currentTime: playerVM.progress.currentTimeInSeconds,
                totalDuration: playerVM.progress.totalDurationInSeconds
            )
        }
    }
    
    // MARK: - Playback Control
    
    public func jumpForward(seconds: Int32) {
        let current = playerVM.progress.currentTimeInSeconds
        let total = playerVM.progress.totalDurationInSeconds
        let target = min(total > 0 ? total : current + Double(seconds), current + Double(seconds))
        seekTo(seconds: target)
    }
    
    public func jumpBackward(seconds: Int32) {
        let current = playerVM.progress.currentTimeInSeconds
        let target = max(0.0, current - Double(seconds))
        seekTo(seconds: target)
    }
    
    public func seekTo(position: Float) {
        let total = playerVM.progress.totalDurationInSeconds
        if total > 0 {
            let targetSeconds = Double(position) * total
            seekTo(seconds: targetSeconds)
        }
    }
    
    public func seekTo(seconds: Double) {
        pendingResumeTime = seconds
        playerVM.isBuffering = true
        playerVM.isSeeking = true
        playerView.seek(time: seconds) { [weak self] finished in
            guard let self = self else { return }
            self.pendingResumeTime = nil
            DispatchQueue.main.async {
                self.playerVM.isBuffering = false
                self.playerVM.isSeeking = false
                if finished {
                    // Explicitly resume playback after seek — isSeekedAutoPlay triggers
                    // KSMEPlayer.play() internally, but playerVM.isPlaying may be stale.
                    // Calling play() here ensures the VM and engine are in sync.
                    if self.playerVM.isPlaying {
                        self.playerView.play()
                    }
                }
                print("[KSPlaybackEngine] seekTo(\(seconds)) completed, finished=\(finished)")
            }
        }
    }
    
    public func setVolume(_ volume: Float, isHardwareControlled: Bool = true) {
        let clamped = max(0.0, min(1.0, volume))
        playerVM.volume = clamped
        if let player = playerView.playerLayer?.player {
            if isHardwareControlled {
                player.playbackVolume = 1.0
            } else {
                player.playbackVolume = clamped
            }
            player.isMuted = (clamped <= 0.001)
            print("[KSPlaybackEngine] setVolume to \(clamped), isHardware: \(isHardwareControlled), isMuted: \(player.isMuted)")
        }
    }
    
    public func setPlaybackSpeed(_ speed: Float) {
        playerVM.playbackSpeed = speed
        playerView.playerLayer?.player.playbackRate = speed
    }
    
    private func selectTrack(_ track: any MediaPlayerTrack, on player: any MediaPlayerProtocol) {
        player.select(track: track)
    }
    
    public func setAudioTrack(_ index: Int32) {
        print("[KSPlaybackEngine] setAudioTrack called with index: \(index)")
        playerVM.selectedAudioTrack = index
        if let player = playerView.playerLayer?.player {
            let tracks = player.tracks(mediaType: .audio)
            print("[KSPlaybackEngine] Available audio tracks count: \(tracks.count)")
            if index >= 0 && Int(index) < tracks.count {
                let track = tracks[Int(index)]
                print("[KSPlaybackEngine] Selecting audio track: \(track.name)")
                selectTrack(track, on: player)
            }
        }
    }
    
    public func setSubtitleTrack(_ index: Int32) {
        print("[KSPlaybackEngine] setSubtitleTrack called with index: \(index)")
        playerVM.selectedSubtitleTrack = index
        if let player = playerView.playerLayer?.player {
            let tracks = player.tracks(mediaType: .subtitle)
            if index < 0 {
                tracks.forEach { $0.isEnabled = false }
            } else if Int(index) < tracks.count {
                let track = tracks[Int(index)]
                print("[KSPlaybackEngine] Selecting subtitle track: \(track.name)")
                selectTrack(track, on: player)
            }
        }
    }
    
    // MARK: - PlayerControllerDelegate
    
    public func playerController(state: KSPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch state {
            case .initialized, .preparing:
                self.playerVM.isBuffering = true
                
            case .readyToPlay:
                // Attach video view only at readyToPlay — doing it on every state change
                // (including buffering during seeks) triggers layout passes that cause visual freezes.
                self.playerView.attachCurrentPlayerView()
                self.playerVM.isBuffering = false
                self.populateAudioAndSubtitles()
                
                if let player = self.playerView.playerLayer?.player {
                    player.playbackVolume = 1.0
                    player.isMuted = (self.playerVM.volume <= 0.001)
                    print("[KSPlaybackEngine] readyToPlay initialized volume: \(self.playerVM.volume), isMuted: \(player.isMuted)")
                }
                
                if self.playerVM.showResumePrompt {
                    print("[KSPlaybackEngine] showResumePrompt is active. Pausing playback until user choice.")
                    self.playerView.pause()
                    self.playerVM.isPlaying = false
                } else if let pending = self.pendingResumeTime {
                    self.seekTo(seconds: pending)
                }
                
                if !self.hasDetectedVideoSize {
                    if let size = self.playerView.playerLayer?.player.naturalSize, size.width > 0 && size.height > 0 {
                        self.hasDetectedVideoSize = true
                        print("[KSPlaybackEngine] Detected nativeVideoSize at readyToPlay: \(size)")
                        self.delegate?.engineDidDetectNativeVideoSize(size)
                    }
                }
                
            case .buffering:
                // Don't re-attach view or re-populate tracks during buffering — this fires
                // during every seek and the layout churn causes the post-seek video freeze.
                self.playerVM.isBuffering = true
                
            case .bufferFinished:
                self.playerVM.isBuffering = false
                // Restore isPlaying so the UI reflects the actual playing state after a seek.
                if self.playerView.playerLayer?.state == .bufferFinished {
                    self.playerVM.isPlaying = true
                }
                if !self.hasDetectedVideoSize {
                    if let size = self.playerView.playerLayer?.player.naturalSize, size.width > 0 && size.height > 0 {
                        self.hasDetectedVideoSize = true
                        print("[KSPlaybackEngine] Detected nativeVideoSize at bufferFinished: \(size)")
                        self.delegate?.engineDidDetectNativeVideoSize(size)
                    }
                }
                
            case .paused:
                self.playerVM.isPlaying = false
                self.playerVM.isBuffering = false
                self.saveCurrentProgress()
                
            case .playedToTheEnd:
                self.playerVM.isPlaying = false
                self.playerVM.isBuffering = false
                if let key = self.currentMediaKey {
                    PlaybackHistoryManager.shared.clearPosition(for: key)
                }
                self.delegate?.engineDidStop()
                
            case .error:
                self.playerVM.isPlaying = false
                self.playerVM.isBuffering = false
                self.delegate?.engineDidStop()
                
            default:
                break
            }
        }
    }
    
    public func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateTime(currentTime: currentTime, totalDuration: totalTime)
        }
    }
    
    public func playerController(finish error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let error = error {
                if case .transmuxedHLS(let origURL, _, let server) = self.activeRoute {
                    print("[KSPlaybackEngine] Transmuxed playback error: \(error). Falling back to KSMEPlayer for \(origURL.lastPathComponent)")
                    server.stop()
                    self.activeRoute = .ffmpegDirect(url: origURL)
                    KSOptions.firstPlayerType = KSMEPlayer.self
                    let options = KSOptions()
                    options.preferredForwardBufferDuration = 0.5
                    options.isSecondOpen = true
                    options.isAccurateSeek = false
                    options.syncDecodeVideo = true
                    options.seekFlags = Int32(1)
                    self.playerView.set(url: origURL, options: options)
                    self.playerView.attachCurrentPlayerView()
                    self.playerView.play()
                    return
                }
            }
            self.playerVM.isPlaying = false
            self.playerVM.isBuffering = false
            self.delegate?.engineDidStop()
        }
    }
    
    public func playerController(maskShow: Bool) {}
    public func playerController(action: PlayerButtonType) {}
    public func playerController(bufferedCount: Int, consumeTime: TimeInterval) {}
    public func playerController(seek: TimeInterval) {}
    
    // MARK: - Helpers
    
    private func updateTime(currentTime: TimeInterval, totalDuration: TimeInterval) {
        let wholeSecond = Int(currentTime)
        if wholeSecond != lastRecordedSecond {
            lastRecordedSecond = wholeSecond
            playerVM.progress.currentTimeInSeconds = currentTime
            playerVM.progress.currentTime = formatSeconds(currentTime)
            
            if totalDuration > 0 {
                playerVM.progress.totalDurationInSeconds = totalDuration
                playerVM.progress.totalTime = formatSeconds(totalDuration)
                let remaining = max(0, totalDuration - currentTime)
                playerVM.progress.remainingTime = "-\(formatSeconds(remaining))"
                playerVM.progress.position = Float(currentTime / totalDuration)
            }
            
            if !hasDetectedVideoSize {
                if let size = playerView.playerLayer?.player.naturalSize, size.width > 0 && size.height > 0 {
                    hasDetectedVideoSize = true
                    delegate?.engineDidDetectNativeVideoSize(size)
                }
            }
            
            if wholeSecond % 5 == 0, pendingResumeTime == nil, let key = currentMediaKey {
                PlaybackHistoryManager.shared.savePosition(
                    for: key,
                    currentTime: currentTime,
                    totalDuration: playerVM.progress.totalDurationInSeconds
                )
            }
        }
    }
    
    private func formatSeconds(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
    
    private func populateAudioAndSubtitles() {
        guard let player = playerView.playerLayer?.player else { return }
        
        if !addedAudioTracks {
            let audioTracks = player.tracks(mediaType: .audio)
            var list: [Tracks] = []
            for (idx, track) in audioTracks.enumerated() {
                let displayName: String
                if !track.name.isEmpty {
                    displayName = track.name
                } else if let lang = track.languageCode, !lang.isEmpty {
                    displayName = lang.uppercased()
                } else {
                    displayName = "Track \(idx + 1)"
                }
                list.append(Tracks(index: Int32(idx), name: displayName))
            }
            if !list.isEmpty {
                playerVM.audioTracks = list
                let activeIndex = audioTracks.firstIndex(where: { $0.isEnabled }) ?? 0
                playerVM.selectedAudioTrack = Int32(activeIndex)
                addedAudioTracks = true
                print("[KSPlaybackEngine] Populated \(list.count) audio tracks, active index: \(playerVM.selectedAudioTrack)")
            }
        }
        
        if !addedSubsTracks {
            let subTracks = player.tracks(mediaType: .subtitle)
            var list: [Tracks] = [Tracks(index: -1, name: "Off")]
            for (idx, track) in subTracks.enumerated() {
                let displayName: String
                if !track.name.isEmpty {
                    displayName = track.name
                } else if let lang = track.languageCode, !lang.isEmpty {
                    displayName = lang.uppercased()
                } else {
                    displayName = "Subtitle \(idx + 1)"
                }
                list.append(Tracks(index: Int32(idx), name: displayName))
            }
            if list.count > 1 {
                playerVM.subtitleTracks = list
                if let activeIndex = subTracks.firstIndex(where: { $0.isEnabled }) {
                    playerVM.selectedSubtitleTrack = Int32(activeIndex)
                } else {
                    playerVM.selectedSubtitleTrack = -1
                }
                addedSubsTracks = true
                print("[KSPlaybackEngine] Populated \(subTracks.count) subtitle tracks, active index: \(playerVM.selectedSubtitleTrack)")
            }
        }
    }
}

typealias VLCPlaybackEngine = KSPlaybackEngine

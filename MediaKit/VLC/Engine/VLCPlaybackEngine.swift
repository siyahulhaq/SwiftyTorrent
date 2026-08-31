import Foundation

#if os(iOS)
import MobileVLCKit
#elseif os(tvOS)
import TVVLCKit
#endif

public protocol VLCPlaybackEngineDelegate: AnyObject {
    func engineDidDetectNativeVideoSize(_ size: CGSize)
    func engineDidStop()
}

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
            // Video reached end, remove record so next playback starts from beginning
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

public final class VLCPlaybackEngine: NSObject, VLCMediaPlayerDelegate {
    
    public let player: VLCMediaPlayer
    public weak var delegate: VLCPlaybackEngineDelegate?
    private let playerVM: PlayerViewModel
    
    public var currentMediaKey: String?
    private var resumeAttempts = 0
    public var pendingResumeTime: Double? {
        didSet {
            resumeAttempts = 0
        }
    }
    
    private var hasDetectedVideoSize = false
    private var addedAudioTracks = false
    private var addedSubsTracks = false
    private var addedTotalTime = false
    private var lastRecordedSecond: Int = -1
    
    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
        self.player = VLCMediaPlayer()
        super.init()
        self.player.delegate = self
    }
    
    public func load(url: URL?, title: String?) {
        self.currentMediaKey = PlaybackHistoryManager.shared.key(for: url, title: title)
        
        if let url = url {
            let media = VLCMedia(url: url)
            player.media = media
            playerVM.fileName = url.lastPathComponent
        }
        if let title = title {
            playerVM.title = title
        }
        
        playerVM.isBuffering = false
        playerVM.isPlaying = false
        playerVM.isControlsVisible = true
    }
    
    public func play() {
        player.play()
    }
    
    public func pause() {
        player.pause()
        saveCurrentProgress()
    }
    
    public func stop() {
        saveCurrentProgress()
        if player.isPlaying {
            player.stop()
        }
    }
    
    public func cleanup() {
        saveCurrentProgress()
        stop()
        player.drawable = nil
        player.delegate = nil
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
        player.jumpForward(seconds)
    }
    
    public func jumpBackward(seconds: Int32) {
        player.jumpBackward(seconds)
    }
    
    public func seekTo(position: Float) {
        player.position = position
        playerVM.position = position
        updateTime()
    }
    
    public func seekTo(seconds: Double) {
        pendingResumeTime = seconds
        performSeekIfPossible(seconds: seconds)
    }
    
    private func performSeekIfPossible(seconds: Double) {
        guard player.isSeekable else { return }
        
        player.time = VLCTime(number: NSNumber(value: Int(seconds * 1000)))
        
        let duration = player.media?.length.value?.doubleValue ?? (playerVM.progress.totalDurationInSeconds * 1000.0)
        if duration > 0 {
            let targetPos = Float((seconds * 1000.0) / duration)
            if targetPos > 0 && targetPos < 1.0 {
                player.position = targetPos
            }
        }
    }
    
    public func setVolume(_ volume: Float) {
        player.audio?.volume = Int32(volume * 100)
        playerVM.volume = volume
    }
    
    public func setPlaybackSpeed(_ speed: Float) {
        playerVM.playbackSpeed = speed
        player.rate = speed
    }
    
    public func setAudioTrack(_ index: Int32) {
        playerVM.selectedAudioTrack = index
        player.currentAudioTrackIndex = index
    }
    
    public func setSubtitleTrack(_ index: Int32) {
        playerVM.selectedSubtitleTrack = index
        player.currentVideoSubTitleIndex = index
    }
    
    // MARK: - VLCMediaPlayerDelegate
    
    public func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .opening:
            playerVM.isBuffering = false
            populateAudioAndSubtitles()
            
        case .buffering:
            playerVM.isBuffering = !player.isPlaying
            populateAudioAndSubtitles()
            
        case .playing:
            playerVM.isBuffering = false
            playerVM.isPlaying = true
            populateAudioAndSubtitles()
            
            if let pending = pendingResumeTime {
                performSeekIfPossible(seconds: pending)
            }
            
            if !hasDetectedVideoSize {
                let size = player.videoSize
                if size.width > 0 && size.height > 0 {
                    hasDetectedVideoSize = true
                    delegate?.engineDidDetectNativeVideoSize(size)
                }
            }
            
            let vlcVol = player.audio?.volume ?? 0
            if vlcVol > 0 {
                playerVM.volume = min(1.0, Float(vlcVol) / 100.0)
            } else {
                player.audio?.volume = Int32(playerVM.volume * 100)
            }
            
        case .paused:
            playerVM.isBuffering = false
            playerVM.isPlaying = false
            saveCurrentProgress()
            
        case .stopped, .ended, .error:
            playerVM.isPlaying = false
            playerVM.isBuffering = false
            if player.state == .ended, let key = currentMediaKey {
                PlaybackHistoryManager.shared.clearPosition(for: key)
            }
            delegate?.engineDidStop()
            
        default:
            break
        }
    }
    
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        if playerVM.isPlaying != player.isPlaying {
            playerVM.isPlaying = player.isPlaying
        }
        
        if let pending = pendingResumeTime {
            let currentMs = player.time.value?.doubleValue ?? 0.0
            let currentSec = currentMs / 1000.0
            
            if abs(currentSec - pending) < 3.0 || (currentSec >= pending && pending > 5.0) {
                pendingResumeTime = nil
                resumeAttempts = 0
            } else if resumeAttempts < 20 {
                resumeAttempts += 1
                performSeekIfPossible(seconds: pending)
            } else {
                pendingResumeTime = nil
                resumeAttempts = 0
            }
        }
        
        updateTime()
        if abs(playerVM.progress.position - player.position) > 0.001 {
            playerVM.progress.position = player.position
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateTime() {
        let currentMs = player.time.value?.doubleValue ?? 0.0
        let currentSeconds = currentMs / 1000.0
        let wholeSecond = Int(currentSeconds)
        
        if wholeSecond != lastRecordedSecond {
            lastRecordedSecond = wholeSecond
            playerVM.progress.currentTimeInSeconds = currentSeconds
            playerVM.progress.currentTime = formatSeconds(currentSeconds)
            
            if let remainingMs = player.remainingTime?.value?.doubleValue {
                let remainingSeconds = abs(remainingMs / 1000.0)
                playerVM.progress.remainingTime = "-\(formatSeconds(remainingSeconds))"
                
                if !addedTotalTime || playerVM.progress.totalDurationInSeconds == 0 {
                    let totalSeconds = currentSeconds + remainingSeconds
                    if totalSeconds > 0 {
                        playerVM.progress.totalDurationInSeconds = totalSeconds
                        playerVM.progress.totalTime = formatSeconds(totalSeconds)
                        addedTotalTime = true
                    }
                }
            }
            
            // Periodically save playback progress (every 5 seconds)
            // Never save while pendingResumeTime is active to avoid saving 0.0
            if wholeSecond % 5 == 0, pendingResumeTime == nil, let key = currentMediaKey {
                PlaybackHistoryManager.shared.savePosition(
                    for: key,
                    currentTime: currentSeconds,
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
        if !addedAudioTracks {
            var audioList: [Tracks] = []
            for (index, element) in player.audioTrackIndexes.enumerated() {
                if let name = player.audioTrackNames[index] as? String,
                   let trackIdx = element as? NSNumber {
                    audioList.append(Tracks(index: trackIdx.int32Value, name: name))
                }
            }
            if !audioList.isEmpty {
                playerVM.audioTracks = audioList
                playerVM.selectedAudioTrack = player.currentAudioTrackIndex
                addedAudioTracks = true
            }
        }
        
        if !addedSubsTracks {
            var subsList: [Tracks] = []
            for (index, element) in player.videoSubTitlesIndexes.enumerated() {
                if let name = player.videoSubTitlesNames[index] as? String,
                   let trackIdx = element as? NSNumber {
                    let idx = trackIdx.int32Value
                    let trackName = (idx == -1) ? "Off" : name
                    subsList.append(Tracks(index: idx, name: trackName))
                }
            }
            if !subsList.isEmpty {
                playerVM.subtitleTracks = subsList
                playerVM.selectedSubtitleTrack = player.currentVideoSubTitleIndex
                addedSubsTracks = true
            }
        }
    }
}

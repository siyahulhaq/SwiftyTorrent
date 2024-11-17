import SwiftUI
import UIKit

#if os(iOS)
import MobileVLCKit
#elseif os(tvOS)
import TVVLCKit
#endif

public struct VLCViewHost: UIViewControllerRepresentable {
    
    public var previewItem: PreviewItem
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }
    
    public func makeCoordinator() -> VLCViewHost.Coordinator {
        return Coordinator(previewItem: previewItem)
    }
    
    public typealias Context = UIViewControllerRepresentableContext<VLCViewHost>
    public typealias Controller = VLCPlayerViewController
    
    public func makeUIViewController(context: Context) -> Controller {
        let item = context.coordinator.previewItem
        return VLCPlayerViewController(previewItem: item)
    }
    
    public func updateUIViewController(_ uiViewController: Controller, context: Context) {}
    
    public static func dismantleUIViewController(
        _ uiViewController: Controller, coordinator: Coordinator
    ) {}
    
    public class Coordinator: NSObject {
        
        let previewItem: PreviewItem
        
        init(previewItem: PreviewItem) {
            self.previewItem = previewItem
            super.init()
        }
        
    }
}

public final class VLCPlayerViewController: UIViewController {
    
    private var previewItem: PreviewItem
    private var player: VLCMediaPlayer
    private var controlsView: UIHostingController<ControlsView>?
    private var controlsViewModel: ControlsViewModel!
    private var addedAudioTracks = false
    private var addedSubsTracks = false
    
    private var initialSwipePoint: CGPoint?
    private var initialValue: Float = 0
    private var swipeType: SwipeType = .none
    private var systemVolume: Float = 1
    
    private enum SwipeType {
        case none, volume, brightness, seek
    }
    
    
    private var controlsHidden = true {
        didSet {
            view.bringSubviewToFront(controlsView!.view)
            UIView.animate(withDuration: 0.3) {
                self.controlsView?.view.alpha = self.controlsHidden ? 0.0 : 0.75
            }
            if(!controlsHidden) {
                self.hidePlaybackControlsAfterDelay()
            }
        }
    }
    
    public init(previewItem: PreviewItem) {
        self.controlsViewModel = ControlsViewModel()
        self.previewItem = previewItem
        self.player = VLCMediaPlayer()
        super.init(nibName: nil, bundle: nil)
        print("previewItemURL: \(previewItem.previewItemURL?.absoluteString ?? "NO URL")")
        if let url = previewItem.previewItemURL {
            player.media = VLCMedia(url: url)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var addedTotalTime = false
    
    func getTotalTimeString(_ timeInMs: Double) -> String {
        let totalSeconds = timeInMs / 1000
        let hours = Int(totalSeconds / 3600)
        let minutes = Int(totalSeconds.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    func updateTime(_ player: VLCMediaPlayer) {
        self.controlsViewModel.currentTime = getTotalTimeString(player.time.value?.doubleValue ?? 0)
        self.controlsViewModel.remainingTime = "-\(getTotalTimeString(-(player.remainingTime?.value?.doubleValue ?? 0)))"
        if(!addedTotalTime) {
            let currentTime = player.time.value?.doubleValue ?? 0;
            if let remainingTime = player.remainingTime?.value?.doubleValue {
                let totalTime = currentTime + (-remainingTime)
                self.controlsViewModel.totalTime = getTotalTimeString(totalTime)
                self.addedTotalTime = true
            }
            
        }
        
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        player.delegate = self
        player.drawable = view
        player.play()
        self.controlsViewModel.isPlaying = true
        
        
        self.controlsViewModel.title = (player.videoTrackNames.first as! String?) ?? ""
        
        self.updateTime(player)
        let controlsView = ControlsView(
            controlsVM: self.controlsViewModel,
            deligate: self
        )
        
        
        let hostingController = UIHostingController(rootView: controlsView)
        self.controlsView = hostingController
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        hostingController.view.alpha = 0.0
        
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(viewDidTap(_:))))
        
        // Add pan gesture recognizer
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        view.addGestureRecognizer(panGesture)
    }
    
    func updateVolume(_ newVolume: Float) {
        player.audio?.volume = Int32(newVolume * 200) // VLC volume range is 0-200
        systemVolume = newVolume
        controlsViewModel.volume = newVolume
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let location = gesture.location(in: view)
        
        switch gesture.state {
        case .began:
            initialSwipePoint = location
            
            // Determine swipe type based on initial touch location
            let screenWidth = view.bounds.width
            if location.x < screenWidth/3 {
                swipeType = .brightness
                initialValue = Float(UIScreen.main.brightness)
            } else if location.x > 2*screenWidth/3 {
                swipeType = .volume
                initialValue = systemVolume
            } else {
                swipeType = .seek
                initialValue = player.position
            }
            
        case .changed:
            guard let initialPoint = initialSwipePoint else { return }
            
            // Calculate change ratio (-1 to 1)
            let verticalDelta = Float((initialPoint.y - location.y) / view.bounds.height)
            let horizontalDelta = Float((location.x - initialPoint.x) / view.bounds.width)
            
            switch swipeType {
            case .volume:
                let newVolume = max(0, min(1, initialValue + verticalDelta))
                self.updateVolume(newVolume)
                
            case .brightness:
                let newBrightness = max(0, min(1, initialValue + verticalDelta))
                UIScreen.main.brightness = CGFloat(newBrightness)
                
            case .seek:
                let newPosition = max(0, min(1, initialValue + horizontalDelta))
                player.position = newPosition
                controlsViewModel.position = newPosition
                
            case .none:
                break
            }
            
        case .ended, .cancelled:
            initialSwipePoint = nil
            swipeType = .none
            
        default:
            break
        }
    }
    
    
    @objc func viewDidTap(_ sender: Any) {
        controlsHidden.toggle()
    }
    
    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
    
    private var hideTimer: Timer?
    
    private func hidePlaybackControlsAfterDelay() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if self.player.isPlaying {
                self.controlsHidden = true
            }
        }
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        hideTimer?.invalidate()
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        hidePlaybackControlsAfterDelay()
    }
    
    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause:
                togglePlayback()
            case .select:
                controlsHidden.toggle()
            default: break
            }
        }
    }
}

extension VLCPlayerViewController: VLCMediaPlayerDelegate {
    
    func getFileName (_ url: URL?) -> String {
        if let url {
            return url.lastPathComponent
        } else {
            return "UNKNOWN"
        }
    }
    
    func addAudioTracks(_ player: VLCMediaPlayer) {
        let title = (player.media?.metaDictionary.values.first as! String?) ?? "UNKNOWN"
        let fileName = getFileName(player.media?.url)
        self.controlsViewModel.title = title
        self.controlsViewModel.fileName = fileName
        
        var audioTracks: [Tracks] = [];
        
        for (index, element) in player.audioTrackIndexes.enumerated() {
            let name = player.audioTrackNames[index] as! String?
            let audioIndex = element as! NSNumber?
            audioTracks.append(Tracks(index: Int32(truncating: audioIndex ?? -1), name: name ?? "UNKNOWN"))
        }
        self.controlsViewModel.audioTracks = audioTracks
        self.controlsViewModel.selectedAudioTrack = player.currentAudioTrackIndex
        addedAudioTracks = true
    }
    
    func addSubtitleTracks(_ player: VLCMediaPlayer) {
        var subtitleTracks: [Tracks] = [];
        
        for (index, element) in player.videoSubTitlesIndexes.enumerated() {
            let name = player.videoSubTitlesNames[index] as! String?
            let subIndex = element as! NSNumber?
            let subIndexInt = Int32(truncating: subIndex ?? -1)
            let subTitle = subIndexInt == -1 ? "Off" : name ?? "UNKNOWN"
            subtitleTracks.append(Tracks(index: subIndexInt, name: subTitle))
        }
        self.controlsViewModel.subtitleTracks = subtitleTracks
        self.controlsViewModel.selectedSubtitleTrack = player.currentVideoSubTitleIndex
        addedSubsTracks = true
    }
    
    public func mediaPlayerStateChanged(_ aNotification: Notification) {
        print("mediaPlayerStateChanged")
        print("\(aNotification.name)")
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        
        let stateNames = [
            VLCMediaPlayerState.paused: "Paused",
            VLCMediaPlayerState.stopped: "Stopped",
            VLCMediaPlayerState.buffering: "Buffering",
            VLCMediaPlayerState.ended: "Ended",
            VLCMediaPlayerState.error: "Error",
            VLCMediaPlayerState.opening: "Opening",
            VLCMediaPlayerState.playing: "Playing",
            VLCMediaPlayerState.esAdded: "ES Added",
        ]
        
        print("state: \(stateNames[player.state] ?? "Unknown")")
        
        
        switch player.state {
        case .stopped:
            self.controlsViewModel.isPlaying = false
            self.dismiss(animated: true, completion: nil)
            break
        case .opening:
            
            break
        case .buffering:
            if(!addedAudioTracks) {
                addAudioTracks(player)
            }
            if(!addedSubsTracks) {
                addSubtitleTracks(player)
            }
            break;
        case .ended:
            self.controlsViewModel.isPlaying = false
            self.dismiss(animated: true, completion: nil)
            break
        case .error:
            self.controlsViewModel.isPlaying = false
            self.dismiss(animated: true, completion: nil)
            break
        case .playing:
            self.controlsViewModel.isPlaying = true
            break
        case .paused:
            self.controlsViewModel.isPlaying = false
            break
        case .esAdded: break
        default: break
        }
    }
    
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        let position = player.position
        self.updateTime(player)
        updateProgress(position)
    }
    
    private func updateProgress(_ value: Float) {
        self.controlsViewModel.position = value
    }
    
}

extension VLCPlayerViewController: PlayerControlsProtocol {
    func onTogglePlayPause() {
        self.togglePlayback()
    }
    
    func onBackward() { self.player.jumpBackward(10) }
    
    func onForward() { self.player.jumpForward(10) }
    
    func onSliderChange(_ position: Float) {
        self.player.position = position
    }
    
    func changeVolume(_ value: Float) {
        self.updateVolume(value)
    }
    
    func onStop() {
        self.player.stop()
    }
    
    func onClose() {
        self.player.stop()
        self.dismiss(animated: true, completion: nil)
    }
    
    func onAudioTrackSelected(_ index: Int32) {
        self.player.currentAudioTrackIndex = index
        self.controlsViewModel.selectedAudioTrack = index
    }
    
    func onSubtitleTrackSelected(_ index: Int32) {
        self.player.currentVideoSubTitleIndex = index
        self.controlsViewModel.selectedSubtitleTrack = index
    }
}

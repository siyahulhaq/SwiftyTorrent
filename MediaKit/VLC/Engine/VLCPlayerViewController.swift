import SwiftUI
import UIKit

#if os(iOS)
import MobileVLCKit
#elseif os(tvOS)
import TVVLCKit
#endif

// MARK: - Haptics

enum MediaHaptics {
    #if os(iOS)
    private static let lightGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        return gen
    }()
    
    private static let mediumGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        return gen
    }()
    
    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        return gen
    }()
    
    static func light() {
        lightGenerator.impactOccurred()
    }
    
    static func medium() {
        mediumGenerator.impactOccurred()
    }
    
    static func selection() {
        selectionGenerator.selectionChanged()
    }
    #else
    static func light() {}
    static func medium() {}
    static func selection() {}
    #endif
}

// MARK: - SwiftUI Host

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
    ) {
        uiViewController.stopAndCleanup()
    }
    
    public class Coordinator: NSObject {
        let previewItem: PreviewItem
        
        init(previewItem: PreviewItem) {
            self.previewItem = previewItem
            super.init()
        }
    }
}

// MARK: - VLCPlayerViewController

public final class VLCPlayerViewController: UIViewController {
    
    private let playerVM: PlayerViewModel
    private let engine: VLCPlaybackEngine
    private let videoContainerView: VLCVideoContainerView
    
    private var controlsHostingController: UIHostingController<ControlsView>?
    private var nativeVideoSize: CGSize = .zero
    
    // Gestures & HUD State
    private var initialSwipePoint: CGPoint?
    private var initialValue: Float = 0
    private var initialSeekPosition: Float = 0
    private var swipeType: SwipeType = .none
    private var hudDismissTimer: Timer?
    private var rippleDismissTimer: Timer?
    private var hideTimer: Timer?
    
    private var currentItemKey: String?
    
    private enum SwipeType {
        case none, volume, brightness, seek
    }
    
    public init(previewItem: PreviewItem) {
        self.playerVM = PlayerViewModel()
        self.engine = VLCPlaybackEngine(playerVM: self.playerVM)
        self.videoContainerView = VLCVideoContainerView(frame: .zero)
        
        let key = PlaybackHistoryManager.shared.key(for: previewItem.previewItemURL, title: previewItem.previewItemTitle)
        self.currentItemKey = key
        
        super.init(nibName: nil, bundle: nil)
        
        self.engine.delegate = self
        self.engine.load(url: previewItem.previewItemURL, title: previewItem.previewItemTitle)
        
        if let key = key, let record = PlaybackHistoryManager.shared.getRecord(for: key) {
            if record.savedTime >= 5.0 && (record.totalDuration <= 0 || record.savedTime < (record.totalDuration - 15.0)) {
                playerVM.resumeTime = record.savedTime
                playerVM.resumeTimeString = formatSeconds(record.savedTime)
                playerVM.showResumePrompt = true
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopAndCleanup()
    }
    
    public func stopAndCleanup() {
        hideTimer?.invalidate()
        hudDismissTimer?.invalidate()
        rippleDismissTimer?.invalidate()
        engine.cleanup()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupVideoContainerView()
        setupControlsView()
        setupGestureRecognizers()
        
        engine.player.drawable = videoContainerView
        
        if !playerVM.showResumePrompt {
            engine.play()
        }
        
        #if os(iOS)
        playerVM.brightness = Float(UIScreen.main.brightness)
        #endif
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hidePlaybackControlsAfterDelay()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoContainerView.applyAspectRatio(playerVM.aspectRatio, nativeVideoSize: nativeVideoSize, in: view.bounds, animated: false)
    }
    
    public override var prefersHomeIndicatorAutoHidden: Bool {
        return !playerVM.isControlsVisible
    }
    
    public override var prefersStatusBarHidden: Bool {
        return !playerVM.isControlsVisible
    }
    
    // MARK: - Setup
    
    private func setupVideoContainerView() {
        view.addSubview(videoContainerView)
        videoContainerView.frame = view.bounds
    }
    
    private func setupControlsView() {
        let controlsView = ControlsView(
            playerVM: playerVM,
            delegate: self
        )
        
        let hostingController = UIHostingController(rootView: controlsView)
        hostingController.view.backgroundColor = .clear
        self.controlsHostingController = hostingController
        
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
    }
    
    private func setupGestureRecognizers() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Visibility & Auto-hide
    
    private func hidePlaybackControlsAfterDelay() {
        hideTimer?.invalidate()
        guard !playerVM.isLocked else { return }
        
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.engine.player.isPlaying && self.playerVM.isControlsVisible {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.playerVM.isControlsVisible = false
                }
                self.setNeedsStatusBarAppearanceUpdate()
                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            }
        }
    }
    
    // MARK: - Gestures
    
    private func triggerDoubleTapSeek(seconds: Int, isForward: Bool) {
        MediaHaptics.light()
        
        if isForward {
            engine.jumpForward(seconds: Int32(seconds))
            playerVM.doubleTapRipple = .right(seconds: seconds)
        } else {
            engine.jumpBackward(seconds: Int32(abs(seconds)))
            playerVM.doubleTapRipple = .left(seconds: abs(seconds))
        }
        
        rippleDismissTimer?.invalidate()
        rippleDismissTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            withAnimation(.easeOut(duration: 0.2)) {
                self?.playerVM.doubleTapRipple = nil
            }
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        guard !playerVM.isLocked else { return }
        
        let translation = gesture.translation(in: view)
        let location = gesture.location(in: view)
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        switch gesture.state {
        case .began:
            initialSwipePoint = location
            swipeType = .none
            initialSeekPosition = engine.player.position
            #if os(iOS)
            initialValue = Float(UIScreen.main.brightness)
            #else
            initialValue = 0.5
            #endif
            hideTimer?.invalidate()
            
        case .changed:
            guard let initialPoint = initialSwipePoint else { return }
            
            if swipeType == .none {
                let dx = abs(translation.x)
                let dy = abs(translation.y)
                
                if dx > 8 || dy > 8 {
                    if dx > dy {
                        swipeType = .seek
                    } else {
                        if initialPoint.x < screenWidth * 0.5 {
                            swipeType = .brightness
                            #if os(iOS)
                            initialValue = Float(UIScreen.main.brightness)
                            #else
                            initialValue = 0.5
                            #endif
                        } else {
                            swipeType = .volume
                            initialValue = playerVM.volume
                        }
                    }
                }
            }
            
            switch swipeType {
            case .seek:
                let horizontalDelta = Float(translation.x / (screenWidth * 0.65))
                let totalDuration = playerVM.progress.totalDurationInSeconds > 0 ? playerVM.progress.totalDurationInSeconds : 100.0
                let maxSweepSeconds = min(600.0, max(60.0, totalDuration * 0.5))
                let deltaSeconds = Double(horizontalDelta) * maxSweepSeconds
                let currentSeconds = Double(initialSeekPosition) * totalDuration
                let targetSeconds = max(0.0, min(totalDuration, currentSeconds + deltaSeconds))
                
                let targetTimeStr = formatSeconds(targetSeconds)
                let totalTimeStr = playerVM.progress.totalTime
                let isForward = deltaSeconds >= 0
                
                showHUD(.seek(
                    delta: deltaSeconds,
                    targetTime: targetTimeStr,
                    totalTime: totalTimeStr,
                    isForward: isForward
                ))
                
            case .brightness:
                let verticalDelta = Float(-translation.y / (screenHeight * 0.6))
                let newBrightness = max(0.0, min(1.0, initialValue + verticalDelta))
                #if os(iOS)
                UIScreen.main.brightness = CGFloat(newBrightness)
                #endif
                playerVM.brightness = newBrightness
                showHUD(.brightness(newBrightness))
                
            case .volume:
                let verticalDelta = Float(-translation.y / (screenHeight * 0.6))
                let newVolume = max(0.0, min(1.0, initialValue + verticalDelta))
                engine.setVolume(newVolume)
                showHUD(.volume(newVolume))
                
            case .none:
                break
            }
            
        case .ended, .cancelled:
            if swipeType == .seek, let _ = initialSwipePoint {
                let horizontalDelta = Float(translation.x / (screenWidth * 0.65))
                let totalDuration = playerVM.progress.totalDurationInSeconds > 0 ? playerVM.progress.totalDurationInSeconds : 100.0
                let maxSweepSeconds = min(600.0, max(60.0, totalDuration * 0.5))
                let deltaSeconds = Double(horizontalDelta) * maxSweepSeconds
                let currentSeconds = Double(initialSeekPosition) * totalDuration
                let targetSeconds = max(0.0, min(totalDuration, currentSeconds + deltaSeconds))
                
                let targetPosition = Float(targetSeconds / totalDuration)
                engine.seekTo(position: targetPosition)
                
                MediaHaptics.light()
            }
            
            initialSwipePoint = nil
            swipeType = .none
            scheduleHUDDismiss()
            
            if playerVM.isControlsVisible && engine.player.isPlaying {
                hidePlaybackControlsAfterDelay()
            }
            
        default:
            break
        }
    }
    
    private func showHUD(_ hud: HUDState) {
        hudDismissTimer?.invalidate()
        playerVM.activeHUD = hud
    }
    
    private func scheduleHUDDismiss() {
        hudDismissTimer?.invalidate()
        hudDismissTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            withAnimation(.easeOut(duration: 0.2)) {
                self?.playerVM.activeHUD = nil
            }
        }
    }
    
    private func togglePlayback() {
        MediaHaptics.medium()
        
        if engine.player.isPlaying {
            engine.pause()
            hideTimer?.invalidate()
        } else {
            engine.play()
            hidePlaybackControlsAfterDelay()
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
}

// MARK: - UIGestureRecognizerDelegate

extension VLCPlayerViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - VLCPlaybackEngineDelegate

extension VLCPlayerViewController: VLCPlaybackEngineDelegate {
    public func engineDidDetectNativeVideoSize(_ size: CGSize) {
        nativeVideoSize = size
        videoContainerView.applyAspectRatio(playerVM.aspectRatio, nativeVideoSize: nativeVideoSize, in: view.bounds, animated: true)
    }
    
    public func engineDidStop() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - PlayerControlsProtocol Implementation

extension VLCPlayerViewController: PlayerControlsProtocol {
    
    public func onScreenTapped() {
        if playerVM.isLocked {
            withAnimation(.easeInOut(duration: 0.25)) {
                playerVM.isControlsVisible.toggle()
            }
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            playerVM.isControlsVisible.toggle()
        }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        
        if playerVM.isControlsVisible && engine.player.isPlaying {
            hidePlaybackControlsAfterDelay()
        } else {
            hideTimer?.invalidate()
        }
    }
    
    public func onDoubleTapped(at location: CGPoint, screenWidth: CGFloat) {
        guard !playerVM.isLocked else { return }
        if location.x < screenWidth * 0.35 {
            triggerDoubleTapSeek(seconds: -10, isForward: false)
        } else if location.x > screenWidth * 0.65 {
            triggerDoubleTapSeek(seconds: 10, isForward: true)
        } else {
            togglePlayback()
        }
    }
    
    public func onTogglePlayPause() {
        togglePlayback()
    }
    
    public func seekBy(seconds: Double) {
        if seconds > 0 {
            engine.jumpForward(seconds: Int32(seconds))
        } else {
            engine.jumpBackward(seconds: Int32(abs(seconds)))
        }
    }
    
    public func toggleLock() {
        playerVM.isLocked.toggle()
        MediaHaptics.medium()
        if playerVM.isLocked {
            withAnimation(.easeInOut(duration: 0.25)) {
                playerVM.isControlsVisible = true
            }
            hideTimer?.invalidate()
        } else {
            hidePlaybackControlsAfterDelay()
        }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
    
    public func onBackward() {
        triggerDoubleTapSeek(seconds: -10, isForward: false)
    }
    
    public func onForward() {
        triggerDoubleTapSeek(seconds: 10, isForward: true)
    }
    
    public func onSliderChange(_ position: Float) {
        engine.seekTo(position: position)
    }
    
    public func changeVolume(_ value: Float) {
        engine.setVolume(value)
    }
    
    public func changeBrightness(_ value: Float) {
        #if os(iOS)
        UIScreen.main.brightness = CGFloat(value)
        #endif
        playerVM.brightness = value
    }
    
    public func changePlaybackSpeed(_ speed: Float) {
        MediaHaptics.selection()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.engine.setPlaybackSpeed(speed)
        }
    }
    
    public func changeAspectRatio(_ ratio: VideoAspectRatio) {
        playerVM.aspectRatio = ratio
        MediaHaptics.selection()
        videoContainerView.applyAspectRatio(ratio, nativeVideoSize: nativeVideoSize, in: view.bounds, animated: true)
    }
    
    public func onStop() {
        engine.stop()
    }
    
    public func onClose() {
        stopAndCleanup()
        dismiss(animated: true, completion: nil)
    }
    
    public func onAudioTrackSelected(_ index: Int32) {
        MediaHaptics.selection()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.engine.setAudioTrack(index)
        }
    }
    
    public func onSubtitleTrackSelected(_ index: Int32) {
        MediaHaptics.selection()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.engine.setSubtitleTrack(index)
        }
    }
    
    public func onResumePlayback(at seconds: Double) {
        playerVM.showResumePrompt = false
        engine.player.media?.addOption(":start-time=\(Int(seconds))")
        engine.seekTo(seconds: seconds)
        engine.play()
        hidePlaybackControlsAfterDelay()
    }
    
    public func onStartOver() {
        playerVM.showResumePrompt = false
        if let key = currentItemKey {
            PlaybackHistoryManager.shared.clearPosition(for: key)
        }
        engine.pendingResumeTime = nil
        engine.player.media?.addOption(":start-time=0")
        engine.seekTo(position: 0)
        engine.play()
        hidePlaybackControlsAfterDelay()
    }
}

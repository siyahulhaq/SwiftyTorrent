import SwiftUI
import UIKit
import AVFoundation
#if os(iOS)
import MediaPlayer
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

public struct MediaPlayerViewHost: UIViewControllerRepresentable {
    public var previewItem: PreviewItem
    
    public init(previewItem: PreviewItem) {
        self.previewItem = previewItem
    }
    
    public func makeUIViewController(context: Context) -> MediaPlayerViewController {
        return MediaPlayerViewController(previewItem: previewItem)
    }
    
    public func updateUIViewController(_ uiViewController: MediaPlayerViewController, context: Context) {}
    
    public static func dismantleUIViewController(
        _ uiViewController: MediaPlayerViewController, coordinator: ()
    ) {
        uiViewController.stopAndCleanup()
    }
}

public typealias VLCViewHost = MediaPlayerViewHost

// MARK: - MediaPlayerViewController

public final class MediaPlayerViewController: UIViewController {
    
    private let playerVM: PlayerViewModel
    private let engine: KSPlaybackEngine
    private let videoContainerView: KSVideoContainerView
    
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
    
    #if os(iOS)
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var volumeObserver: NSKeyValueObservation?
    #endif
    
    private enum SwipeType {
        case none, volume, brightness, seek
    }
    
    public init(previewItem: PreviewItem) {
        print("[MediaPlayerViewController] Initializing with item: '\(previewItem.previewItemTitle ?? "nil")', URL: \(previewItem.previewItemURL?.absoluteString ?? "nil")")
        self.playerVM = PlayerViewModel()
        self.engine = KSPlaybackEngine(playerVM: self.playerVM)
        self.videoContainerView = KSVideoContainerView(frame: .zero)
        
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
        #if os(iOS)
        volumeObserver?.invalidate()
        volumeObserver = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeSlider = nil
        #endif
        engine.cleanup()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupVideoContainerView()
        setupControlsView()
        setupGestureRecognizers()
        
        videoContainerView.attach(playerView: engine.playerView)
        
        if !playerVM.showResumePrompt {
            engine.play()
        }
        
        #if os(iOS)
        playerVM.brightness = Float(UIScreen.main.brightness)
        
        let systemVol = AVAudioSession.sharedInstance().outputVolume
        playerVM.volume = systemVol
        engine.setVolume(systemVol, isHardwareControlled: true)
        print("[MediaPlayerViewController] Initialized with system outputVolume: \(systemVol)")
        
        let volView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volView.clipsToBounds = true
        volView.alpha = 0.001
        view.addSubview(volView)
        self.volumeView = volView
        
        if let slider = volView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            self.volumeSlider = slider
        }
        
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let newVol = session.outputVolume
                if abs(self.playerVM.volume - newVol) > 0.01 {
                    self.playerVM.volume = newVol
                    self.engine.setVolume(newVol, isHardwareControlled: true)
                    self.showHUD(.volume(newVol))
                }
            }
        }
        #endif
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hidePlaybackControlsAfterDelay()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if os(iOS)
        if volumeSlider == nil, let volView = volumeView {
            if let slider = volView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                self.volumeSlider = slider
            }
        }
        #endif
        guard view.bounds.width > 0 && view.bounds.height > 0 else { return }
        videoContainerView.applyAspectRatio(playerVM.aspectRatio, nativeVideoSize: nativeVideoSize, in: view.bounds, animated: false)
    }
    
    #if os(iOS)
    public override var prefersHomeIndicatorAutoHidden: Bool {
        return !playerVM.isControlsVisible
    }
    
    public override var prefersStatusBarHidden: Bool {
        return !playerVM.isControlsVisible
    }
    #endif
    
    private func updateSystemUIVisibility() {
        #if os(iOS)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        #endif
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
        #if os(iOS)
        panGesture.maximumNumberOfTouches = 1
        #endif
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Visibility & Auto-hide
    
    private func hidePlaybackControlsAfterDelay() {
        hideTimer?.invalidate()
        guard !playerVM.isLocked else { return }
        
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.engine.isPlaying && self.playerVM.isControlsVisible {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.playerVM.isControlsVisible = false
                }
                self.updateSystemUIVisibility()
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
            initialSeekPosition = engine.position
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
                #if os(iOS)
                if let slider = volumeSlider {
                    if abs(slider.value - newVolume) > 0.01 {
                        slider.value = newVolume
                    }
                    engine.setVolume(newVolume, isHardwareControlled: true)
                } else {
                    engine.setVolume(newVolume, isHardwareControlled: false)
                }
                #else
                engine.setVolume(newVolume, isHardwareControlled: false)
                #endif
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
            
            if playerVM.isControlsVisible && engine.isPlaying {
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
        
        if engine.isPlaying {
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

extension MediaPlayerViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - KSPlaybackEngineDelegate

extension MediaPlayerViewController: KSPlaybackEngineDelegate {
    func engineDidDetectNativeVideoSize(_ size: CGSize) {
        print("[MediaPlayerViewController] engineDidDetectNativeVideoSize: \(size)")
        nativeVideoSize = size
        guard view.bounds.width > 0 && view.bounds.height > 0 else { return }
        videoContainerView.applyAspectRatio(playerVM.aspectRatio, nativeVideoSize: size, in: view.bounds, animated: true)
    }
    
    func engineDidStop() {
        // Do not auto-dismiss on transient stopped/probing states.
        // Dismissal is handled via user action (onClose).
    }
}

// MARK: - PlayerControlsProtocol Implementation

extension MediaPlayerViewController: PlayerControlsProtocol {
    
    public func onScreenTapped() {
        if playerVM.isLocked {
            withAnimation(.easeInOut(duration: 0.25)) {
                playerVM.isControlsVisible.toggle()
            }
            updateSystemUIVisibility()
            return
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            playerVM.isControlsVisible.toggle()
        }
        updateSystemUIVisibility()
        
        if playerVM.isControlsVisible && engine.isPlaying {
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
        updateSystemUIVisibility()
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
        let clamped = max(0.0, min(1.0, value))
        #if os(iOS)
        if let slider = volumeSlider {
            if abs(slider.value - clamped) > 0.01 {
                slider.value = clamped
            }
            engine.setVolume(clamped, isHardwareControlled: true)
        } else {
            engine.setVolume(clamped, isHardwareControlled: false)
        }
        #else
        engine.setVolume(clamped, isHardwareControlled: false)
        #endif
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
        engine.seekTo(position: 0)
        engine.play()
        hidePlaybackControlsAfterDelay()
    }
}

public typealias VLCPlayerViewController = MediaPlayerViewController

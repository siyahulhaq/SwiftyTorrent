import SwiftUI

public struct ControlsView: View {
    @ObservedObject var playerVM: PlayerViewModel
    public let delegate: PlayerControlsProtocol
    
    public init(playerVM: PlayerViewModel, delegate: PlayerControlsProtocol) {
        self.playerVM = playerVM
        self.delegate = delegate
    }
    
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Background tap & double-tap receiver across the entire screen
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        delegate.onDoubleTapped(at: location, screenWidth: proxy.size.width)
                    }
                    .onTapGesture(count: 1) {
                        delegate.onScreenTapped()
                    }
                
                if playerVM.isLocked {
                    lockedOverlay
                        .opacity(playerVM.isControlsVisible ? 1.0 : 0.0)
                        .allowsHitTesting(playerVM.isControlsVisible)
                } else {
                    VStack(spacing: 0) {
                        PlayerTopBarView(playerVM: playerVM, delegate: delegate)
                        
                        Spacer()
                        
                        PlayerCenterControlsView(playerVM: playerVM, delegate: delegate)
                        
                        Spacer()
                        
                        PlayerBottomContainerView(playerVM: playerVM, delegate: delegate)
                    }
                    .opacity(playerVM.isControlsVisible ? 1.0 : 0.0)
                    .allowsHitTesting(playerVM.isControlsVisible)
                }
                
                // OSD HUDs (Brightness / Volume / Scrub preview)
                PlayerHUDView(playerVM: playerVM)
                
                // Double Tap Seek Ripple feedback
                PlayerRippleView(playerVM: playerVM)
            }
        }
        .ignoresSafeArea(.all)
        .animation(.easeInOut(duration: 0.25), value: playerVM.isControlsVisible)
        .animation(.easeInOut(duration: 0.25), value: playerVM.isLocked)
        .alert("Resume Playback", isPresented: $playerVM.showResumePrompt) {
            Button("Resume (\(playerVM.resumeTimeString))") {
                delegate.onResumePlayback(at: playerVM.resumeTime)
            }
            Button("Start from Beginning", role: .cancel) {
                delegate.onStartOver()
            }
        } message: {
            Text("Would you like to continue watching from where you left off?")
        }
    }
    
    // MARK: - Locked Overlay
    
    private var lockedOverlay: some View {
        VStack {
            HStack {
                Button(action: {
                    MediaHaptics.medium()
                    delegate.toggleLock()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Locked • Tap to Unlock")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.65))
                            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    )
                }
                .padding(.leading, 24)
                .padding(.top, 50)
                
                Spacer()
            }
            
            Spacer()
        }
    }
}

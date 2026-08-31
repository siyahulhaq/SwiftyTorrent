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
                // 1. Full-screen gesture receiver across physical screen
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea(.all)
                    .onTapGesture(count: 2) { location in
                        delegate.onDoubleTapped(at: location, screenWidth: proxy.size.width)
                    }
                    .onTapGesture(count: 1) {
                        delegate.onScreenTapped()
                    }
                
                // 2. Active Controls with Edge-to-Edge gradient backdrops
                if playerVM.isLocked {
                    lockedOverlay(proxy: proxy)
                        .opacity(playerVM.isControlsVisible ? 1.0 : 0.0)
                        .allowsHitTesting(playerVM.isControlsVisible)
                } else {
                    VStack(spacing: 0) {
                        // Top Bar with full-bleed gradient backdrop extending past safe area
                        PlayerTopBarView(playerVM: playerVM, delegate: delegate)
                            .padding(.top, proxy.safeAreaInsets.top > 0 ? proxy.safeAreaInsets.top : 12)
                            .padding(.leading, proxy.safeAreaInsets.leading)
                            .padding(.trailing, proxy.safeAreaInsets.trailing)
                            .background(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.4), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .ignoresSafeArea(edges: .top)
                                .allowsHitTesting(false)
                            )
                        
                        Spacer()
                        
                        // Center controls padded from landscape side cutouts
                        PlayerCenterControlsView(playerVM: playerVM, delegate: delegate)
                            .padding(.leading, proxy.safeAreaInsets.leading)
                            .padding(.trailing, proxy.safeAreaInsets.trailing)
                        
                        Spacer()
                        
                        // Bottom Toolbar with full-bleed gradient backdrop extending past safe area
                        PlayerBottomContainerView(playerVM: playerVM, delegate: delegate)
                            .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? proxy.safeAreaInsets.bottom : 12)
                            .padding(.leading, proxy.safeAreaInsets.leading)
                            .padding(.trailing, proxy.safeAreaInsets.trailing)
                            .background(
                                LinearGradient(
                                    colors: [Color.clear, Color.black.opacity(0.4), Color.black.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                            )
                    }
                    .opacity(playerVM.isControlsVisible ? 1.0 : 0.0)
                    .allowsHitTesting(playerVM.isControlsVisible)
                }
                
                // 3. OSD HUDs (Brightness / Volume / Scrub preview)
                PlayerHUDView(playerVM: playerVM)
                    .padding(.top, proxy.safeAreaInsets.top)
                    .padding(.bottom, proxy.safeAreaInsets.bottom)
                    .padding(.leading, proxy.safeAreaInsets.leading)
                    .padding(.trailing, proxy.safeAreaInsets.trailing)
                
                // 4. Double Tap Seek Ripple feedback
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
    
    private func lockedOverlay(proxy: GeometryProxy) -> some View {
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
                .padding(.leading, max(16, proxy.safeAreaInsets.leading + 16))
                .padding(.top, max(12, proxy.safeAreaInsets.top + 8))
                
                Spacer()
            }
            
            Spacer()
        }
    }
}

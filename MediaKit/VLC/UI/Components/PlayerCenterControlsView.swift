import SwiftUI

// MARK: - Isolated Center Controls View

public struct PlayerCenterControlsView: View {
    @ObservedObject var playerVM: PlayerViewModel
    public let delegate: PlayerControlsProtocol
    
    public init(playerVM: PlayerViewModel, delegate: PlayerControlsProtocol) {
        self.playerVM = playerVM
        self.delegate = delegate
    }
    
    public var body: some View {
        HStack(spacing: 36) {
            // Jump Backward 10s
            Button(action: {
                delegate.onBackward()
            }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                    )
            }
            
            // Primary Play / Pause Button
            Button(action: {
                delegate.onTogglePlayPause()
            }) {
                ZStack {
                    if playerVM.isBuffering {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.6)
                    } else {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: playerVM.isPlaying ? 0 : 2)
                    }
                }
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
                )
            }
            .scaleEffect(playerVM.isPlaying ? 1.0 : 1.05)
            
            // Jump Forward 10s
            Button(action: {
                delegate.onForward()
            }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                    )
            }
        }
    }
}

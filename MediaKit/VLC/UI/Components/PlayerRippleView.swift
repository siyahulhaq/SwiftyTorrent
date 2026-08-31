import SwiftUI

public struct PlayerRippleView: View {
    @ObservedObject var playerVM: PlayerViewModel
    
    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }
    
    public var body: some View {
        if let ripple = playerVM.doubleTapRipple {
            switch ripple {
            case .left(let seconds):
                HStack {
                    VStack(spacing: 6) {
                        Image(systemName: "gobackward.\(seconds)")
                            .font(.system(size: 34, weight: .bold))
                        Text("-\(seconds)s")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(24)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    )
                    .padding(.leading, 60)
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                
            case .right(let seconds):
                HStack {
                    Spacer()
                    
                    VStack(spacing: 6) {
                        Image(systemName: "goforward.\(seconds)")
                            .font(.system(size: 34, weight: .bold))
                        Text("+\(seconds)s")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(24)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
                    )
                    .padding(.trailing, 60)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
    }
}

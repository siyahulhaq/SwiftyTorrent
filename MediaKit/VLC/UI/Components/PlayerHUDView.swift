import SwiftUI

public struct PlayerHUDView: View {
    @ObservedObject var playerVM: PlayerViewModel
    
    public init(playerVM: PlayerViewModel) {
        self.playerVM = playerVM
    }
    
    public var body: some View {
        if let hud = playerVM.activeHUD {
            switch hud {
            case .brightness(let value):
                HStack {
                    verticalLevelPill(
                        icon: "sun.max.fill",
                        value: value,
                        text: "\(Int(value * 100))%"
                    )
                    .padding(.leading, 32)
                    
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .volume(let value):
                HStack {
                    Spacer()
                    
                    verticalLevelPill(
                        icon: volumeIcon(for: value),
                        value: value,
                        text: "\(Int(value * 100))%"
                    )
                    .padding(.trailing, 32)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
            case .seek(let delta, let targetTime, let totalTime, let isForward):
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: isForward ? "goforward" : "gobackward")
                            .font(.system(size: 20, weight: .bold))
                        
                        Text(String(format: "%@%02d:%02d", isForward ? "+" : "-", abs(Int(delta)) / 60, abs(Int(delta)) % 60))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.blue)
                    
                    Text("\(targetTime) / \(totalTime)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }
    
    private func verticalLevelPill(icon: String, value: Float, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            GeometryReader { geo in
                let height = geo.size.height
                let clamped = CGFloat(max(0.0, min(1.0, value)))
                
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                    
                    Capsule()
                        .fill(Color.white)
                        .frame(height: clamped * height)
                }
            }
            .frame(width: 5, height: 110)
            
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
    }
    
    private func volumeIcon(for vol: Float) -> String {
        if vol <= 0.001 {
            return "speaker.slash.fill"
        } else if vol < 0.33 {
            return "speaker.wave.1.fill"
        } else if vol < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

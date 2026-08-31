import SwiftUI

// MARK: - Isolated Top Bar View (Does NOT observe playback progress ticks)

public struct PlayerTopBarView: View {
    @ObservedObject var playerVM: PlayerViewModel
    public let delegate: PlayerControlsProtocol
    private let availableSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    public init(playerVM: PlayerViewModel, delegate: PlayerControlsProtocol) {
        self.playerVM = playerVM
        self.delegate = delegate
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // Dismiss / Close Button
                Button(action: {
                    MediaHaptics.light()
                    delegate.onClose()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                        )
                }
                
                // Title and Subtitle Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if !playerVM.fileName.isEmpty && playerVM.fileName != playerVM.title {
                        Text(playerVM.fileName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer()
                
                // Speed Selector Menu
                Menu {
                    ForEach(availableSpeeds, id: \.self) { speed in
                        Button(action: {
                            delegate.changePlaybackSpeed(speed)
                        }) {
                            if abs(playerVM.playbackSpeed - speed) < 0.01 {
                                Label(String(format: "%.2fx", speed), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%.2fx", speed))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: "%.2gx", playerVM.playbackSpeed))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                    )
                }
                
                // Aspect Ratio Selector Menu
                Menu {
                    ForEach(VideoAspectRatio.allCases) { ratio in
                        Button(action: {
                            delegate.changeAspectRatio(ratio)
                        }) {
                            if playerVM.aspectRatio == ratio {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(ratio.rawValue)
                                        Text(ratio.subtitle)
                                    }
                                } icon: {
                                    Image(systemName: "checkmark")
                                }
                            } else {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(ratio.rawValue)
                                        Text(ratio.subtitle)
                                    }
                                } icon: {
                                    Image(systemName: ratio.iconName)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: playerVM.aspectRatio.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                        )
                }
                
                // Lock Screen Button
                Button(action: {
                    delegate.toggleLock()
                }) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 44)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.9), Color.black.opacity(0.45), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        )
    }
    
    private var displayTitle: String {
        if !playerVM.title.isEmpty && playerVM.title != "UNKNOWN" {
            return playerVM.title
        }
        if !playerVM.fileName.isEmpty && playerVM.fileName != "UNKNOWN" {
            return playerVM.fileName
        }
        return "Video Player"
    }
}

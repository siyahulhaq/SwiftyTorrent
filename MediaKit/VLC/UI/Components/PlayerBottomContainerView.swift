import SwiftUI

// MARK: - Bottom Container View

public struct PlayerBottomContainerView: View {
    @ObservedObject var playerVM: PlayerViewModel
    public let delegate: PlayerControlsProtocol
    
    public init(playerVM: PlayerViewModel, delegate: PlayerControlsProtocol) {
        self.playerVM = playerVM
        self.delegate = delegate
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Only this child view redraws on high-frequency timeline ticks
            PlayerTimelineView(progress: playerVM.progress, delegate: delegate)
            
            // Subtitle, Audio, Volume Toolbar (does NOT re-render on ticks)
            PlayerBottomToolbarView(playerVM: playerVM, delegate: delegate)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Isolated Timeline View (Only this view updates when video time ticks)

struct PlayerTimelineView: View {
    @ObservedObject var progress: PlaybackProgressModel
    let delegate: PlayerControlsProtocol
    
    @State private var isTotalTime: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubPosition: Float = 0.0
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let currentPos = isScrubbing ? scrubPosition : progress.position
                let clampedPos = max(0.0, min(1.0, currentPos))
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: isScrubbing ? 8 : 5)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.8), Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: CGFloat(clampedPos) * width, height: isScrubbing ? 8 : 5)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 18 : 12, height: isScrubbing ? 18 : 12)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .offset(x: max(0, CGFloat(clampedPos) * width - (isScrubbing ? 9 : 6)))
                }
                .contentShape(Rectangle())
                #if os(iOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let newPos = Float(max(0.0, min(1.0, value.location.x / width)))
                            scrubPosition = newPos
                            progress.position = newPos
                            // Do NOT call delegate.onSliderChange here — each drag event triggers
                            // a full FFmpeg av_seek_frame, causing the video to freeze until
                            // buffering completes. Only commit the seek when the user lifts their finger.
                        }
                        .onEnded { value in
                            let newPos = Float(max(0.0, min(1.0, value.location.x / width)))
                            scrubPosition = newPos
                            progress.position = newPos
                            delegate.onSliderChange(newPos)
                            isScrubbing = false
                        }
                )
                #endif
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isScrubbing)
            }
            .frame(height: 24)
            .padding(.horizontal, 20)
            
            HStack {
                Text(progress.currentTime)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text(isTotalTime ? progress.totalTime : progress.remainingTime)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .onTapGesture {
                        MediaHaptics.selection()
                        isTotalTime.toggle()
                    }
            }
            .padding(.horizontal, 22)
        }
    }
}

// MARK: - Isolated Bottom Toolbar (Subtitles, Audio, Volume - does NOT observe timeline progress)

struct PlayerBottomToolbarView: View {
    @ObservedObject var playerVM: PlayerViewModel
    let delegate: PlayerControlsProtocol
    
    var body: some View {
        HStack(spacing: 16) {
            // Subtitles Menu
            if !playerVM.subtitleTracks.isEmpty {
                Menu {
                    ForEach(playerVM.subtitleTracks) { track in
                        Button(action: {
                            delegate.onSubtitleTrackSelected(track.index)
                        }) {
                            if track.index == playerVM.selectedSubtitleTrack {
                                Label(track.name, systemImage: "checkmark")
                            } else {
                                Text(track.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSubtitlesOn ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 16))
                        Text(isSubtitlesOn ? subtitleTrackName : "Subtitles")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSubtitlesOn ? Color.blue : Color.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        Capsule()
                            .fill(isSubtitlesOn ? Color.blue.opacity(0.25) : Color.white.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(isSubtitlesOn ? Color.blue.opacity(0.5) : Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            
            // Audio Tracks Menu
            if !playerVM.audioTracks.isEmpty {
                Menu {
                    ForEach(playerVM.audioTracks) { track in
                        Button(action: {
                            delegate.onAudioTrackSelected(track.index)
                        }) {
                            if track.index == playerVM.selectedAudioTrack {
                                Label(track.name, systemImage: "checkmark")
                            } else {
                                Text(track.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14))
                        Text(audioTrackName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                    )
                }
            }
            
            #if os(iOS)
            Spacer()
            
            // Inline Volume Slider
            HStack(spacing: 8) {
                Button(action: {
                    if playerVM.volume > 0 {
                        delegate.changeVolume(0)
                    } else {
                        delegate.changeVolume(0.5)
                    }
                }) {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 18)
                }
                .buttonStyle(PlainButtonStyle())
                
                Slider(
                    value: Binding(
                        get: { Double(playerVM.volume) },
                        set: { val in
                            delegate.changeVolume(Float(val))
                        }
                    ),
                    in: 0...1
                )
                .accentColor(.blue)
                .frame(width: 90)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
            )
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
    
    private var isSubtitlesOn: Bool {
        playerVM.selectedSubtitleTrack != -1
    }
    
    private var subtitleTrackName: String {
        if let current = playerVM.subtitleTracks.first(where: { $0.index == playerVM.selectedSubtitleTrack }) {
            return current.name
        }
        return "Subtitles"
    }
    
    private var audioTrackName: String {
        if let current = playerVM.audioTracks.first(where: { $0.index == playerVM.selectedAudioTrack }) {
            return current.name
        }
        return "Audio"
    }
    
    private var volumeIconName: String {
        volumeIcon(for: playerVM.volume)
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

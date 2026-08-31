import SwiftUI
import Combine

/// Isolated progress model so high-frequency playback position ticks do NOT re-render menus or top bar
public final class PlaybackProgressModel: ObservableObject {
    @Published public var position: Float = 0.0
    @Published public var currentTime: String = "00:00"
    @Published public var totalTime: String = "00:00"
    @Published public var remainingTime: String = "00:00"
    @Published public var currentTimeInSeconds: Double = 0.0
    @Published public var totalDurationInSeconds: Double = 0.0
    
    public init() {}
}

//
//  ControlsViewModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Siyahul Haq. All rights reserved.
//

import SwiftUI
import Combine

public final class PlayerViewModel: ObservableObject {
    public let progress = PlaybackProgressModel()
    
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var isLocked: Bool = false
    @Published public var isControlsVisible: Bool = true
    
    @Published public var audioTracks: [Tracks] = []
    @Published public var subtitleTracks: [Tracks] = []
    @Published public var selectedAudioTrack: Int32 = -1
    @Published public var selectedSubtitleTrack: Int32 = -1
    
    @Published public var title: String = ""
    @Published public var fileName: String = ""
    
    @Published public var volume: Float = 1.0
    @Published public var brightness: Float = 0.5
    @Published public var playbackSpeed: Float = 1.0
    @Published public var aspectRatio: VideoAspectRatio = .fit
    
    @Published public var activeHUD: HUDState? = nil
    @Published public var doubleTapRipple: DoubleTapRippleSide? = nil
    
    @Published public var showResumePrompt: Bool = false
    @Published public var resumeTime: Double = 0
    @Published public var resumeTimeString: String = ""
    
    // Convenience accessors mapping to isolated progress model
    public var position: Float {
        get { progress.position }
        set { progress.position = newValue }
    }
    public var currentTime: String {
        get { progress.currentTime }
        set { progress.currentTime = newValue }
    }
    public var totalTime: String {
        get { progress.totalTime }
        set { progress.totalTime = newValue }
    }
    public var remainingTime: String {
        get { progress.remainingTime }
        set { progress.remainingTime = newValue }
    }
    public var currentTimeInSeconds: Double {
        get { progress.currentTimeInSeconds }
        set { progress.currentTimeInSeconds = newValue }
    }
    public var totalDurationInSeconds: Double {
        get { progress.totalDurationInSeconds }
        set { progress.totalDurationInSeconds = newValue }
    }
    
    public init() {}
}

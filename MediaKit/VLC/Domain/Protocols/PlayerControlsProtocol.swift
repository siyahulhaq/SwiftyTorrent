//
//  PlayerControlsProtocol.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Siyahul Haq. All rights reserved.
//

import Foundation

public protocol PlayerControlsProtocol: AnyObject {
    func onTogglePlayPause()
    func onBackward()
    func onForward()
    func onSliderChange(_ position: Float)
    func onStop()
    func onClose()
    func onAudioTrackSelected(_ index: Int32)
    func onSubtitleTrackSelected(_ index: Int32)
    func changeVolume(_ value: Float)
    func changeBrightness(_ value: Float)
    func changePlaybackSpeed(_ speed: Float)
    func changeAspectRatio(_ ratio: VideoAspectRatio)
    func toggleLock()
    func seekBy(seconds: Double)
    func onScreenTapped()
    func onDoubleTapped(at location: CGPoint, screenWidth: CGFloat)
    func onResumePlayback(at seconds: Double)
    func onStartOver()
}

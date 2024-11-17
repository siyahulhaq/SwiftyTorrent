//
//  PlayerControlsProtocol.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

protocol PlayerControlsProtocol {
    func onTogglePlayPause()
    func onBackward()
    func onForward()
    func onSliderChange(_ position: Float)
    func onStop()
    func onClose()
    func onAudioTrackSelected(_ index: Int32)
    func onSubtitleTrackSelected(_ index: Int32)
    func changeVolume(_ value: Float)
}

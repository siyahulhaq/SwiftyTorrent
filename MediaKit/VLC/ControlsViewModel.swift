//
//  ControlsViewModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

struct Tracks {
    let index: Int32
    let name: String
}

class ControlsViewModel: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var position: Float = 0.0
    @Published var currentTime: String = "00:00"
    @Published var totalTime: String = "00:00"
    @Published var remainingTime: String = "00:00"
    @Published var audioTracks: [Tracks] = []
    @Published var subtitleTracks: [Tracks] = []
    @Published var selectedAudioTrack: Int32 = -1
    @Published var selectedSubtitleTrack: Int32 = -1
    @Published var title: String = "Title"
    @Published var fileName: String = ""
    @Published var volume: Float = 1
}

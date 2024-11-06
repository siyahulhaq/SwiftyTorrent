//
//  TorrentsAttributes.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 05/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import ActivityKit

struct TorrentsWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var downloadProgress: Double
        var downloadSpeed: Int
        var uploadSpeed: Int
        var peers: Int
        var seeds: Int
        var status: String
    }
    
    var torrentName: String
    var totalSize: Int64
}


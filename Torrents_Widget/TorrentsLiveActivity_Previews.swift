//
//  TorrentsLiveActivity_Previews.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 05/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

struct TorrentsLiveActivity_Previews: PreviewProvider {
    static let attributes = TorrentsWidgetAttributes(
        torrentName: "Ubuntu 22.04 LTS",
        totalSize: 3_500_000_000 // 3.5GB
    )
    
    static let contentState = TorrentsWidgetAttributes.ContentState(
        downloadProgress: 0.45,
        downloadSpeed: 2_000_000, // 2MB/s
        uploadSpeed: 500_000,     // 500KB/s
        peers: 12,
        seeds: 45,
        status: "Downloading"
    )
    
    static var previews: some View {
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Island Compact")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Island Expanded")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Minimal")
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Notification")
    }
}

//
//  File+PreviewItem.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31.08.2026.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import MediaKit
import TorrentKit

extension File: PreviewItem {
    
    private var torrentManager: TorrentManagerProtocol {
        resolveComponent(TorrentManagerProtocol.self)
    }
    
    public var previewItemURL: URL? {
        if (self.isDownloads) {
            return torrentManager
                .downloadsDirectoryURL()
                .appendingPathComponent(path)
        }
        return URL(string: "file://\(path)")
    }
    
    public var previewItemTitle: String? {
        return title
    }
    
}

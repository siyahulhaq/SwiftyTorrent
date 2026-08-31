//
//  FileRowModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/16/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

import Foundation
import TorrentKit

protocol FileRowModel {
    
    var title: String { get }
    
    var sizeDetails: String? { get }
    
    var isDirectory: Bool { get }
    
}

extension FileEntry: FileRowModel {
    var isDirectory: Bool {
        false
    }
    
    var title: String { name }
    
    var sizeDetails: String? {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
}

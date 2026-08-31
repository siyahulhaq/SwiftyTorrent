//
//  File+UTI.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31.08.2026.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers

extension File {
    
    private var fileExtension: String {
        return URL(fileURLWithPath: path).pathExtension
    }
        
    var isVideo: Bool {
        // Special handling for 'mkv' container
        switch fileExtension {
        case "mkv": return true
        default: break
        }
        // Other file extensions
        guard
            let mimeUTI = UTType(filenameExtension: fileExtension)
        else { return false }
        return mimeUTI.conforms(to: .audiovisualContent)
    }
    
    var isImage: Bool {
        guard
            let mimeUTI = UTType(filenameExtension: fileExtension)
        else { return false }
        return mimeUTI.conforms(to: .image)
    }
    
}

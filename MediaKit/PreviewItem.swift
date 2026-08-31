//
//  PreviewItem.swift
//  MediaKit
//
//  Created by Siyahul Haq on 31.08.2026.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation

public protocol PreviewItem {
    
    var previewItemURL: URL? { get }
    var previewItemTitle: String? { get }
    
}

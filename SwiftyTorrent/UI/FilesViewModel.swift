//
//  FilesViewModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/16/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

import Foundation
import TorrentKit

protocol FilesViewModel {
    
    var title: String { get }
    
    var directory: Directory { get }

}

extension Directory: FilesViewModel {
    
    var title: String { name }
    
    var directory: Directory { self }
    
}

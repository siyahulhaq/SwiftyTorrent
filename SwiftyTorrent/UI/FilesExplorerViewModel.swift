//
//  FilesExplorerViewModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

final class FilesExplorerViewModel: ObservableObject {
    @Published var directory: Directory?
    
    func generateRootDirectory(_ path: String) -> Directory {
        let directory = Directory.directory(with: path)
        return directory
    }
    
    func getRootPath() {
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            self.directory = self.generateRootDirectory(documentsPath)
        }
    }
}

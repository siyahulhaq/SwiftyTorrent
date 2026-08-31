//
//  FilesExplorerView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Siyahul Haq. All rights reserved.
//
import SwiftUI

struct FilesExplorerView: View {
    var body: some View {
        NavigationStack {
            CloudLocationsView()
        }
    }
}

// Preview Provider
struct FileExplorerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FilesExplorerView()
        }
    }
}

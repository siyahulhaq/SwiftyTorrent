//
//  FilesExplorerView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 17/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//
import SwiftUI

struct FilesExplorerView: View {
    @ObservedObject var model = FilesExplorerViewModel()
    var body: some View {
        NavigationStack {
            if let directory = model.directory {
                FilesView(model: directory)
                    .navigationTitle("Files")
            } else {
                Text("Unable to access Documents folder")

            }
        }.onAppear {
            model.getRootPath()
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

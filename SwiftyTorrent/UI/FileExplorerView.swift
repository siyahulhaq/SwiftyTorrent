
import SwiftUI

struct FilesExplorerView: View {
    var body: some View {
        NavigationView {
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
                FolderView(directory: Directory(name: "Documents", path: documentsPath))
            } else {
                Text("Unable to access Documents folder")
            }
        }
    }
}

struct FolderView: View {
    let directory: Directory
    @StateObject private var viewModel = FilesExplorerViewModel()
    
    var body: some View {
        List {
            ForEach(viewModel.directory.allSubDirectories, id: \.path) { subDir in
                NavigationLink(destination: FolderView(directory: subDir)) {
                    FileRow(model: subDir)
                }
            }
            ForEach(viewModel.directory.allFiles, id: \.path) { file in
                Button(action: {
                    // Handle file selection
                }) {
                    FileRow(model: file)
                }
            }
        }
        .navigationTitle(directory.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadContents(at: directory.path)
        }
    }
}

#if DEBUG
struct FileExplorerView_Previews: PreviewProvider {
    static var previews: some View {
        FilesExplorerView()
    }
}
#endif
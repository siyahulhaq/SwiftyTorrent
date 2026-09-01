//
//  CloudExplorerView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import MediaKit

public enum ActiveModalPreview: Identifiable {
    case vlc(CloudFileItem)
    case quickLook(CloudFileItem)
    
    public var id: String {
        switch self {
        case .vlc(let item): return "vlc_\(item.id)_\(item.name)"
        case .quickLook(let item): return "ql_\(item.id)_\(item.name)"
        }
    }
}

public struct CloudExplorerView: View {
    @StateObject private var viewModel: CloudExplorerViewModel
    @ObservedObject private var downloadManager = CloudDownloadManager.shared
    @State private var activeModal: ActiveModalPreview?
    @State private var openingItemId: String?
    @State private var showDownloadsSheet: Bool = false
    
    public init(provider: CloudStorageProviderProtocol, folderId: String? = nil, folderName: String? = nil) {
        _viewModel = StateObject(wrappedValue: CloudExplorerViewModel(provider: provider, folderId: folderId, folderName: folderName))
    }
    
    public var body: some View {
        List {
            // Subdirectories Section
            if !viewModel.filteredDirectories.isEmpty {
                Section(header: Text("Folders (\(viewModel.filteredDirectories.count))")) {
                    ForEach(viewModel.filteredDirectories) { folder in
                        NavigationLink(destination: CloudExplorerView(
                            provider: viewModel.provider,
                            folderId: folder.path,
                            folderName: folder.name
                        )) {
                            CloudFileRowView(item: folder, dateSortField: viewModel.sortField)
                        }
                    }
                }
            }
            
            // Files Section
            if !viewModel.filteredFiles.isEmpty {
                Section(header: Text("Files (\(viewModel.filteredFiles.count))")) {
                    ForEach(viewModel.filteredFiles) { file in
                        Button(action: {
                            print("[CloudExplorerView] Row tapped for file: '\(file.name)', id: '\(file.id)', mimeType: '\(file.mimeType ?? "none")', size: \(file.size)")
                            handleFileSelection(file)
                        }) {
                            CloudFileRowView(
                                item: file,
                                dateSortField: viewModel.sortField,
                                isPreparing: (openingItemId == file.id),
                                downloadProgress: downloadManager.activeDownloads[file.id],
                                isDownloaded: downloadManager.isItemDownloaded(file)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if viewModel.provider.descriptor.capabilities.contains(.deletion) {
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.deleteItem(file)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            
                            if !file.isDirectory && viewModel.provider.descriptor.id != LocalStorageProvider.providerId {
                                Button {
                                    downloadManager.startDownload(item: file, provider: viewModel.provider)
                                } label: {
                                    Label("Download", systemImage: "arrow.down.circle")
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            if !file.isDirectory {
                                Button {
                                    handleFileSelection(file)
                                } label: {
                                    Label(file.isPlayableMedia ? "Play Media" : "Preview File", systemImage: file.isPlayableMedia ? "play.circle" : "eye")
                                }
                                
                                if viewModel.provider.descriptor.id != LocalStorageProvider.providerId {
                                    Button {
                                        downloadManager.startDownload(item: file, provider: viewModel.provider)
                                    } label: {
                                        Label("Download to Device", systemImage: "arrow.down.circle")
                                    }
                                }
                                
                                if viewModel.provider.descriptor.capabilities.contains(.deletion) {
                                    Divider()
                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.deleteItem(file)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Empty State
            if !viewModel.isLoading && viewModel.filteredDirectories.isEmpty && viewModel.filteredFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No files in this folder")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(viewModel.folderName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search files & folders")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { showDownloadsSheet = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 18))
                            
                            if !downloadManager.activeTasks.isEmpty {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    
                    sortMenu
                }
            }
        }
        .sheet(isPresented: $showDownloadsSheet) {
            NavigationStack {
                DownloadsManagerView()
            }
        }
        .refreshable {
            await viewModel.loadContents()
        }
        .task {
            await viewModel.loadContents()
        }
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading...")
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let err = viewModel.errorMessage {
                Text(err)
            }
        }
        .alert(downloadManager.alertMessage ?? "", isPresented: Binding(
            get: { downloadManager.alertMessage != nil },
            set: { if !$0 { downloadManager.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        // Unified Full Screen Modal for Media and QuickLook Preview
        .fullScreenCover(item: $activeModal) { modal in
            switch modal {
            case .vlc(let item):
                VLCViewHost(previewItem: item)
                    .ignoresSafeArea(.all)
            case .quickLook(let item):
                QLPreviewModalView(previewItem: item)
                    .ignoresSafeArea(.all)
            }
        }
    }
    
    private func handleFileSelection(_ file: CloudFileItem) {
        print("[CloudExplorerView] handleFileSelection entered for file: '\(file.name)', openingItemId currently: '\(openingItemId ?? "nil")'")
        guard openingItemId == nil else {
            print("[CloudExplorerView] Ignored tap because openingItemId is already active: '\(openingItemId!)'")
            return
        }
        openingItemId = file.id
        
        print("[CloudExplorerView] Starting preparePlayback Task for '\(file.name)'...")
        Task {
            let readyItem = await viewModel.preparePlayback(for: file) as? CloudFileItem
            print("[CloudExplorerView] preparePlayback completed for '\(file.name)'. Ready item: \(readyItem != nil ? "SUCCESS" : "FAILED/NIL")")
            
            await MainActor.run {
                self.openingItemId = nil
                guard let readyItem = readyItem else {
                    print("[CloudExplorerView] readyItem is nil, aborting modal presentation. Check previous error logs.")
                    return
                }
                print("[CloudExplorerView] Setting activeModal. isPlayableMedia = \(readyItem.isPlayableMedia), URL = \(readyItem.previewItemURL?.absoluteString ?? "nil")")
                if readyItem.isPlayableMedia {
                    self.activeModal = .vlc(readyItem)
                } else {
                    self.activeModal = .quickLook(readyItem)
                }
            }
        }
    }
    
    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(FileSortField.allCases) { field in
                    Button(action: {
                        viewModel.sortField = field
                    }) {
                        HStack {
                            Text(field.rawValue)
                            Spacer()
                            if viewModel.sortField == field {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Section("Order") {
                ForEach(FileSortOrder.allCases) { order in
                    Button(action: {
                        viewModel.sortOrder = order
                    }) {
                        HStack {
                            Text(order.rawValue)
                            Spacer()
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 18))
        }
    }
}

//
//  DownloadsManagerView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 01/09/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI
import MediaKit

public struct DownloadsManagerView: View {
    @ObservedObject private var downloadManager = CloudDownloadManager.shared
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var selectedFilter: DownloadFilter = .all
    @State private var searchText: String = ""
    @State private var activeModal: ActiveModalPreview?
    @State private var openingItemId: String?
    @State private var fileToShare: URL?
    @State private var showClearAllAlert: Bool = false
    @State private var fileToDelete: CloudFileItem?
    
    private let localStorageProvider = LocalStorageProvider()
    
    public enum DownloadFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        
        public var id: String { rawValue }
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Summary Card
            summaryHeaderView
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // Filter Segmented Control
            Picker("Filter", selection: $selectedFilter) {
                ForEach(DownloadFilter.allCases) { filter in
                    Text(filterTitle(for: filter)).tag(filter)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Content List
            List {
                // Active Downloads Section
                if (selectedFilter == .all || selectedFilter == .active) && !filteredActiveTasks.isEmpty {
                    Section(header: Text("In Progress (\(filteredActiveTasks.count))")) {
                        ForEach(filteredActiveTasks) { task in
                            activeTaskRow(task)
                        }
                    }
                }
                
                // Completed Downloads Section
                if (selectedFilter == .all || selectedFilter == .completed) && !filteredCompletedFiles.isEmpty {
                    Section(header: Text("Completed on Device (\(filteredCompletedFiles.count))")) {
                        ForEach(filteredCompletedFiles) { file in
                            completedFileRow(file)
                        }
                    }
                }
                
                // Empty State
                if shouldShowEmptyState {
                    emptyStateView
                }
            }
            .listStyle(InsetGroupedListStyle())
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search downloaded files")
            .refreshable {
                downloadManager.reloadDownloadedFiles()
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if !downloadManager.completedFiles.isEmpty {
                    Button(role: .destructive) {
                        showClearAllAlert = true
                    } label: {
                        Text("Clear All")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert("Clear All Downloads?", isPresented: $showClearAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                downloadManager.clearAllCompleted()
            }
        } message: {
            Text("This will permanently remove all downloaded files from this device.")
        }
        .sheet(item: $fileToShare) { url in
            ActivityViewControllerPresenter(activityItems: [url])
        }
        .fullScreenCover(item: $activeModal) { modal in
            switch modal {
            case .vlc(let item):
                MediaPlayerViewHost(previewItem: item)
                    .ignoresSafeArea(.all)
            case .quickLook(let item):
                QLPreviewModalView(previewItem: item)
                    .ignoresSafeArea(.all)
            }
        }
        .onAppear {
            downloadManager.reloadDownloadedFiles()
        }
    }
    
    // MARK: - Header Summary
    
    private var summaryHeaderView: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Device Downloads")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Text("\(downloadManager.completedFiles.count) files")
                    Text("•")
                    Text(downloadManager.formattedTotalDownloadedSize)
                    if !downloadManager.activeTasks.isEmpty {
                        Text("•")
                        Text("\(downloadManager.activeTasks.count) downloading")
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Active Row
    
    private func activeTaskRow(_ task: DownloadTaskItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(task.providerDisplayName)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        if task.size > 0 {
                            Text("• \(task.formattedSize)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    downloadManager.cancelDownload(itemId: task.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: task.progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                
                Text(task.formattedProgress)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Completed Row
    
    private func completedFileRow(_ file: CloudFileItem) -> some View {
        Button(action: {
            handlePlayCompleted(file)
        }) {
            HStack(spacing: 14) {
                Image(systemName: iconName(for: file.name))
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundColor(iconColor(for: file.name))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        if let size = file.sizeDetails {
                            Text(size)
                        }
                        if let date = file.modifiedAt ?? file.createdAt {
                            Text("•")
                            Text(date, style: .date)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if openingItemId == file.id {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Button(action: {
                        if let url = file.localURL ?? downloadManager.localFileURL(for: file) {
                            self.fileToShare = url
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                            .padding(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                downloadManager.deleteDownloadedFile(file)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                if let url = file.localURL ?? downloadManager.localFileURL(for: file) {
                    self.fileToShare = url
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                handlePlayCompleted(file)
            } label: {
                Label(file.isPlayableMedia ? "Play Media" : "Preview File", systemImage: file.isPlayableMedia ? "play.circle" : "eye")
            }
            
            Button {
                if let url = file.localURL ?? downloadManager.localFileURL(for: file) {
                    self.fileToShare = url
                }
            } label: {
                Label("Share File", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            Button(role: .destructive) {
                downloadManager.deleteDownloadedFile(file)
            } label: {
                Label("Delete from Device", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Files downloaded from SMB shares, Google Drive, or iCloud will be saved and managed here.")
                .font(.subheadline)
                .foregroundColor(Color(UIColor.tertiaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
    
    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all: return "No Downloads Yet"
        case .active: return "No Active Downloads"
        case .completed: return "No Completed Downloads"
        }
    }
    
    private var shouldShowEmptyState: Bool {
        switch selectedFilter {
        case .all:
            return filteredActiveTasks.isEmpty && filteredCompletedFiles.isEmpty
        case .active:
            return filteredActiveTasks.isEmpty
        case .completed:
            return filteredCompletedFiles.isEmpty
        }
    }
    
    // MARK: - Playback
    
    private func handlePlayCompleted(_ file: CloudFileItem) {
        guard openingItemId == nil else { return }
        openingItemId = file.id
        
        Task {
            let readyItem = try? await CloudPlaybackCoordinator.shared.prepareForPlayback(item: file, provider: localStorageProvider) as? CloudFileItem
            
            await MainActor.run {
                self.openingItemId = nil
                guard let readyItem = readyItem else { return }
                if readyItem.isPlayableMedia {
                    self.activeModal = .vlc(readyItem)
                } else {
                    self.activeModal = .quickLook(readyItem)
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func filterTitle(for filter: DownloadFilter) -> String {
        switch filter {
        case .all:
            let total = downloadManager.activeTasks.count + downloadManager.completedFiles.count
            return total > 0 ? "All (\(total))" : "All"
        case .active:
            let count = downloadManager.activeTasks.count
            return count > 0 ? "Active (\(count))" : "Active"
        case .completed:
            let count = downloadManager.completedFiles.count
            return count > 0 ? "Completed (\(count))" : "Completed"
        }
    }
    
    private var filteredActiveTasks: [DownloadTaskItem] {
        let all = Array(downloadManager.activeTasks.values)
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return all.sorted { $0.startDate > $1.startDate }
        }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.startDate > $1.startDate }
    }
    
    private var filteredCompletedFiles: [CloudFileItem] {
        let all = downloadManager.completedFiles
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return all
        }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func iconName(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let videoExts: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "wmv", "ts", "m2ts"]
        let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff"]
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg"]
        
        if videoExts.contains(ext) {
            return "play.rectangle.fill"
        } else if audioExts.contains(ext) {
            return "music.note"
        } else if imageExts.contains(ext) {
            return "photo.fill"
        } else if ext == "pdf" {
            return "doc.text.fill"
        } else if ext == "zip" || ext == "rar" || ext == "7z" || ext == "tar" || ext == "gz" {
            return "archivebox.fill"
        }
        return "doc.fill"
    }
    
    private func iconColor(for name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        let videoExts: Set<String> = ["mp4", "mkv", "avi", "mov", "m4v", "webm", "flv", "wmv", "ts", "m2ts"]
        let audioExts: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "aiff"]
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp", "svg"]
        
        if videoExts.contains(ext) {
            return .purple
        } else if audioExts.contains(ext) {
            return .pink
        } else if imageExts.contains(ext) {
            return .teal
        } else if ext == "pdf" {
            return .red
        }
        return .blue
    }
}

// Presenter for native iOS Share Sheet with URL
private struct ActivityViewControllerPresenter: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


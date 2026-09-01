//
//  CloudDownloadManager.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 01/09/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

public enum DownloadStatus: Equatable {
    case queued
    case downloading(progress: Double)
    case completed(url: URL)
    case failed(error: String)
    case cancelled
}

public struct DownloadTaskItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let size: UInt64
    public let providerId: String
    public let providerDisplayName: String
    public var progress: Double
    public var status: DownloadStatus
    public var localURL: URL?
    public var startDate: Date
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    public var formattedProgress: String {
        "\(Int(progress * 100))%"
    }
}

@MainActor
public final class CloudDownloadManager: ObservableObject {
    public static let shared = CloudDownloadManager()
    
    @Published public var activeDownloads: [String: Double] = [:] // itemId -> progress (0.0...1.0)
    @Published public var activeTasks: [String: DownloadTaskItem] = [:]
    @Published public var completedDownloadIds: Set<String> = []
    @Published public var completedFiles: [CloudFileItem] = []
    @Published public var alertMessage: String?
    
    private var downloadJobs: [String: Task<Void, Never>] = [:]
    
    private init() {
        reloadDownloadedFiles()
    }
    
    // MARK: - Directory
    
    public func downloadsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }
        return downloadsDir
    }
    
    public func destinationURL(for fileName: String) -> URL {
        let baseDir = downloadsDirectory()
        let targetURL = baseDir.appendingPathComponent(fileName)
        
        if !FileManager.default.fileExists(atPath: targetURL.path) {
            return targetURL
        }
        
        let ext = (fileName as NSString).pathExtension
        let baseName = (fileName as NSString).deletingPathExtension
        var counter = 1
        while true {
            let candidateName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            let candidateURL = baseDir.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }
    
    // MARK: - File Checks
    
    public func isItemDownloaded(_ item: CloudFileItem) -> Bool {
        if completedDownloadIds.contains(item.id) {
            return true
        }
        let target = downloadsDirectory().appendingPathComponent(item.name)
        return FileManager.default.fileExists(atPath: target.path)
    }
    
    public func localFileURL(for item: CloudFileItem) -> URL? {
        let target = downloadsDirectory().appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        return nil
    }
    
    public func reloadDownloadedFiles() {
        let dir = downloadsDirectory()
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            self.completedFiles = []
            return
        }
        
        let items: [CloudFileItem] = fileURLs.compactMap { url in
            let rawName = url.lastPathComponent
            if rawName == ".DS_Store" || rawName.hasPrefix("._") {
                return nil
            }
            
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
            let isDir = values.isDirectory ?? false
            let size = UInt64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate
            let createDate = values.creationDate
            
            return CloudFileItem(
                id: "local_download_\(url.lastPathComponent)",
                providerId: LocalStorageProvider.providerId,
                name: url.lastPathComponent,
                path: url.path,
                size: size,
                isDirectory: isDir,
                localURL: url,
                remoteURL: nil,
                isDownloads: true,
                createdAt: createDate,
                modifiedAt: modDate
            )
        }.sorted { ($0.modifiedAt ?? Date.distantPast) > ($1.modifiedAt ?? Date.distantPast) }
        
        self.completedFiles = items
        for item in items {
            self.completedDownloadIds.insert(item.name)
            self.completedDownloadIds.insert(item.id)
        }
    }
    
    public var totalDownloadedSize: UInt64 {
        completedFiles.reduce(0) { $0 + $1.size }
    }
    
    public var formattedTotalDownloadedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalDownloadedSize), countStyle: .file)
    }
    
    // MARK: - Download Execution
    
    public func startDownload(item: CloudFileItem, provider: CloudStorageProviderProtocol) {
        guard !item.isDirectory else { return }
        guard activeDownloads[item.id] == nil else { return }
        
        let initialTask = DownloadTaskItem(
            id: item.id,
            name: item.name,
            size: item.size,
            providerId: provider.descriptor.id,
            providerDisplayName: provider.descriptor.displayName,
            progress: 0.01,
            status: .downloading(progress: 0.01),
            localURL: nil,
            startDate: Date()
        )
        
        activeTasks[item.id] = initialTask
        activeDownloads[item.id] = 0.01
        
        let task = Task {
            do {
                let tempURL = try await provider.download(item: item) { [weak self] fraction in
                    Task { @MainActor in
                        let clamped = max(0.01, min(1.0, fraction))
                        self?.activeDownloads[item.id] = clamped
                        if var taskItem = self?.activeTasks[item.id] {
                            taskItem.progress = clamped
                            taskItem.status = .downloading(progress: clamped)
                            self?.activeTasks[item.id] = taskItem
                        }
                    }
                }
                
                let destURL = self.destinationURL(for: item.name)
                
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.removeItem(at: destURL)
                }
                
                if tempURL.path != destURL.path {
                    try FileManager.default.copyItem(at: tempURL, to: destURL)
                }
                
                await MainActor.run {
                    self.activeDownloads.removeValue(forKey: item.id)
                    self.activeTasks.removeValue(forKey: item.id)
                    self.downloadJobs.removeValue(forKey: item.id)
                    self.completedDownloadIds.insert(item.id)
                    self.completedDownloadIds.insert(item.name)
                    self.reloadDownloadedFiles()
                    self.alertMessage = "Downloaded '\(item.name)' to On This Device / Downloads"
                    NotificationCenter.default.post(name: NSNotification.Name("LocalDownloadsDidUpdateNotification"), object: nil)
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        self.activeDownloads.removeValue(forKey: item.id)
                        self.activeTasks.removeValue(forKey: item.id)
                        self.downloadJobs.removeValue(forKey: item.id)
                    }
                    return
                }
                
                await MainActor.run {
                    self.activeDownloads.removeValue(forKey: item.id)
                    if var taskItem = self.activeTasks[item.id] {
                        taskItem.status = .failed(error: error.localizedDescription)
                        self.activeTasks[item.id] = taskItem
                    }
                    self.downloadJobs.removeValue(forKey: item.id)
                    self.alertMessage = "Failed to download '\(item.name)': \(error.localizedDescription)"
                }
            }
        }
        
        downloadJobs[item.id] = task
    }
    
    public func cancelDownload(itemId: String) {
        downloadJobs[itemId]?.cancel()
        downloadJobs.removeValue(forKey: itemId)
        activeDownloads.removeValue(forKey: itemId)
        activeTasks.removeValue(forKey: itemId)
    }
    
    public func deleteDownloadedFile(_ item: CloudFileItem) {
        if let local = item.localURL {
            try? FileManager.default.removeItem(at: local)
        } else {
            let target = downloadsDirectory().appendingPathComponent(item.name)
            try? FileManager.default.removeItem(at: target)
        }
        completedDownloadIds.remove(item.id)
        completedDownloadIds.remove(item.name)
        reloadDownloadedFiles()
        NotificationCenter.default.post(name: NSNotification.Name("LocalDownloadsDidUpdateNotification"), object: nil)
    }
    
    public func clearAllCompleted() {
        let dir = downloadsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        completedDownloadIds.removeAll()
        reloadDownloadedFiles()
        NotificationCenter.default.post(name: NSNotification.Name("LocalDownloadsDidUpdateNotification"), object: nil)
    }
}

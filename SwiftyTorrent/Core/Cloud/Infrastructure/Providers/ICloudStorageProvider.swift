//
//  ICloudStorageProvider.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Foundation

public final class ICloudStorageProvider: CloudStorageProviderProtocol {
    public static let providerId = "icloud"
    
    public var descriptor: CloudProviderDescriptor {
        CloudProviderDescriptor(
            id: Self.providerId,
            displayName: "iCloud Drive",
            subtitle: "Apple Cloud Storage",
            iconName: "icloud.fill",
            brandColorHex: "34AADC",
            authType: .documentPicker,
            capabilities: [.streaming, .downloading, .uploading, .deletion, .search]
        )
    }
    
    public var account: CloudAccount?
    
    public init(account: CloudAccount? = nil) {
        self.account = account
    }
    
    public func authenticate(from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        guard let account = self.account else {
            throw NSError(domain: "ICloudStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please select an iCloud Drive folder."])
        }
        return account
    }
    
    public func disconnect() async throws {
        if let account = self.account {
            CloudAccountManager.shared.delete(account: account)
            self.account = nil
        }
    }
    
    // MARK: - Folder URL Resolution
    
    private func resolveFolderURL(folderPath: String?) throws -> (url: URL, isSecurityScoped: Bool) {
        if let folderPath = folderPath, !folderPath.isEmpty {
            return (URL(fileURLWithPath: folderPath), false)
        }
        
        if let bookmarkBase64 = account?.customProperties["bookmark"],
           let bookmarkData = Data(base64Encoded: bookmarkBase64) {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return (resolved, true)
            }
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return (resolved, true)
            }
        }
        
        if let savedPath = account?.customProperties["path"], !savedPath.isEmpty {
            let directURL = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: directURL.path) {
                return (directURL, false)
            }
        }
        
        if let ubiquitousURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            return (ubiquitousURL, false)
        }
        
        throw NSError(domain: "ICloudStorageProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "No iCloud folder linked. Tap '+' to connect an iCloud folder."])
    }
    
    // MARK: - Ubiquitous Download Handling
    
    private func ensureUbiquitousItemDownloaded(at url: URL) async throws -> URL {
        let fileManager = FileManager.default
        var targetURL = url
        
        // Handle .filename.ext.icloud (dataless cloud placeholder)
        if url.lastPathComponent.hasPrefix(".") && url.pathExtension == "icloud" {
            print("[ICloudStorageProvider] Downloading dataless iCloud item: \(url.lastPathComponent)")
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            
            let parent = url.deletingLastPathComponent()
            let cleanName = String(url.deletingPathExtension().lastPathComponent.dropFirst())
            let expectedURL = parent.appendingPathComponent(cleanName)
            
            for _ in 0..<60 {
                if fileManager.fileExists(atPath: expectedURL.path) {
                    targetURL = expectedURL
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        } else if fileManager.isUbiquitousItem(at: url) {
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus != .current {
                print("[ICloudStorageProvider] Triggering download for ubiquitous item: \(url.lastPathComponent)")
                try? fileManager.startDownloadingUbiquitousItem(at: url)
                
                for _ in 0..<60 {
                    let updated = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if updated?.ubiquitousItemDownloadingStatus == .current {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        
        return targetURL
    }
    
    // MARK: - Listing
    
    public func listFolder(folderId: String?, cursor: String?) async throws -> CloudFolderContents {
        let (targetURL, isSecurityScoped) = try resolveFolderURL(folderPath: folderId)
        
        if isSecurityScoped {
            _ = targetURL.startAccessingSecurityScopedResource()
        }
        defer {
            if isSecurityScoped {
                targetURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: resourceKeys, options: []) else {
            return CloudFolderContents(items: [])
        }
        
        let items: [CloudFileItem] = fileURLs.compactMap { url in
            let rawName = url.lastPathComponent
            
            // Skip system hidden files
            if rawName == ".DS_Store" || rawName == ".Trash" || rawName.hasPrefix("._") {
                return nil
            }
            
            var displayName = rawName
            if rawName.hasPrefix(".") && rawName.hasSuffix(".icloud") {
                displayName = String(url.deletingPathExtension().lastPathComponent.dropFirst())
            }
            
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
            let isDir = values.isDirectory ?? false
            let size = UInt64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate
            let createDate = values.creationDate
            
            return CloudFileItem(
                id: url.path,
                providerId: Self.providerId,
                accountId: self.account?.id,
                name: displayName,
                path: url.path,
                size: size,
                isDirectory: isDir,
                localURL: url,
                remoteURL: nil,
                isDownloads: false,
                createdAt: createDate,
                modifiedAt: modDate
            )
        }
        
        return CloudFolderContents(items: items)
    }
    
    // MARK: - Playback & Download
    
    public func getStreamURL(for item: CloudFileItem) async throws -> URL {
        let (rootURL, isSecurityScoped) = try resolveFolderURL(folderPath: nil)
        if isSecurityScoped {
            _ = rootURL.startAccessingSecurityScopedResource()
        }
        
        let sourceURL = item.localURL ?? URL(fileURLWithPath: item.path)
        let readyURL = try await ensureUbiquitousItemDownloaded(at: sourceURL)
        
        _ = readyURL.startAccessingSecurityScopedResource()
        return readyURL
    }
    
    public func download(item: CloudFileItem, progress: @escaping (Double) -> Void) async throws -> URL {
        let (rootURL, isSecurityScoped) = try resolveFolderURL(folderPath: nil)
        if isSecurityScoped {
            _ = rootURL.startAccessingSecurityScopedResource()
        }
        defer {
            if isSecurityScoped {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let sourceURL = item.localURL ?? URL(fileURLWithPath: item.path)
        let readyURL = try await ensureUbiquitousItemDownloaded(at: sourceURL)
        
        // Cache non-media preview file in Caches directory for QuickLook access
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CloudPreviews", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        let destURL = cacheDir.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        
        try FileManager.default.copyItem(at: readyURL, to: destURL)
        progress(1.0)
        return destURL
    }
    
    public func search(query: String) async throws -> [CloudFileItem] {
        let contents = try await listFolder(folderId: nil, cursor: nil)
        return contents.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    public func delete(item: CloudFileItem) async throws {
        let url = item.localURL ?? URL(fileURLWithPath: item.path)
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try FileManager.default.removeItem(at: url)
    }
}

//
//  LocalStorageProvider.swift
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

public final class LocalStorageProvider: CloudStorageProviderProtocol {
    public static let providerId = "local"
    
    public var descriptor: CloudProviderDescriptor {
        CloudProviderDescriptor(
            id: Self.providerId,
            displayName: "Downloads",
            subtitle: "On This Device",
            iconName: "iphone",
            brandColorHex: "007AFF",
            authType: .none,
            capabilities: [.streaming, .downloading, .uploading, .deletion, .search]
        )
    }
    
    public var account: CloudAccount?
    
    public init(account: CloudAccount? = nil) {
        self.account = account
    }
    
    public func authenticate(from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        return CloudAccount(providerId: Self.providerId, accountName: "Local Storage", displayName: "Downloads")
    }
    
    public func disconnect() async throws {
        // No-op for local storage
    }
    
    public func listFolder(folderId: String?, cursor: String?) async throws -> CloudFolderContents {
        let baseDir: URL
        if let folderPath = folderId, !folderPath.isEmpty {
            baseDir = URL(fileURLWithPath: folderPath)
        } else {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "LocalStorageProvider", code: 404, userInfo: [NSLocalizedDescriptionKey: "Document directory not found"])
            }
            baseDir = docs.appendingPathComponent("Downloads")
            if !FileManager.default.fileExists(atPath: baseDir.path) {
                try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            }
        }
        
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        
        guard let fileURLs = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            return CloudFolderContents(items: [])
        }
        
        let items: [CloudFileItem] = fileURLs.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
            let isDir = values.isDirectory ?? false
            let size = UInt64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate
            let createDate = values.creationDate
            
            return CloudFileItem(
                id: url.path,
                providerId: Self.providerId,
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
        }
        
        return CloudFolderContents(items: items)
    }
    
    public func getStreamURL(for item: CloudFileItem) async throws -> URL {
        if let localURL = item.localURL {
            return localURL
        }
        return URL(fileURLWithPath: item.path)
    }
    
    public func download(item: CloudFileItem, progress: @escaping (Double) -> Void) async throws -> URL {
        progress(1.0)
        return try await getStreamURL(for: item)
    }
    
    public func search(query: String) async throws -> [CloudFileItem] {
        let root = try await listFolder(folderId: nil, cursor: nil)
        return root.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    public func delete(item: CloudFileItem) async throws {
        let url = item.localURL ?? URL(fileURLWithPath: item.path)
        try FileManager.default.removeItem(at: url)
    }
}

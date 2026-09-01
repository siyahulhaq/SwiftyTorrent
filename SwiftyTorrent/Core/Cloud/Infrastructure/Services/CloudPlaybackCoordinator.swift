//
//  CloudPlaybackCoordinator.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import MediaKit

public final class CloudPlaybackCoordinator {
    public static let shared = CloudPlaybackCoordinator()
    
    private init() {}
    
    public func prepareForPlayback(
        item: CloudFileItem,
        provider: CloudStorageProviderProtocol
    ) async throws -> PreviewItem {
        print("[CloudPlaybackCoordinator] prepareForPlayback: '\(item.name)', isPlayableMedia=\(item.isPlayableMedia), mimeType=\(item.mimeType ?? "nil")")
        
        // If file is strictly from on-device local app sandbox downloads, use it directly
        if item.providerId == LocalStorageProvider.providerId,
           let localURL = item.localURL,
           FileManager.default.fileExists(atPath: localURL.path) {
            print("[CloudPlaybackCoordinator] Using existing local storage URL: \(localURL)")
            return item
        }
        
        // If file was previously downloaded to on-device Downloads, use it directly
        if let downloadedLocalURL = await CloudDownloadManager.shared.localFileURL(for: item) {
            print("[CloudPlaybackCoordinator] Using already downloaded local URL: \(downloadedLocalURL)")
            return CloudFileItem(
                id: item.id,
                providerId: item.providerId,
                accountId: item.accountId,
                name: item.name,
                path: item.path,
                size: item.size,
                isDirectory: item.isDirectory,
                mimeType: item.mimeType,
                localURL: downloadedLocalURL,
                remoteURL: nil,
                streamHeaders: item.streamHeaders,
                isDownloads: true,
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt
            )
        }
        
        if item.isPlayableMedia {
            print("[CloudPlaybackCoordinator] Resolving streaming URL via provider...")
            let streamURL = try await provider.getStreamURL(for: item)
            print("[CloudPlaybackCoordinator] Streaming URL obtained: \(streamURL)")
            return CloudFileItem(
                id: item.id,
                providerId: item.providerId,
                accountId: item.accountId,
                name: item.name,
                path: item.path,
                size: item.size,
                isDirectory: item.isDirectory,
                mimeType: item.mimeType,
                localURL: streamURL.isFileURL ? streamURL : nil,
                remoteURL: streamURL.isFileURL ? nil : streamURL,
                streamHeaders: item.streamHeaders,
                isDownloads: item.isDownloads,
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt,
                accessedAt: item.accessedAt
            )
        } else {
            print("[CloudPlaybackCoordinator] Downloading non-media file for QuickLook...")
            let cachedLocalURL = try await provider.download(item: item, progress: { _ in })
            print("[CloudPlaybackCoordinator] Downloaded to: \(cachedLocalURL)")
            return CloudFileItem(
                id: item.id,
                providerId: item.providerId,
                accountId: item.accountId,
                name: cachedLocalURL.lastPathComponent,
                path: cachedLocalURL.path,
                size: item.size,
                isDirectory: item.isDirectory,
                mimeType: item.mimeType,
                localURL: cachedLocalURL,
                remoteURL: nil,
                streamHeaders: nil,
                isDownloads: false,
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt,
                accessedAt: item.accessedAt
            )
        }
    }
}

//
//  CloudFileItem.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import MediaKit

public final class CloudFileItem: NSObject, Identifiable, FileProtocol, PreviewItem {
    public let id: String
    public let providerId: String
    public let accountId: String?
    public let name: String
    public let path: String
    public let size: UInt64
    public let isDirectory: Bool
    public let mimeType: String?
    public let localURL: URL?
    public let remoteURL: URL?
    public let streamHeaders: [String: String]?
    public var isDownloads: Bool
    
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var accessedAt: Date?
    
    public func recursiveDescription(_ level: Int) {
        let tab = String(repeating: "\t", count: level)
        print(tab + "⎜" + description)
    }
    
    public var title: String { name }
    
    public var sizeDetails: String? {
        if isDirectory {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    public var previewItemURL: URL? {
        return localURL ?? remoteURL
    }
    
    public var previewItemTitle: String? {
        return name
    }
    
    public var isPlayableMedia: Bool {
        if isDirectory { return false }
        
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ext = (cleanName as NSString).pathExtension
        
        let mediaExtensions: Set<String> = [
            // Video
            "mkv", "mp4", "m4v", "mov", "avi", "wmv", "flv", "webm", "ts", "m2ts", "vob",
            "3gp", "mpg", "mpeg", "m2v", "ogv", "divx", "asf", "rm", "rmvb", "iso", "dat",
            "f4v", "h264", "h265", "hevc", "264", "265", "nut", "nsv",
            // Audio
            "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma", "aiff", "alac", "ac3", "dts", "eac3", "mka"
        ]
        
        if mediaExtensions.contains(ext) {
            return true
        }
        
        if let mime = mimeType?.lowercased() {
            if mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime.contains("matroska") || (mime.contains("octet-stream") && (cleanName.contains(".mkv") || cleanName.contains(".mp4"))) {
                return true
            }
        }
        
        return false
    }
    
    public init(
        id: String = UUID().uuidString,
        providerId: String,
        accountId: String? = nil,
        name: String,
        path: String,
        size: UInt64 = 0,
        isDirectory: Bool = false,
        mimeType: String? = nil,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        streamHeaders: [String: String]? = nil,
        isDownloads: Bool = false,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        accessedAt: Date? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.accountId = accountId
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.mimeType = mimeType
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.streamHeaders = streamHeaders
        self.isDownloads = isDownloads
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.accessedAt = accessedAt
        super.init()
    }
    
    public override var description: String {
        return "\(isDirectory ? "📁" : "📄") \(name) (\(sizeDetails ?? "folder"))"
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CloudFileItem else { return false }
        return self.id == other.id && self.providerId == other.providerId
    }
    
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(providerId)
        return hasher.finalize()
    }
}

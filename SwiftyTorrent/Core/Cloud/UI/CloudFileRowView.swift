//
//  CloudFileRowView.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import SwiftUI

private let cloudDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

public struct CloudFileRowView: View {
    public let item: CloudFileItem
    public var dateSortField: FileSortField? = nil
    public var isPreparing: Bool = false
    
    public init(item: CloudFileItem, dateSortField: FileSortField? = nil, isPreparing: Bool = false) {
        self.item = item
        self.dateSortField = dateSortField
        self.isPreparing = isPreparing
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .frame(width: 32, height: 32)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let details = detailsText {
                    Text(details)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isPreparing {
                ProgressView()
                    .scaleEffect(0.85)
            } else if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .padding(.vertical, 3)
    }
    
    private var detailsText: String? {
        var parts: [String] = []
        
        if let size = item.sizeDetails {
            parts.append(size)
        }
        
        let dateToDisplay: Date?
        switch dateSortField {
        case .dateModified:
            dateToDisplay = item.modifiedAt
        case .dateCreated:
            dateToDisplay = item.createdAt
        case .dateOpened:
            dateToDisplay = item.accessedAt
        default:
            dateToDisplay = item.modifiedAt ?? item.createdAt
        }
        
        if let date = dateToDisplay {
            parts.append(cloudDateFormatter.string(from: date))
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
    
    private var iconName: String {
        if item.isDirectory {
            return "folder.fill"
        }
        
        let ext = (item.name as NSString).pathExtension.lowercased()
        if isVideoExtension(ext) || item.mimeType?.hasPrefix("video/") == true {
            return "play.rectangle.fill"
        } else if isAudioExtension(ext) || item.mimeType?.hasPrefix("audio/") == true {
            return "music.note"
        } else if isImageExtension(ext) || item.mimeType?.hasPrefix("image/") == true {
            return "photo.fill"
        } else if isDocumentExtension(ext) || item.mimeType?.hasPrefix("text/") == true || item.mimeType?.contains("pdf") == true || item.mimeType?.contains("google-apps") == true {
            return "doc.text.fill"
        } else if isArchiveExtension(ext) {
            return "doc.zipper"
        }
        return "doc.fill"
    }
    
    private var iconColor: Color {
        if item.isDirectory {
            return .blue
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if isVideoExtension(ext) || item.mimeType?.hasPrefix("video/") == true {
            return .purple
        } else if isAudioExtension(ext) || item.mimeType?.hasPrefix("audio/") == true {
            return .pink
        } else if isImageExtension(ext) || item.mimeType?.hasPrefix("image/") == true {
            return .teal
        } else if isDocumentExtension(ext) || item.mimeType?.hasPrefix("text/") == true || item.mimeType?.contains("pdf") == true || item.mimeType?.contains("google-apps") == true {
            return .orange
        } else if isArchiveExtension(ext) {
            return .yellow
        }
        return .secondary
    }
    
    private func isVideoExtension(_ ext: String) -> Bool {
        ["mp4", "m4v", "mov", "mkv", "avi", "wmv", "flv", "webm", "ts", "m2ts", "vob", "3gp", "mpg", "mpeg", "ogv", "divx", "asf", "rm", "rmvb", "iso"].contains(ext)
    }
    
    private func isAudioExtension(_ ext: String) -> Bool {
        ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma", "aiff", "alac"].contains(ext)
    }
    
    private func isImageExtension(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "bmp", "tiff", "svg"].contains(ext)
    }
    
    private func isDocumentExtension(_ ext: String) -> Bool {
        ["pdf", "doc", "docx", "txt", "epub", "pages", "xls", "xlsx", "ppt", "pptx", "rtf", "md", "json", "csv", "xml", "html"].contains(ext)
    }
    
    private func isArchiveExtension(_ ext: String) -> Bool {
        ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "torrent"].contains(ext)
    }
}

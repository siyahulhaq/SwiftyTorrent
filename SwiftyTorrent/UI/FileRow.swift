//
//  FileRow.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/16/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

import SwiftUI

private let fileDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

struct FileRow: View {
    
    var model: FileRowModel
    var dateSortField: FileSortField? = nil
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 26))
                .frame(width: 32, height: 32)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let details = detailsText {
                    Text(details)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
    
    private var detailsText: String? {
        let fileProtocol = model as? FileProtocol
        let dateToDisplay: Date?
        
        switch dateSortField {
        case .dateModified:
            dateToDisplay = fileProtocol?.modifiedAt
        case .dateCreated:
            dateToDisplay = fileProtocol?.createdAt
        case .dateOpened:
            dateToDisplay = fileProtocol?.accessedAt
        default:
            dateToDisplay = nil
        }
        
        var datePrefix = ""
        if let date = dateToDisplay {
            datePrefix = "\(fileDateFormatter.string(from: date)) • "
        }
        
        if let dir = model as? Directory {
            let count = dir.files.count
            let countStr = count == 1 ? "1 item" : "\(count) items"
            if dir.size > 0 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(dir.size), countStyle: .file)
                return "\(datePrefix)\(countStr) • \(sizeStr)"
            }
            return "\(datePrefix)\(countStr)"
        }
        
        if let sizeDetails = model.sizeDetails {
            return "\(datePrefix)\(sizeDetails)"
        }
        
        if let date = dateToDisplay {
            return fileDateFormatter.string(from: date)
        }
        
        return nil
    }
    
    private var iconName: String {
        if model.isDirectory {
            return "folder.fill"
        }
        if let file = model as? File {
            if file.isVideo {
                return "play.circle.fill"
            }
            if file.isImage {
                return "photo.circle.fill"
            }
            let ext = URL(fileURLWithPath: file.path).pathExtension.lowercased()
            if ["mp3", "m4a", "flac", "aac", "wav", "ogg", "alac"].contains(ext) {
                return "music.note"
            }
            if ["pdf", "doc", "docx", "txt", "pages", "rtf", "md"].contains(ext) {
                return "doc.text.fill"
            }
            if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
                return "doc.zipper"
            }
        }
        return "doc.fill"
    }
    
    private var iconColor: Color {
        if model.isDirectory {
            return .blue
        }
        if let file = model as? File {
            if file.isVideo {
                return .orange
            }
            if file.isImage {
                return .purple
            }
            let ext = URL(fileURLWithPath: file.path).pathExtension.lowercased()
            if ["mp3", "m4a", "flac", "aac", "wav", "ogg", "alac"].contains(ext) {
                return .pink
            }
            if ["pdf", "doc", "docx", "txt", "pages", "rtf", "md"].contains(ext) {
                return .blue
            }
            if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
                return .yellow
            }
        }
        return .secondary
    }
}

//
//  File.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/17/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

import Foundation
import TorrentKit

enum FileCategory: Int, Comparable {
    case folder = 0
    case video = 1
    case audio = 2
    case image = 3
    case document = 4
    case other = 5
    
    static func < (lhs: FileCategory, rhs: FileCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

protocol FileProtocol: FileRowModel {
    var name: String { get }
    var path: String { get }
    var size: UInt64 { get }
    var createdAt: Date? { get }
    var modifiedAt: Date? { get }
    var accessedAt: Date? { get }
    var isDirectory: Bool { get }
    var isDownloads: Bool { get set }
    func recursiveDescription(_ level: Int)
}

extension FileProtocol {
    var title: String { name }
    
    var fileCategory: FileCategory {
        if isDirectory {
            return .folder
        }
        if let file = self as? File {
            if file.isVideo { return .video }
            if file.isImage { return .image }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            if ["mp3", "m4a", "flac", "aac", "wav", "ogg", "alac", "wma"].contains(ext) {
                return .audio
            }
            if ["pdf", "doc", "docx", "txt", "epub", "pages", "xls", "xlsx", "ppt", "pptx", "rtf", "md"].contains(ext) {
                return .document
            }
        }
        return .other
    }
}

public class File: NSObject, FileProtocol {

    let name: String
    let path: String
    let size: UInt64
    var sizeDetails: String?
    
    var createdAt: Date?
    var modifiedAt: Date?
    var accessedAt: Date?
    
    var isDirectory: Bool { false }
    var isDownloads: Bool
    
    init(name: String, path: String, size: UInt64, isDownloads: Bool = true, createdAt: Date? = nil, modifiedAt: Date? = nil, accessedAt: Date? = nil) {
        self.name = name
        self.path = path
        self.size = size
        self.sizeDetails = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        self.isDownloads = isDownloads
        
        if createdAt != nil || modifiedAt != nil || accessedAt != nil {
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.accessedAt = accessedAt
        } else {
            let fileURL = URL(fileURLWithPath: path)
            if let vals = try? fileURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .contentAccessDateKey]) {
                self.createdAt = vals.creationDate
                self.modifiedAt = vals.contentModificationDate
                self.accessedAt = vals.contentAccessDate
            } else if let attr = try? FileManager.default.attributesOfItem(atPath: path) {
                self.createdAt = attr[.creationDate] as? Date
                self.modifiedAt = attr[.modificationDate] as? Date
                self.accessedAt = self.modifiedAt ?? self.createdAt
            }
        }
    }
    
    public override var description: String {
        return name
    }
    
    func recursiveDescription(_ level: Int) {
        let tab = String(repeating: "\t", count: level)
        print(tab + "⎜" + description)
    }
}

extension File: Identifiable {
    public var id: String { path }
}

public class Directory: FileProtocol, CustomStringConvertible {
    
    let name: String
    let path: String
    var sizeDetails: String?
    var isDownloads: Bool

    var files: [FileProtocol]
    
    var isDirectory: Bool { true }
    
    var size: UInt64 {
        files.reduce(0) { $0 + $1.size }
    }
    
    var createdAt: Date? {
        if let attr = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attr[.creationDate] as? Date {
            return date
        }
        return files.compactMap { $0.createdAt }.min()
    }
    
    var modifiedAt: Date? {
        if let attr = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attr[.modificationDate] as? Date {
            return date
        }
        return files.compactMap { $0.modifiedAt }.max()
    }
    
    var accessedAt: Date? {
        let fileURL = URL(fileURLWithPath: path)
        if let vals = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey]),
           let date = vals.contentAccessDate {
            return date
        }
        return files.compactMap { $0.accessedAt }.max()
    }
    
    var allSubDirectories: [Directory] {
        return files.compactMap { $0 as? Directory }
    }
    
    var allFiles: [File] {
        return files.compactMap { $0 as? File }
    }
    
    init(name: String, path: String, files: [FileProtocol]? = nil, isDownloads: Bool = true) {
        self.name = name
        self.path = path
        self.files = files ?? []
        self.isDownloads = isDownloads
    }
    
    public var description: String {
        return name
    }
    
    func recursiveDescription(_ level: Int) {
        let tab = String(repeating: "\t", count: level)
        print(tab + "⎣" + description)
        
        func nameOrder(lhs: FileProtocol, rhs: FileProtocol) -> Bool {
            return lhs.name < rhs.name
        }
        
        for dir in allSubDirectories.sorted(by: nameOrder) {
            dir.recursiveDescription(level + 1)
        }
        
        for file in allFiles.sorted(by: nameOrder) {
            file.recursiveDescription(level + 1)
        }
    }
    
    class func directory(from fileEntries: [FileEntry]) -> Directory {
        let rootDir = Directory(name: "/", path: "")
        for fileEntry in fileEntries {
            var lastDir = rootDir
            let filePath = fileEntry.path
            let components = filePath.components(separatedBy: "/")
            for (idx, component) in components.enumerated() {
                let isLast = (idx == components.count - 1)
                let path = lastDir.path + "/" + component
                if isLast {
                    let file = File(name: component, path: path, size: fileEntry.size)
                    lastDir.files.append(file)
                } else {
                    var dir: Directory! = lastDir.files.first(where: { $0.name == component }) as? Directory
                    if dir == nil {
                        dir = Directory(name: component, path: path)
                        lastDir.files.append(dir)
                    }
                    lastDir = dir
                }
            }
        }
        return rootDir
    }
    
    class func directory(with path: String) -> Directory {
        let fileName = (path as NSString).lastPathComponent
        let rootDir = Directory(name: fileName, path: path, isDownloads: false)
        let fileManager = FileManager.default
        
        if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
            for item in contents {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        let subDir = directory(with: fullPath)
                        rootDir.files.append(subDir)
                    } else {
                        let fileURL = URL(fileURLWithPath: fullPath)
                        var size: UInt64 = 0
                        var created: Date? = nil
                        var modified: Date? = nil
                        var accessed: Date? = nil
                        
                        if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentAccessDateKey]) {
                            size = UInt64(vals.fileSize ?? 0)
                            created = vals.creationDate
                            modified = vals.contentModificationDate
                            accessed = vals.contentAccessDate
                        } else if let attr = try? fileManager.attributesOfItem(atPath: fullPath) {
                            size = attr[.size] as? UInt64 ?? 0
                            created = attr[.creationDate] as? Date
                            modified = attr[.modificationDate] as? Date
                            accessed = modified ?? created
                        }
                        let file = File(name: item, path: fullPath, size: size, isDownloads: false, createdAt: created, modifiedAt: modified, accessedAt: accessed)
                        rootDir.files.append(file)
                    }
                }
            }
        }
        return rootDir
    }
}

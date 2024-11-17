//
//  File.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 7/17/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import Foundation
import TorrentKit

protocol FileProtocol: FileRowModel {

    var name: String { get }
    
    var path: String { get }
    
    func recursiveDescription(_ level: Int)
    
    var isDownloads: Bool { get set }
    
}

extension FileProtocol {
    
    var title: String { name }

}

public class File: NSObject, FileProtocol {

    let name: String
    let path: String
    var sizeDetails: String?
    
    var isDirectory: Bool { false }
    var isDownloads: Bool
    
    init(name: String, path: String, size: UInt64, isDownloads: Bool = true) {
        self.name = name
        self.path = path
        self.sizeDetails = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        self.isDownloads = isDownloads
        
    }
    
    public override var description: String {
        return name //+ " (\(path))"
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
    
    var allSubDirectories: [Directory] {
        //swiftlint:disable:next force_cast
        return files.filter({ type(of: $0) == Directory.self }) as! [Directory]
    }
    
    var allFiles: [File] {
        //swiftlint:disable:next force_cast
        return files.filter({ type(of: $0) == File.self }) as! [File]
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
        
        // print all subdiectories first
        func nameOrder(lhs: FileProtocol, rhs: FileProtocol) -> Bool {
            return lhs.name < rhs.name
        }
        
        for dir in allSubDirectories.sorted(by: nameOrder) {
            dir.recursiveDescription(level + 1)
        }
        
        // all files after
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
                        let subDir = directory(with: fullPath) // Recursive call for subdirectories
                        rootDir.files.append(subDir)
                    } else {
                        let attr = try? fileManager.attributesOfItem(atPath: fullPath)
                        let size = attr?[FileAttributeKey.size] as? UInt64 ?? 0
                        let file = File(name: item, path: fullPath, size: size, isDownloads: false)
                        rootDir.files.append(file)
                    }
                }
            }
        }
        return rootDir
    }
    
}

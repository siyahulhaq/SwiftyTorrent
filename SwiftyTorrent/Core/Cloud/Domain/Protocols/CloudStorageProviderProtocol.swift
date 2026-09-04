//
//  CloudStorageProviderProtocol.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

#if canImport(UIKit)
import UIKit
public typealias PlatformViewController = UIViewController
#elseif canImport(AppKit)
import AppKit
public typealias PlatformViewController = NSViewController
#endif
import Foundation

public struct CloudFolderContents {
    public let items: [CloudFileItem]
    public let nextCursor: String?
    public let currentFolder: CloudFileItem?
    
    public init(items: [CloudFileItem], nextCursor: String? = nil, currentFolder: CloudFileItem? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.currentFolder = currentFolder
    }
}

public protocol CloudStorageProviderProtocol: AnyObject {
    var descriptor: CloudProviderDescriptor { get }
    var account: CloudAccount? { get set }
    
    func authenticate(from presentingVC: PlatformViewController?) async throws -> CloudAccount
    func disconnect() async throws
    
    func listFolder(folderId: String?, cursor: String?) async throws -> CloudFolderContents
    func getStreamURL(for item: CloudFileItem) async throws -> URL
    func download(item: CloudFileItem, progress: @escaping (Double) -> Void) async throws -> URL
    func search(query: String) async throws -> [CloudFileItem]
    func delete(item: CloudFileItem) async throws
}

public extension CloudStorageProviderProtocol {
    func search(query: String) async throws -> [CloudFileItem] {
        let contents = try await listFolder(folderId: nil, cursor: nil)
        return contents.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    func delete(item: CloudFileItem) async throws {
        throw NSError(domain: "CloudStorageProvider", code: 405, userInfo: [NSLocalizedDescriptionKey: "Deletion is not supported by this provider."])
    }
}

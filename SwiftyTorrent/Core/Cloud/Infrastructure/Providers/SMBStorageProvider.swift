//
//  SMBStorageProvider.swift
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

public final class SMBStorageProvider: CloudStorageProviderProtocol {
    public static let providerId = "smb"
    
    public var descriptor: CloudProviderDescriptor {
        CloudProviderDescriptor(
            id: Self.providerId,
            displayName: "SMB / Windows Share",
            subtitle: "Local Network & NAS Storage",
            iconName: "server.rack",
            brandColorHex: "5856D6",
            authType: .credentials(requiredFields: [
                CloudCredentialField(id: "host", label: "Server / Host", placeholder: "192.168.1.100 or nas.local"),
                CloudCredentialField(id: "share", label: "Share Name", placeholder: "Optional: leave blank for all shares"),
                CloudCredentialField(id: "username", label: "Username", placeholder: "Optional for Guest"),
                CloudCredentialField(id: "password", label: "Password", placeholder: "Optional for Guest", isSecure: true)
            ]),
            capabilities: [.streaming, .downloading, .uploading, .deletion, .search]
        )
    }
    
    public var account: CloudAccount?
    private var cachedClients: [String: SMBClient] = [:]
    private let clientLock = NSLock()
    
    public init(account: CloudAccount? = nil) {
        self.account = account
    }
    
    // MARK: - Configuration & Client Management
    
    private func getBaseSMBConfiguration() throws -> SMBConfiguration {
        guard let account = account else {
            throw NSError(domain: "SMBStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "No SMB account configured."])
        }
        
        let props = account.customProperties
        guard let host = props["host"], !host.isEmpty else {
            throw NSError(domain: "SMBStorageProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Server host is required."])
        }
        
        let share = props["share"] ?? ""
        let port = UInt16(props["port"] ?? "445") ?? 445
        let basePath = props["basePath"] ?? ""
        let username = props["username"] ?? ""
        let password = props["password"] ?? ""
        let domain = props["domain"] ?? ""
        let isGuest = (props["isGuest"] == "true") || username.isEmpty
        
        return SMBConfiguration(
            host: host,
            port: port,
            share: share,
            basePath: basePath,
            username: username,
            password: password,
            domain: domain,
            isGuest: isGuest
        )
    }
    
    private func getClient(forShare share: String) throws -> SMBClient {
        clientLock.lock()
        defer { clientLock.unlock() }
        
        if let existing = cachedClients[share] {
            return existing
        }
        let baseConfig = try getBaseSMBConfiguration()
        let config = SMBConfiguration(
            host: baseConfig.host,
            port: baseConfig.port,
            share: share,
            basePath: "",
            username: baseConfig.username,
            password: baseConfig.password,
            domain: baseConfig.domain,
            isGuest: baseConfig.isGuest
        )
        let client = SMBClient(config: config)
        cachedClients[share] = client
        return client
    }
    
    private func getRootClient() throws -> SMBClient {
        return try getClient(forShare: "IPC$")
    }
    
    private func parsePath(_ path: String, configuredShare: String) -> (share: String, subpath: String)? {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        if !configuredShare.isEmpty {
            return (configuredShare, clean)
        }
        
        if clean.isEmpty {
            return nil
        }
        
        let components = clean.components(separatedBy: "/")
        guard let first = components.first, !first.isEmpty else {
            return nil
        }
        
        let share = first
        let subpath = components.dropFirst().joined(separator: "/")
        return (share, subpath)
    }
    
    // MARK: - CloudStorageProviderProtocol
    
    public func authenticate(from presentingVC: PlatformViewController?) async throws -> CloudAccount {
        guard let account = self.account else {
            throw NSError(domain: "SMBStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Please enter your SMB server credentials."])
        }
        
        let baseConfig = try getBaseSMBConfiguration()
        let configuredShare = baseConfig.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        if configuredShare.isEmpty {
            let rootClient = try getRootClient()
            _ = try await rootClient.listAvailableShares()
        } else {
            let client = try getClient(forShare: configuredShare)
            try await client.connect()
            _ = try await client.listDirectory(path: "")
        }
        
        return account
    }
    
    public func disconnect() async throws {
        clientLock.lock()
        for (_, client) in cachedClients {
            client.disconnect()
        }
        cachedClients.removeAll()
        clientLock.unlock()
        
        if let account = self.account {
            CloudAccountManager.shared.delete(account: account)
            self.account = nil
        }
    }
    
    public func listFolder(folderId: String?, cursor: String?) async throws -> CloudFolderContents {
        let baseConfig = try getBaseSMBConfiguration()
        let configuredShare = baseConfig.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        let requestedPath = (folderId ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        // 1. Root level when no share is configured: enumerate all shares as directories
        if configuredShare.isEmpty && requestedPath.isEmpty {
            let rootClient = try getRootClient()
            let availableShares = try await rootClient.listAvailableShares()
            
            let shareItems: [CloudFileItem] = availableShares.map { shareName in
                CloudFileItem(
                    id: "smb_\(baseConfig.host)_\(shareName)".replacingOccurrences(of: "/", with: "_"),
                    providerId: Self.providerId,
                    accountId: self.account?.id,
                    name: shareName,
                    path: shareName,
                    size: 0,
                    isDirectory: true,
                    localURL: nil,
                    remoteURL: nil,
                    isDownloads: false
                )
            }
            return CloudFolderContents(items: shareItems)
        }
        
        // 2. Folder listing inside a share
        guard let (share, subpath) = parsePath(requestedPath, configuredShare: configuredShare) else {
            return CloudFolderContents(items: [])
        }
        
        let client = try getClient(forShare: share)
        let entries = try await client.listDirectory(path: subpath)
        
        let authPart: String
        if !baseConfig.isGuest && !baseConfig.username.isEmpty {
            let userEnc = baseConfig.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? baseConfig.username
            let passEnc = baseConfig.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? baseConfig.password
            authPart = "\(userEnc):\(passEnc)@"
        } else {
            authPart = ""
        }
        
        let items: [CloudFileItem] = entries.map { entry in
            let fullItemPath: String
            if configuredShare.isEmpty {
                fullItemPath = subpath.isEmpty ? "\(share)/\(entry.name)" : "\(share)/\(subpath)/\(entry.name)"
            } else {
                fullItemPath = subpath.isEmpty ? entry.name : "\(subpath)/\(entry.name)"
            }
            
            let itemStreamId = "smb_\(baseConfig.host)_\(share)_\(fullItemPath)".replacingOccurrences(of: "/", with: "_")
            let itemSubpath = subpath.isEmpty ? entry.name : "\(subpath)/\(entry.name)"
            let smbUrlString = "smb://\(authPart)\(baseConfig.host):\(baseConfig.port)/\(share)/\(itemSubpath)"
            let remoteURL = URL(string: smbUrlString)
            
            return CloudFileItem(
                id: itemStreamId,
                providerId: Self.providerId,
                accountId: self.account?.id,
                name: entry.name,
                path: fullItemPath,
                size: entry.size,
                isDirectory: entry.isDirectory,
                localURL: nil,
                remoteURL: remoteURL,
                isDownloads: false,
                createdAt: entry.createdAt,
                modifiedAt: entry.modifiedAt
            )
        }
        
        return CloudFolderContents(items: items)
    }
    
    public func getStreamURL(for item: CloudFileItem) async throws -> URL {
        let baseConfig = try getBaseSMBConfiguration()
        let configuredShare = baseConfig.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        guard let (share, subpath) = parsePath(item.path, configuredShare: configuredShare) else {
            throw NSError(domain: "SMBStorageProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid file path."])
        }
        
        let authPart: String
        if !baseConfig.isGuest && !baseConfig.username.isEmpty {
            let userEnc = baseConfig.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? baseConfig.username
            let passEnc = baseConfig.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? baseConfig.password
            authPart = "\(userEnc):\(passEnc)@"
        } else {
            authPart = ""
        }
        
        let smbUrlString = "smb://\(authPart)\(baseConfig.host):\(baseConfig.port)/\(share)/\(subpath)"
        if let smbUrl = URL(string: smbUrlString) {
            return smbUrl
        }
        return item.remoteURL ?? URL(string: "smb://\(baseConfig.host)/\(share)/\(subpath)")!
    }
    
    public func download(item: CloudFileItem, progress: @escaping (Double) -> Void) async throws -> URL {
        let baseConfig = try getBaseSMBConfiguration()
        let configuredShare = baseConfig.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        guard let (share, subpath) = parsePath(item.path, configuredShare: configuredShare) else {
            throw NSError(domain: "SMBStorageProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot download directory."])
        }
        
        let client = try getClient(forShare: share)
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CloudPreviews", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cacheDir.path) {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        let destURL = cacheDir.appendingPathComponent(item.name)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        
        try await client.downloadFile(path: subpath, to: destURL, progress: progress)
        return destURL
    }
    
    public func delete(item: CloudFileItem) async throws {
        let baseConfig = try getBaseSMBConfiguration()
        let configuredShare = baseConfig.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        guard let (share, subpath) = parsePath(item.path, configuredShare: configuredShare), !subpath.isEmpty else {
            throw NSError(domain: "SMBStorageProvider", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cannot delete a root share."])
        }
        
        let client = try getClient(forShare: share)
        try await client.deleteItem(path: subpath)
    }
    
    public func search(query: String) async throws -> [CloudFileItem] {
        let contents = try await listFolder(folderId: nil, cursor: nil)
        return contents.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

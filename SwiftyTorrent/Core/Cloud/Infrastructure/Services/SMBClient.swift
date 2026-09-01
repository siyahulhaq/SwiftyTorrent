//
//  SMBClient.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
internal import AMSMB2

// MARK: - SMB Client Models

public struct SMBFileEntry: Identifiable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: UInt64
    public let createdAt: Date?
    public let modifiedAt: Date?
    
    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: UInt64,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct SMBConfiguration {
    public let host: String
    public let port: UInt16
    public let share: String
    public let basePath: String
    public let username: String
    public let password: String
    public let domain: String
    public let isGuest: Bool
    
    public init(
        host: String,
        port: UInt16 = 445,
        share: String,
        basePath: String = "",
        username: String = "",
        password: String = "",
        domain: String = "",
        isGuest: Bool = false
    ) {
        self.host = host
        self.port = port
        self.share = share
        self.basePath = basePath
        self.username = username
        self.password = password
        self.domain = domain
        self.isGuest = isGuest
    }
}

// MARK: - AMSMB2 (SMB2Manager) Powered Client

public final class SMBClient {
    public let config: SMBConfiguration
    private var manager: SMB2Manager?
    private let lock = NSLock()
    private var isConnected = false
    
    public init(config: SMBConfiguration) {
        self.config = config
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Hostname & Bonjour Resolution
    
    public static func resolveHostToIPAddress(_ hostname: String) -> String {
        var trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("smb://") {
            trimmed = String(trimmed.dropFirst(6))
        }
        trimmed = trimmed.components(separatedBy: "/").first ?? trimmed
        trimmed = trimmed.components(separatedBy: ":").first ?? trimmed
        
        if trimmed.isEmpty { return hostname }
        
        // Check if already an IPv4 address
        var sin = sockaddr_in()
        if inet_pton(AF_INET, trimmed, &sin.sin_addr) == 1 {
            return trimmed
        }
        
        // 1. Try getaddrinfo with AF_INET (IPv4)
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(trimmed, nil, &hints, &res) == 0, let first = res {
            defer { freeaddrinfo(res) }
            var current: UnsafeMutablePointer<addrinfo>? = first
            while let ptr = current {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ai_addr, ptr.pointee.ai_addrlen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(cString: hostBuffer)
                    if !ipStr.isEmpty && !ipStr.hasPrefix("127.") {
                        return ipStr
                    }
                }
                current = ptr.pointee.ai_next
            }
        }
        
        // 2. CFHost resolution for Bonjour / .local hostnames
        let hostRef = CFHostCreateWithName(kCFAllocatorDefault, trimmed as CFString).takeRetainedValue()
        var success: DarwinBoolean = false
        if CFHostStartInfoResolution(hostRef, .addresses, nil) {
            if let addresses = CFHostGetAddressing(hostRef, &success)?.takeUnretainedValue() as? [Data] {
                for addrData in addresses {
                    var storage = sockaddr_storage()
                    (addrData as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
                    if storage.ss_family == sa_family_t(AF_INET) {
                        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        let saLen = socklen_t(addrData.count)
                        let resolved = withUnsafePointer(to: &storage) {
                            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                                getnameinfo(sa, saLen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
                            }
                        }
                        if resolved == 0 {
                            let ip = String(cString: hostBuffer)
                            if !ip.isEmpty && !ip.hasPrefix("127.") {
                                return ip
                            }
                        }
                    }
                }
            }
        }
        
        return trimmed
    }
    
    // MARK: - Share Enumeration
    
    public func listAvailableShares() async throws -> [String] {
        var cleanHost = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.lowercased().hasPrefix("smb://") {
            cleanHost = String(cleanHost.dropFirst(6))
        }
        cleanHost = cleanHost.components(separatedBy: "/").first ?? cleanHost
        let resolvedHost = Self.resolveHostToIPAddress(cleanHost)
        
        let urlString = "smb://\(resolvedHost):\(config.port)"
        guard let serverURL = URL(string: urlString) else {
            throw NSError(domain: "SMBClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid host address: \(cleanHost)"])
        }
        
        let isGuestLogin = config.isGuest || config.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let creds: URLCredential? = isGuestLogin ? nil : URLCredential(user: config.username, password: config.password, persistence: .forSession)
        
        let domainsToTry = ["", "WORKGROUP"]
        var lastErr: Error?
        
        for dom in domainsToTry {
            if let mgr = SMB2Manager(url: serverURL, domain: dom, credential: creds) {
                do {
                    let shares = try await mgr.listShares(enumerateHidden: false)
                    return shares.map { $0.name }.filter { !$0.hasSuffix("$") && !$0.isEmpty }
                } catch {
                    lastErr = error
                }
            }
        }
        
        if let err = lastErr {
            throw mapSMBError(err)
        }
        return []
    }
    
    // MARK: - Connection with Smart Authentication Cascade
    
    public func connect() async throws {
        lock.lock()
        if isConnected, let _ = manager {
            lock.unlock()
            return
        }
        lock.unlock()
        
        var cleanHost = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHost.lowercased().hasPrefix("smb://") {
            cleanHost = String(cleanHost.dropFirst(6))
        }
        cleanHost = cleanHost.components(separatedBy: "/").first ?? cleanHost
        
        let cleanShare = config.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        guard !cleanHost.isEmpty else {
            throw NSError(domain: "SMBClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Server host / IP address is required."])
        }
        guard !cleanShare.isEmpty else {
            throw NSError(domain: "SMBClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Share name is required."])
        }
        
        // Resolve host
        let resolvedHost = Self.resolveHostToIPAddress(cleanHost)
        let hostCandidates = resolvedHost != cleanHost ? [resolvedHost, cleanHost] : [resolvedHost]
        
        let isGuestLogin = config.isGuest || config.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        var lastError: Error?
        
        // Build valid domain candidates (NEVER extract IP prefix as domain!)
        var domainCandidates: [String] = ["", "WORKGROUP"]
        
        var sin = sockaddr_in()
        let isIPAddress = inet_pton(AF_INET, cleanHost, &sin.sin_addr) == 1
        if !isIPAddress {
            let hostNameWithoutLocal = cleanHost.replacingOccurrences(of: ".local", with: "").components(separatedBy: ".").first ?? ""
            if !hostNameWithoutLocal.isEmpty && !domainCandidates.contains(hostNameWithoutLocal) {
                domainCandidates.append(hostNameWithoutLocal)
                domainCandidates.append(hostNameWithoutLocal.uppercased())
            }
        }
        
        if !config.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let userDomain = config.domain.trimmingCharacters(in: .whitespacesAndNewlines)
            if !domainCandidates.contains(userDomain) {
                domainCandidates.insert(userDomain, at: 0)
            }
        }
        
        for hostToTry in hostCandidates {
            let baseUrlString = "smb://\(hostToTry):\(config.port)"
            guard let serverURL = URL(string: baseUrlString) else { continue }
            
            if isGuestLogin {
                do {
                    let mgr = try createAndConnectManager(url: serverURL, domain: "", credential: nil, share: cleanShare)
                    lock.lock()
                    self.manager = mgr
                    self.isConnected = true
                    lock.unlock()
                    return
                } catch {
                    lastError = error
                }
            } else {
                let rawUser = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
                var userCandidates: [String] = [rawUser]
                
                let lowerNoSpace = rawUser.lowercased().replacingOccurrences(of: " ", with: "")
                if !userCandidates.contains(lowerNoSpace) {
                    userCandidates.append(lowerNoSpace)
                }
                
                let lower = rawUser.lowercased()
                if !userCandidates.contains(lower) {
                    userCandidates.append(lower)
                }
                
                let firstName = rawUser.components(separatedBy: " ").first?.lowercased() ?? ""
                if !firstName.isEmpty && !userCandidates.contains(firstName) {
                    userCandidates.append(firstName)
                }
                
                for userToTry in userCandidates {
                    let userEnc = userToTry.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? userToTry
                    let passEnc = config.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? config.password
                    let urlWithCreds = URL(string: "smb://\(userEnc):\(passEnc)@\(hostToTry):\(config.port)") ?? serverURL
                    
                    let creds = URLCredential(user: userToTry, password: config.password, persistence: .forSession)
                    
                    for domainToTry in domainCandidates {
                        do {
                            let mgr = try createAndConnectManager(
                                url: urlWithCreds,
                                domain: domainToTry,
                                credential: creds,
                                share: cleanShare
                            )
                            lock.lock()
                            self.manager = mgr
                            self.isConnected = true
                            lock.unlock()
                            return
                        } catch {
                            lastError = error
                        }
                    }
                }
            }
        }
        
        if let err = lastError {
            // Check if user specified a share name that doesn't exist by querying available shares
            if let availableShares = try? await listAvailableShares(), !availableShares.isEmpty {
                if !availableShares.contains(where: { $0.caseInsensitiveCompare(cleanShare) == .orderedSame }) {
                    let list = availableShares.joined(separator: ", ")
                    throw NSError(domain: "SMBClient", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Share '\(cleanShare)' was not found on \(config.host).\n\nAvailable shares on this server:\n\(list)\n\nPlease choose one of the available shares above."
                    ])
                }
            }
            
            throw mapSMBError(err)
        }
        
        throw NSError(domain: "SMBClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to SMB server at \(config.host)."])
    }
    
    private func createAndConnectManager(
        url: URL,
        domain: String,
        credential: URLCredential?,
        share: String
    ) throws -> SMB2Manager {
        guard let smbManager = SMB2Manager(
            url: url,
            domain: domain,
            credential: credential
        ) else {
            throw NSError(domain: "SMBClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not initialize SMB client for \(url.absoluteString)"])
        }
        
        smbManager.timeout = 15.0
        
        var connectError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        smbManager.connectShare(name: share) { error in
            connectError = error
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 15.0)
        
        if let error = connectError {
            throw error
        }
        
        return smbManager
    }
    
    public func disconnect() {
        lock.lock()
        let mgr = self.manager
        self.manager = nil
        self.isConnected = false
        lock.unlock()
        
        Task {
            try? await mgr?.disconnectShare(gracefully: false)
        }
    }
    
    // MARK: - Directory Listing
    
    public func listDirectory(path: String = "") async throws -> [SMBFileEntry] {
        try await connect()
        
        guard let mgr = self.manager else {
            throw NSError(domain: "SMBClient", code: 503, userInfo: [NSLocalizedDescriptionKey: "SMB Client not connected."])
        }
        
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        do {
            let rawEntries = try await mgr.contentsOfDirectory(atPath: cleanPath)
            
            var results: [SMBFileEntry] = []
            for entry in rawEntries {
                guard let name = entry[.nameKey] as? String else { continue }
                if name == "." || name == ".." || name == ".DS_Store" || name.hasPrefix("._") {
                    continue
                }
                
                let isDir = (entry[.isDirectoryKey] as? Bool) ?? false
                let size = (entry[.fileSizeKey] as? NSNumber)?.uint64Value ?? 0
                let createdAt = entry[.creationDateKey] as? Date
                let modifiedAt = entry[.contentModificationDateKey] as? Date
                
                let itemRelativePath = cleanPath.isEmpty ? name : "\(cleanPath)/\(name)"
                
                results.append(SMBFileEntry(
                    name: name,
                    path: itemRelativePath,
                    isDirectory: isDir,
                    size: isDir ? 0 : size,
                    createdAt: createdAt,
                    modifiedAt: modifiedAt
                ))
            }
            
            return results.sorted { a, b in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory && !b.isDirectory
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        } catch {
            throw mapSMBError(error)
        }
    }
    
    // MARK: - Download & Read
    
    public func downloadFile(path: String, to localURL: URL, progress: @escaping (Double) -> Void) async throws {
        try await connect()
        
        guard let mgr = self.manager else {
            throw NSError(domain: "SMBClient", code: 503, userInfo: [NSLocalizedDescriptionKey: "SMB Client not connected."])
        }
        
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        do {
            let data = try await mgr.contents(atPath: cleanPath, progress: { bytes, total in
                if total > 0 {
                    let fraction = min(1.0, Double(bytes) / Double(total))
                    progress(fraction)
                }
                return true
            })
            
            try data.write(to: localURL, options: .atomic)
            progress(1.0)
        } catch {
            throw mapSMBError(error)
        }
    }
    
    public func readFileData(path: String, offset: UInt64, length: UInt32) async throws -> Data {
        try await connect()
        
        guard let mgr = self.manager else {
            throw NSError(domain: "SMBClient", code: 503, userInfo: [NSLocalizedDescriptionKey: "SMB Client not connected."])
        }
        
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        let range = offset..<(offset + UInt64(length))
        
        do {
            return try await mgr.contents(atPath: cleanPath, range: range, progress: nil)
        } catch {
            throw mapSMBError(error)
        }
    }
    
    public func deleteItem(path: String) async throws {
        try await connect()
        
        guard let mgr = self.manager else {
            throw NSError(domain: "SMBClient", code: 503, userInfo: [NSLocalizedDescriptionKey: "SMB Client not connected."])
        }
        
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        
        do {
            try await mgr.removeItem(atPath: cleanPath)
        } catch {
            throw mapSMBError(error)
        }
    }
    
    // MARK: - Human Readable Error Mapping
    
    public func mapSMBError(_ error: Error) -> Error {
        let nsError = error as NSError
        let code = nsError.code
        let domain = nsError.domain
        
        let cleanShare = config.share.trimmingCharacters(in: CharacterSet(charactersIn: "/\\ "))
        let userDisplay = config.username.isEmpty ? "Guest" : config.username
        
        var readableMessage: String
        
        switch code {
        case 1: // EPERM: Operation not permitted
            if config.isGuest || config.username.isEmpty {
                readableMessage = "Authentication failed (Error 1: EPERM).\n\nThe server requires a valid username and password (Guest access is disabled on '\(config.host)')."
            } else {
                readableMessage = """
                Authentication Failed (Error 1: EPERM)

                • Check that username ('\(userDisplay)') and password are correct.
                • Windows PC: If logging in with a Microsoft account, enter your full Microsoft email address or local account name (Windows PIN will NOT work for SMB; use your Microsoft Account password).
                • Mac: macOS requires your short account name and Windows File Sharing enabled in System Settings > General > Sharing > File Sharing > Options.
                """
            }
            
        case 2: // ENOENT: No such file or directory
            readableMessage = "Share '\(cleanShare)' was not found (Error 2: ENOENT).\n\nThe share name '\(cleanShare)' does not exist on server '\(config.host)'. Please tap 'Discover Shares' to choose an existing share."
            
        case 5: // EIO: I/O error
            readableMessage = "I/O Error (Error 5: EIO).\n\nThe SMB server disconnected or returned an I/O communication error. Verify that SMB2/SMB3 is enabled on the server."
            
        case 13: // EACCES: Permission denied
            readableMessage = "Permission denied (Error 13: EACCES).\n\nUser '\(userDisplay)' does not have access permissions for share '\(cleanShare)'."
            
        case 19: // ENODEV: No such device
            readableMessage = "Device not found (Error 19: ENODEV).\n\nCannot locate SMB server at '\(config.host)'. Please verify the IP address or hostname."
            
        case 22: // EINVAL: Invalid argument
            readableMessage = "Invalid parameters (Error 22: EINVAL).\n\nPlease verify that the server address ('\(config.host)') and share name ('\(cleanShare)') are formatted correctly."
            
        case 54: // ECONNRESET: Connection reset by peer
            readableMessage = "Connection reset (Error 54: ECONNRESET).\n\nThe server closed the connection unexpectedly. Check server logs or firewall settings."
            
        case 60: // ETIMEDOUT: Operation timed out
            readableMessage = "Connection timed out (Error 60: ETIMEDOUT).\n\nCould not reach '\(config.host)' on port \(config.port).\n• Ensure your iOS device and Mac/server are connected to the SAME Wi-Fi network."
            
        case 61: // ECONNREFUSED: Connection refused
            readableMessage = "Connection refused (Error 61: ECONNREFUSED).\n\nServer '\(config.host)' is reachable, but port \(config.port) is closed.\n• Ensure SMB File Sharing is turned ON on the server."
            
        case 65: // EHOSTUNREACH: No route to host
            readableMessage = "Host unreachable (Error 65: EHOSTUNREACH).\n\nCannot route to '\(config.host)'. Make sure your device is connected to Wi-Fi and not on a guest network or VPN."
            
        default:
            if !nsError.localizedDescription.isEmpty && !nsError.localizedDescription.contains("The operation couldn’t be completed") {
                readableMessage = "SMB Error (\(code)): \(nsError.localizedDescription)"
            } else {
                readableMessage = "SMB Error (Code \(code), Domain: \(domain)). Please check your server IP, share name, and credentials."
            }
        }
        
        return NSError(domain: "SMBClient", code: code, userInfo: [
            NSLocalizedDescriptionKey: readableMessage,
            NSUnderlyingErrorKey: error
        ])
    }
}

//
//  SMBBonjourBrowser.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 01/09/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import Network

public struct DiscoveredSMBServer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let hostName: String
    public let ipAddress: String?
    public let port: Int
    
    public init(name: String, hostName: String, ipAddress: String? = nil, port: Int = 445) {
        self.id = "\(name)-\(hostName)-\(port)"
        self.name = name
        self.hostName = hostName
        self.ipAddress = ipAddress
        self.port = port
    }
}

public final class SMBBonjourBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published public var discoveredServers: [DiscoveredSMBServer] = []
    @Published public var isSearching = false
    
    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    
    public override init() {
        super.init()
    }
    
    public func startDiscovery() {
        stopDiscovery()
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")
    }
    
    public func stopDiscovery() {
        browser?.stop()
        browser = nil
        for s in resolvingServices {
            s.stop()
        }
        resolvingServices.removeAll()
        isSearching = false
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5.0)
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        DispatchQueue.main.async {
            self.discoveredServers.removeAll { $0.name == service.name }
        }
    }
    
    // MARK: - NetServiceDelegate
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let hostName = sender.hostName ?? "\(name).local"
        let port = sender.port > 0 ? sender.port : 445
        
        var resolvedIP: String?
        if let addresses = sender.addresses {
            for addrData in addresses {
                var storage = sockaddr_storage()
                (addrData as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
                if storage.ss_family == sa_family_t(AF_INET) {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen = socklen_t(addrData.count)
                    let res = withUnsafePointer(to: &storage) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            getnameinfo(sa, saLen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
                        }
                    }
                    if res == 0 {
                        let ip = String(cString: hostBuffer)
                        if !ip.isEmpty && !ip.hasPrefix("127.") {
                            resolvedIP = ip
                            break
                        }
                    }
                }
            }
        }
        
        let server = DiscoveredSMBServer(
            name: name,
            hostName: hostName,
            ipAddress: resolvedIP,
            port: port
        )
        
        DispatchQueue.main.async {
            if !self.discoveredServers.contains(where: { $0.name == server.name }) {
                self.discoveredServers.append(server)
            }
        }
        
        resolvingServices.removeAll { $0 == sender }
    }
    
    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeAll { $0 == sender }
    }
}

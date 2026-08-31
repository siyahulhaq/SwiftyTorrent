//
//  NetworkMonitor.swift
//  SwiftyTorrent
//
//  Monitors network paths and binds torrent traffic to Wi-Fi
//  to strictly prevent mobile/cellular data usage.
//

import Foundation
import Network
import TorrentKit
import Combine

public final class NetworkMonitor: ObservableObject {
    
    public static let shared = NetworkMonitor()
    
    public static let userDefaultsWiFiOnlyKey = "downloadOverWiFiOnly"
    public static let pathDidChangeNotification = Notification.Name("NetworkMonitorPathDidChangeNotification")
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.swiftytorrent.networkmonitor", qos: .utility)
    
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isWiFi: Bool = false
    @Published public private(set) var isCellular: Bool = false
    @Published public private(set) var currentWiFiInterfaceName: String? = nil
    
    public var isWiFiOnlyEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.userDefaultsWiFiOnlyKey) == nil {
            return true // Default: Wi-Fi Only enabled to protect cellular plans
        }
        return UserDefaults.standard.bool(forKey: Self.userDefaultsWiFiOnlyKey)
    }
    
    /// Returns true if downloading is currently allowed based on network state and user preferences
    public var canDownload: Bool {
        if isWiFiOnlyEnabled {
            return isWiFi
        }
        return isConnected
    }
    
    private var isStarted = false
    
    private init() {}
    
    /// Starts monitoring network path changes
    public func startMonitoring() {
        guard !isStarted else { return }
        isStarted = true
        
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let connected = (path.status == .satisfied)
            let usesWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
            let usesCellular = path.usesInterfaceType(.cellular)
            
            var wifiName: String? = nil
            if usesWiFi {
                for iface in path.availableInterfaces {
                    if iface.type == .wifi || iface.type == .wiredEthernet {
                        wifiName = iface.name
                        break
                    }
                }
                if wifiName == nil {
                    wifiName = "en0"
                }
            }
            
            DispatchQueue.main.async {
                self.isConnected = connected
                self.isWiFi = usesWiFi
                self.isCellular = usesCellular
                self.currentWiFiInterfaceName = wifiName
                
                self.applyInterfaceSettings()
                
                NotificationCenter.default.post(
                    name: Self.pathDidChangeNotification,
                    object: self
                )
            }
        }
        
        monitor.start(queue: monitorQueue)
    }
    
    /// Re-evaluates and applies interface binding to TorrentManager
    public func applyInterfaceSettings() {
        let wifiOnly = isWiFiOnlyEnabled
        let wifiName = isWiFi ? (currentWiFiInterfaceName ?? "en0") : nil
        
        TorrentManager.shared().updateNetworkInterfaces(
            wifiOnly: wifiOnly,
            wifiInterfaceName: wifiName
        )
    }
}

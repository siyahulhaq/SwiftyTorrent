//
//  CloudAccountManager.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import Combine

public final class CloudAccountManager: ObservableObject {
    public static let shared = CloudAccountManager()
    
    @Published public private(set) var accounts: [CloudAccount] = []
    
    private let storageKey = "SwiftyTorrent_SavedCloudAccounts_v1"
    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var cachedAccounts: [CloudAccount] = []
    
    private init() {
        loadAccounts()
    }
    
    public func loadAccounts() {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CloudAccount].self, from: data) else {
            self.cachedAccounts = []
            DispatchQueue.main.async {
                self.accounts = []
            }
            return
        }
        self.cachedAccounts = decoded
        let loaded = decoded
        DispatchQueue.main.async {
            self.accounts = loaded
        }
    }
    
    public func save(account: CloudAccount) {
        lock.lock()
        var list = cachedAccounts
        if let index = list.firstIndex(where: { $0.id == account.id }) {
            list[index] = account
        } else {
            list.append(account)
        }
        self.cachedAccounts = list
        lock.unlock()
        persist(list)
    }
    
    public func delete(account: CloudAccount) {
        lock.lock()
        var list = cachedAccounts
        list.removeAll { $0.id == account.id }
        self.cachedAccounts = list
        lock.unlock()
        persist(list)
    }
    
    public func account(for id: String) -> CloudAccount? {
        lock.lock()
        defer { lock.unlock() }
        return cachedAccounts.first { $0.id == id }
    }
    
    public func accounts(forProvider providerId: String) -> [CloudAccount] {
        lock.lock()
        defer { lock.unlock() }
        return cachedAccounts.filter { $0.providerId == providerId }
    }
    
    private func persist(_ list: [CloudAccount]) {
        if Thread.isMainThread {
            self.accounts = list
        } else {
            DispatchQueue.main.async {
                self.accounts = list
            }
        }
        if let encoded = try? JSONEncoder().encode(list) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
}

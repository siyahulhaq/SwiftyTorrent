//
//  CloudProviderRegistry.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation

public final class CloudProviderRegistry {
    public static let shared = CloudProviderRegistry()
    
    public typealias ProviderFactory = (CloudAccount?) -> CloudStorageProviderProtocol
    
    private var descriptors: [String: CloudProviderDescriptor] = [:]
    private var factories: [String: ProviderFactory] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    public func register(descriptor: CloudProviderDescriptor, factory: @escaping ProviderFactory) {
        lock.lock()
        defer { lock.unlock() }
        descriptors[descriptor.id] = descriptor
        factories[descriptor.id] = factory
    }
    
    public var allDescriptors: [CloudProviderDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return Array(descriptors.values).sorted { $0.displayName < $1.displayName }
    }
    
    public func descriptor(for id: String) -> CloudProviderDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return descriptors[id]
    }
    
    public func createProvider(for id: String, account: CloudAccount? = nil) -> CloudStorageProviderProtocol? {
        lock.lock()
        let factory = factories[id]
        lock.unlock()
        return factory?(account)
    }
}

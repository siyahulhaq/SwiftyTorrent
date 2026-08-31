//
//  CloudLocationsViewModel.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import UIKit
import SwiftUI
import Combine

public struct CloudLocationItem: Identifiable, Hashable {
    public let id: String
    public let providerId: String
    public let accountId: String?
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let brandColorHex: String
    public let provider: CloudStorageProviderProtocol
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: CloudLocationItem, rhs: CloudLocationItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class CloudLocationsViewModel: ObservableObject {
    @Published public var locations: [CloudLocationItem] = []
    @Published public var availableDescriptors: [CloudProviderDescriptor] = []
    @Published public var isAuthenticating: Bool = false
    @Published public var errorMessage: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        // Register default providers if not already registered
        registerDefaultProviders()
        
        // Listen to account changes
        CloudAccountManager.shared.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadLocations()
            }
            .store(in: &cancellables)
        
        reloadLocations()
    }
    
    public func registerDefaultProviders() {
        CloudProviderRegistry.shared.register(descriptor: LocalStorageProvider().descriptor) { account in
            LocalStorageProvider(account: account)
        }
        
        CloudProviderRegistry.shared.register(descriptor: ICloudStorageProvider().descriptor) { account in
            ICloudStorageProvider(account: account)
        }
        
        CloudProviderRegistry.shared.register(descriptor: GoogleDriveStorageProvider().descriptor) { account in
            GoogleDriveStorageProvider(account: account)
        }
    }
    
    public func reloadLocations() {
        self.availableDescriptors = CloudProviderRegistry.shared.allDescriptors
        
        var list: [CloudLocationItem] = []
        
        // 1. Always add Local Storage
        if let localProvider = CloudProviderRegistry.shared.createProvider(for: LocalStorageProvider.providerId) {
            list.append(CloudLocationItem(
                id: "location_local",
                providerId: LocalStorageProvider.providerId,
                accountId: nil,
                title: localProvider.descriptor.displayName,
                subtitle: localProvider.descriptor.subtitle,
                iconName: localProvider.descriptor.iconName,
                brandColorHex: localProvider.descriptor.brandColorHex,
                provider: localProvider
            ))
        }
        
        // 2. Add iCloud Drive
        let iCloudAccounts = CloudAccountManager.shared.accounts(forProvider: ICloudStorageProvider.providerId)
        if iCloudAccounts.isEmpty {
            if let defaultICloud = CloudProviderRegistry.shared.createProvider(for: ICloudStorageProvider.providerId) {
                list.append(CloudLocationItem(
                    id: "location_icloud_default",
                    providerId: ICloudStorageProvider.providerId,
                    accountId: nil,
                    title: defaultICloud.descriptor.displayName,
                    subtitle: "Tap to link folder",
                    iconName: defaultICloud.descriptor.iconName,
                    brandColorHex: defaultICloud.descriptor.brandColorHex,
                    provider: defaultICloud
                ))
            }
        } else {
            for account in iCloudAccounts {
                if let provider = CloudProviderRegistry.shared.createProvider(for: ICloudStorageProvider.providerId, account: account) {
                    list.append(CloudLocationItem(
                        id: account.id,
                        providerId: ICloudStorageProvider.providerId,
                        accountId: account.id,
                        title: account.displayName,
                        subtitle: "iCloud Folder",
                        iconName: provider.descriptor.iconName,
                        brandColorHex: provider.descriptor.brandColorHex,
                        provider: provider
                    ))
                }
            }
        }
        
        // 3. Add Google Drive & other registered accounts
        let allAccounts = CloudAccountManager.shared.accounts
        for account in allAccounts where account.providerId != ICloudStorageProvider.providerId {
            if let provider = CloudProviderRegistry.shared.createProvider(for: account.providerId, account: account) {
                list.append(CloudLocationItem(
                    id: account.id,
                    providerId: account.providerId,
                    accountId: account.id,
                    title: account.displayName.isEmpty ? provider.descriptor.displayName : account.displayName,
                    subtitle: account.accountName,
                    iconName: provider.descriptor.iconName,
                    brandColorHex: provider.descriptor.brandColorHex,
                    provider: provider
                ))
            }
        }
        
        self.locations = list
    }
    
    public func addICloudFolder(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            self.errorMessage = "Failed to access security-scoped iCloud folder."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let base64 = bookmarkData.base64EncodedString()
            let folderName = url.lastPathComponent.isEmpty ? "iCloud Drive" : url.lastPathComponent
            
            let account = CloudAccount(
                providerId: ICloudStorageProvider.providerId,
                accountName: folderName,
                displayName: folderName,
                customProperties: [
                    "bookmark": base64,
                    "path": url.path
                ]
            )
            
            CloudAccountManager.shared.save(account: account)
            reloadLocations()
        } catch {
            self.errorMessage = "Could not save iCloud folder bookmark: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    public func connectProvider(_ descriptor: CloudProviderDescriptor, from viewController: UIViewController? = nil) async {
        guard let provider = CloudProviderRegistry.shared.createProvider(for: descriptor.id) else {
            self.errorMessage = "Provider not found."
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        do {
            _ = try await provider.authenticate(from: viewController)
            reloadLocations()
        } catch {
            if (error as NSError).code != 401 { // Don't show error if user cancelled
                self.errorMessage = error.localizedDescription
            }
        }
        
        isAuthenticating = false
    }
    
    public func disconnectAccount(_ accountId: String) {
        if let account = CloudAccountManager.shared.account(for: accountId) {
            CloudAccountManager.shared.delete(account: account)
            reloadLocations()
        }
    }
}

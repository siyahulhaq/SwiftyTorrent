//
//  CloudProviderDescriptor.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation
import SwiftUI

public enum CloudCapability: String, Codable, Hashable, CaseIterable {
    case streaming
    case downloading
    case uploading
    case deletion
    case search
    case resumableTransfer
}

public enum CloudAuthType: Hashable {
    case none
    case documentPicker
    case oauth2(authURL: URL, tokenURL: URL, clientId: String, scopes: [String])
    case credentials(requiredFields: [CloudCredentialField])
}

public struct CloudCredentialField: Identifiable, Hashable {
    public let id: String
    public let label: String
    public let placeholder: String
    public let isSecure: Bool
    
    public init(id: String, label: String, placeholder: String = "", isSecure: Bool = false) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.isSecure = isSecure
    }
}

public struct CloudProviderDescriptor: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let subtitle: String
    public let iconName: String
    public let brandColorHex: String
    public let authType: CloudAuthType
    public let capabilities: Set<CloudCapability>
    
    public init(
        id: String,
        displayName: String,
        subtitle: String,
        iconName: String,
        brandColorHex: String,
        authType: CloudAuthType,
        capabilities: Set<CloudCapability>
    ) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.iconName = iconName
        self.brandColorHex = brandColorHex
        self.authType = authType
        self.capabilities = capabilities
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: CloudProviderDescriptor, rhs: CloudProviderDescriptor) -> Bool {
        lhs.id == rhs.id
    }
}

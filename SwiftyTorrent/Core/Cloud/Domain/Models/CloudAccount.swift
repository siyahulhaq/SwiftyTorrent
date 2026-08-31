//
//  CloudAccount.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 31/08/26.
//  Copyright © 2026 Siyahul Haq. All rights reserved.
//

import Foundation

public struct CloudAccount: Identifiable, Codable, Hashable {
    public let id: String
    public let providerId: String
    public var accountName: String
    public var displayName: String
    public var accessToken: String?
    public var refreshToken: String?
    public var tokenExpiryDate: Date?
    public var customProperties: [String: String]
    public var quotaTotal: UInt64?
    public var quotaUsed: UInt64?
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        providerId: String,
        accountName: String,
        displayName: String,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        tokenExpiryDate: Date? = nil,
        customProperties: [String: String] = [:],
        quotaTotal: UInt64? = nil,
        quotaUsed: UInt64? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerId = providerId
        self.accountName = accountName
        self.displayName = displayName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiryDate = tokenExpiryDate
        self.customProperties = customProperties
        self.quotaTotal = quotaTotal
        self.quotaUsed = quotaUsed
        self.createdAt = createdAt
    }
    
    public var isTokenExpired: Bool {
        guard let tokenExpiryDate = tokenExpiryDate else { return false }
        return Date() >= tokenExpiryDate
    }
}

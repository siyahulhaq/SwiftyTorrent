//
//  Torrent+Cell.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 7/12/19.
//  Copyright © 2019 Siyahul Haq. All rights reserved.
//

import Foundation
import TorrentKit

protocol TorrentRowModel {
    
    var title: String { get }
    
    var statusDetails: String { get }
    
    var connectionDetails: String { get }
    
    var progressPercentage: Double { get }
    
    var downloadedSize: String { get }
    
    var totalSize: String { get }
    
    var downloadSpeed: String { get }
    
    var uploadSpeed: String { get }
    
    var estimatedTimeRemaining: String { get }
    
    var numberOfSeeds: UInt { get }
    
    var numberOfPeers: UInt { get }
    
}

extension Torrent: TorrentRowModel {

    var title: String {
        return name
    }
    
    var statusDetails: String {
        let progressString = String(format: "%0.2f %%", progress * 100)
        return "\(state.symbol) \(state), \(progressString), seeds: \(numberOfSeeds), peers: \(numberOfPeers)"
    }
    
    var connectionDetails: String {
        let downloadRateString = ByteCountFormatter.string(fromByteCount: Int64(downloadRate), countStyle: .binary)
        let uploadRateString = ByteCountFormatter.string(fromByteCount: Int64(uploadRate), countStyle: .binary)
        return "↓ \(downloadRateString), ↑ \(uploadRateString)"
    }
    
    var progressPercentage: Double {
        return progress
    }
    
    var downloadedSize: String {
        // Show checking status for metadata/file checking states
        if state == .downloadingMetadata || state == .checkingFiles || state == .checkingResumeData {
            return "Checking..."
        }
        
        guard hasMetadata, size > 0 else {
            return "N/A"
        }
        
        // Ensure progress is valid (0.0 to 1.0)
        let validProgress = max(0.0, min(1.0, progress))
        let downloaded = Int64(Double(size) * validProgress)
        return ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
    }
    
    var totalSize: String {
        // Show checking status for metadata/file checking states
        if state == .downloadingMetadata || state == .checkingFiles || state == .checkingResumeData {
            return "Checking..."
        }
        
        guard hasMetadata, size > 0 else {
            return "N/A"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var downloadSpeed: String {
        guard downloadRate > 0 else {
            return "0 B/s"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(downloadRate), countStyle: .binary) + "/s"
    }
    
    var uploadSpeed: String {
        guard uploadRate > 0 else {
            return "0 B/s"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(uploadRate), countStyle: .binary) + "/s"
    }
    
    var estimatedTimeRemaining: String {
        guard hasMetadata, size > 0, downloadRate > 0, progress < 1.0 else {
            return "∞"
        }
        
        let remainingBytes = Double(size) * (1.0 - progress)
        let secondsRemaining = Int(remainingBytes / Double(downloadRate))
        
        guard secondsRemaining > 0 else {
            return "0s"
        }
        
        if secondsRemaining < 60 {
            return "\(secondsRemaining)s"
        } else if secondsRemaining < 3600 {
            let minutes = secondsRemaining / 60
            return "\(minutes)m"
        } else if secondsRemaining < 86400 {
            let hours = secondsRemaining / 3600
            let minutes = (secondsRemaining % 3600) / 60
            return "\(hours)h \(minutes)m"
        } else {
            let days = secondsRemaining / 86400
            let hours = (secondsRemaining % 86400) / 3600
            return "\(days)d \(hours)h"
        }
    }

}

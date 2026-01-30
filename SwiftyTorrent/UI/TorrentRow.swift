//
//  TorrentRow.swift
//  SwiftyTorrent
//  
//  Created by Danylo Kostyshyn on 7/13/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import SwiftUI

struct TorrentRow: View {
    
    var model: TorrentRowModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title with completion indicator
            HStack(spacing: 8) {
                Text(model.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                // Show checkmark if completed
                if model.progressPercentage >= 1.0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            
            // Progress Bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(model.progressPercentage), height: 8)
                    }
                }
                .frame(height: 8)
                
                // Progress percentage with loading indicator
                HStack(spacing: 4) {
                    Text(String(format: "%.1f%%", model.progressPercentage * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    // Show loading indicator when checking
                    if model.downloadedSize == "Checking..." {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            
            // Download/Upload Info Row
            HStack(spacing: 16) {
                // Download Speed
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(model.downloadSpeed)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                // Upload Speed
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(model.uploadSpeed)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // Estimated Time
                if model.estimatedTimeRemaining != "∞" {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(model.estimatedTimeRemaining)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .foregroundColor(.secondary)
            
            // Size and Peers Info Row
            HStack(spacing: 16) {
                // Downloaded / Total Size
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.purple)
                        .font(.caption)
                    Text("\(model.downloadedSize) / \(model.totalSize)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // Seeds
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("\(model.numberOfSeeds) seeds")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                // Peers
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("\(model.numberOfPeers) peers")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
}

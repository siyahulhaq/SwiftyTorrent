//
//  Torrents_WidgetLiveActivity.swift
//  Torrents_Widget
//
//  Created by Siyahul Haq on 05/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import ActivityKit
import WidgetKit
import SwiftUI


struct Torrents_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TorrentsWidgetAttributes.self) { context in
            // Lock screen/banner UI
            VStack(spacing: 8) {
                Text(context.attributes.torrentName)
                    .font(.headline)
                    .lineLimit(1)
                
                ProgressView(value: context.state.downloadProgress) {
                    HStack {
                        Text("\(Int(context.state.downloadProgress * 100))%")
                        Spacer()
                        Text(formatBytes(context.attributes.totalSize))
                    }
                    .font(.caption)
                }
                
                HStack {
                    Label {
                        Text(formatSpeed(context.state.downloadSpeed))
                    } icon: {
                        Image(systemName: "arrow.down")
                    }
                    Spacer()
                    Label {
                        Text(formatSpeed(context.state.uploadSpeed))
                    } icon: {
                        Image(systemName: "arrow.up")
                    }
                }
                .font(.caption)
                
                HStack {
                    Label("\(context.state.peers) peers", systemImage: "person.2")
                    Spacer()
                    Label("\(context.state.seeds) seeds", systemImage: "leaf")
                }
                .font(.caption)
                
                Text(context.state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(.black)
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(formatSpeed(context.state.downloadSpeed))
                    } icon: {
                        Image(systemName: "arrow.down")
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Label {
                        Text(formatSpeed(context.state.uploadSpeed))
                    } icon: {
                        Image(systemName: "arrow.up")
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.torrentName)
                        .font(.caption)
                        .lineLimit(1)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.downloadProgress)
                    Text("\(Int(context.state.downloadProgress * 100))%")
                        .font(.caption)
                }
                
            } compactLeading: {
                Image(systemName: "arrow.down")
                Text(formatSpeed(context.state.downloadSpeed))
            } compactTrailing: {
                Text("\(Int(context.state.downloadProgress * 100))%")
            } minimal: {
                Image(systemName: "arrow.down")
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatSpeed(_ bytesPerSec: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

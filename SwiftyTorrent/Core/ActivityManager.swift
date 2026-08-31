//
//  rawActivityManager.swift
//  SwiftyTorrent
//
//  Created by Siyahul Haq on 05/11/24.
//  Copyright © 2024 Danylo Kostyshyn. All rights reserved.
//

import ActivityKit
import Combine
import Foundation
import TorrentKit
import SwiftUI

final class ActivityManager: ObservableObject {
    @MainActor @Published private(set) var activityID: String?
    
    // Map torrentKey (base64 of infoHash) -> Activity ID
    private var activityIDs: [String: String] = [:]
    
    // Track in-flight start requests to prevent duplicate concurrent creations
    private var inFlightStarts = Set<String>()
    
    // Throttle updates per torrent (min 2.5s between updates to respect ActivityKit budget)
    private var lastUpdateTimes: [String: Date] = [:]
    
    private let torrentManager: TorrentManagerProtocol
    @AppStorage("enableBackgroundMode") private var enableBackgroundMode = false

    static let shared = ActivityManager()

    init(torrentManager: TorrentManagerProtocol = TorrentManager.shared()) {
        self.torrentManager = torrentManager
        syncExistingActivities()
    }
    
    /// Syncs and prunes existing system activities on init/lifecycle
    func syncExistingActivities() {
        var seenTorrentNames = Set<String>()
        var seenInfoHashes = Set<String>()
        
        for activity in Activity<TorrentsWidgetAttributes>.activities {
            let infoHash = activity.attributes.infoHash
            let torrentName = activity.attributes.torrentName
            
            // If we've already tracked an activity for this torrent, end the duplicate
            let alreadySeen = (!infoHash.isEmpty && seenInfoHashes.contains(infoHash)) ||
                              seenTorrentNames.contains(torrentName)
            
            if alreadySeen || activity.activityState == .ended || activity.activityState == .dismissed {
                Task {
                    await activity.end(dismissalPolicy: .immediate)
                }
            } else {
                if !infoHash.isEmpty {
                    seenInfoHashes.insert(infoHash)
                    activityIDs[infoHash] = activity.id
                }
                seenTorrentNames.insert(torrentName)
            }
        }
    }
    
    private func findActiveActivity(for torrent: Torrent) -> Activity<TorrentsWidgetAttributes>? {
        let torrentKey = torrent.infoHash.base64EncodedString()
        
        // 1. Check if cached ID is valid and active
        if let cachedID = activityIDs[torrentKey],
           let activity = Activity<TorrentsWidgetAttributes>.activities.first(where: {
               $0.id == cachedID && ($0.activityState == .active || $0.activityState == .stale)
           }) {
            return activity
        }
        
        // 2. Search by infoHash attribute
        if let activity = Activity<TorrentsWidgetAttributes>.activities.first(where: {
            !$0.attributes.infoHash.isEmpty && $0.attributes.infoHash == torrentKey &&
            ($0.activityState == .active || $0.activityState == .stale)
        }) {
            activityIDs[torrentKey] = activity.id
            return activity
        }
        
        // 3. Fallback: Search by torrentName
        if let activity = Activity<TorrentsWidgetAttributes>.activities.first(where: {
            $0.attributes.torrentName == torrent.name &&
            ($0.activityState == .active || $0.activityState == .stale)
        }) {
            activityIDs[torrentKey] = activity.id
            return activity
        }
        
        return nil
    }
    
    private func pruneDuplicates(for torrent: Torrent, keeping keptActivityID: String) async {
        let torrentKey = torrent.infoHash.base64EncodedString()
        let duplicates = Activity<TorrentsWidgetAttributes>.activities.filter { activity in
            guard activity.id != keptActivityID else { return false }
            if !activity.attributes.infoHash.isEmpty && activity.attributes.infoHash == torrentKey {
                return true
            }
            return activity.attributes.torrentName == torrent.name
        }
        
        for duplicate in duplicates {
            await duplicate.end(dismissalPolicy: .immediate)
            print("[ActivityManager] Pruned duplicate activity \(duplicate.id) for \(torrent.name)")
        }
    }

    func startActivity(for torrent: Torrent) async {
        let torrentKey = torrent.infoHash.base64EncodedString()
        
        // 1. If an active activity already exists for this torrent, adopt it and prune any extras
        if let existing = findActiveActivity(for: torrent) {
            activityIDs[torrentKey] = existing.id
            await pruneDuplicates(for: torrent, keeping: existing.id)
            return
        }

        // 2. Prevent concurrent start calls for the same torrent
        guard !inFlightStarts.contains(torrentKey) else {
            return
        }
        inFlightStarts.insert(torrentKey)
        defer { inFlightStarts.remove(torrentKey) }

        guard torrent.hasMetadata else {
            print("[ActivityManager] Waiting for metadata before starting activity for: \(torrent.name)")
            return
        }

        // Double check after guard
        if let existing = findActiveActivity(for: torrent) {
            activityIDs[torrentKey] = existing.id
            return
        }

        let attributes = TorrentsWidgetAttributes(
            torrentName: torrent.name,
            totalSize: torrent.size,
            infoHash: torrentKey
        )

        let initialState = TorrentsWidgetAttributes.ContentState(
            downloadProgress: torrent.progress,
            downloadSpeed: Int(torrent.downloadRate),
            uploadSpeed: Int(torrent.uploadRate),
            peers: Int(torrent.numberOfPeers),
            seeds: Int(torrent.numberOfSeeds),
            status: torrent.state.description
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: nil
            )

            activityIDs[torrentKey] = activity.id
            lastUpdateTimes[torrentKey] = Date()
            await MainActor.run {
                activityID = activity.id
            }
            
            print("[ActivityManager] Started activity with ID: \(activity.id) for torrent: \(torrent.name)")
            
            await pruneDuplicates(for: torrent, keeping: activity.id)
        } catch {
            print("[ActivityManager] Error starting live activity: \(error.localizedDescription)")
        }
    }

    func updateActivity(with torrent: Torrent) async {
        let torrentKey = torrent.infoHash.base64EncodedString()
        
        // If torrent finished, end the activity
        if torrent.progress >= 1.0 {
            await endActivity(for: torrent)
            return
        }

        guard let activity = findActiveActivity(for: torrent) else {
            if torrent.progress < 1.0 && !inFlightStarts.contains(torrentKey) {
                await startActivity(for: torrent)
            }
            return
        }

        activityIDs[torrentKey] = activity.id

        // Throttle updates: ActivityKit rate limits updates. Minimum 2.5s interval
        if let lastUpdate = lastUpdateTimes[torrentKey], Date().timeIntervalSince(lastUpdate) < 2.5 {
            return
        }

        let updatedState = TorrentsWidgetAttributes.ContentState(
            downloadProgress: torrent.progress,
            downloadSpeed: Int(torrent.downloadRate),
            uploadSpeed: Int(torrent.uploadRate),
            peers: Int(torrent.numberOfPeers),
            seeds: Int(torrent.numberOfSeeds),
            status: torrent.state.description
        )

        do {
            let staleDate = Date().addingTimeInterval(300)
            
            try await activity.update(
                ActivityContent(
                    state: updatedState,
                    staleDate: staleDate
                )
            )
            lastUpdateTimes[torrentKey] = Date()
        } catch {
            print("[ActivityManager] Error updating activity: \(error.localizedDescription)")
            // DO NOT create a new activity on update error!
            // Only cleanup if activity is actually ended or dismissed
            if activity.activityState == .ended || activity.activityState == .dismissed {
                activityIDs.removeValue(forKey: torrentKey)
                lastUpdateTimes.removeValue(forKey: torrentKey)
            }
        }
    }

    func endActivity(for torrent: Torrent) async {
        let torrentKey = torrent.infoHash.base64EncodedString()
        
        // Find all activities for this torrent and end them all
        let matchingActivities = Activity<TorrentsWidgetAttributes>.activities.filter { activity in
            if let cachedID = activityIDs[torrentKey], activity.id == cachedID {
                return true
            }
            if !activity.attributes.infoHash.isEmpty && activity.attributes.infoHash == torrentKey {
                return true
            }
            return activity.attributes.torrentName == torrent.name
        }

        for activity in matchingActivities {
            await activity.end(dismissalPolicy: .immediate)
        }
        
        activityIDs.removeValue(forKey: torrentKey)
        lastUpdateTimes.removeValue(forKey: torrentKey)
        
        await MainActor.run {
            if self.activityID != nil && matchingActivities.contains(where: { $0.id == self.activityID }) {
                self.activityID = nil
            }
        }
        
        if !matchingActivities.isEmpty {
            print("[ActivityManager] Ended \(matchingActivities.count) activity(ies) for torrent: \(torrent.name)")
        }
    }

    func endAllActivities() async {
        for activity in Activity<TorrentsWidgetAttributes>.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
        
        activityIDs.removeAll()
        lastUpdateTimes.removeAll()
        inFlightStarts.removeAll()
        await MainActor.run {
            activityID = nil
        }
        
        print("[ActivityManager] Ended all activities")
    }

    func updateBackgroundMode(_ enabled: Bool) {
        enableBackgroundMode = enabled
        BackgroundDownloadManager.shared.updateBackgroundMode(enabled)
    }
}


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
    private var activityIDs: [String: String] = [:]
    private let torrentManager: TorrentManagerProtocol
    @AppStorage("enableBackgroundMode") private var enableBackgroundMode = false

    static let shared = ActivityManager()

    init(torrentManager: TorrentManagerProtocol = TorrentManager.shared()) {
        self.torrentManager = torrentManager
    }

    func startActivity(for torrent: Torrent) async {
        return
        let torrentKey = torrent.infoHash.base64EncodedString()
        if activityIDs[torrentKey] != nil {
            return
        }

        guard torrent.hasMetadata else {
            print("Waiting for metadata before starting activity for: \(torrent.name)")
            return
        }

        let attributes = TorrentsWidgetAttributes(
            torrentName: torrent.name,
            totalSize: torrent.size
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
                contentState: initialState,
                pushType: nil
            )

            activityIDs[torrentKey] = activity.id
            await MainActor.run {
                activityID = activity.id
            }
            
            print("Started activity with ID: \(activity.id) for torrent: \(torrent.name)")

        } catch {
            print("Error starting live activity: \(error.localizedDescription)")
        }
    }

    func updateActivity(with torrent: Torrent) async {
        let torrentKey = torrent.infoHash.base64EncodedString()
        guard let activityID = activityIDs[torrentKey] else {
            if torrent.progress < 1.0 {
                await startActivity(for: torrent)
            }
            return
        }

        guard let activity = Activity<TorrentsWidgetAttributes>
            .activities.first(where: { $0.id == activityID }) else {
            activityIDs.removeValue(forKey: torrentKey)
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
            // Set stale date to 5 minutes from now
            let staleDate = Date().addingTimeInterval(300)
            
            try await activity.update(
                ActivityContent(
                    state: updatedState,
                    staleDate: staleDate
                )
            )
            
            print("Updated activity \(activityID) for torrent: \(torrent.name)")
            print("Progress: \(torrent.progress), Speed: \(torrent.downloadRate)")
        } catch {
            print("Error updating activity: \(error.localizedDescription)")
            
            // If we get an error, try to recreate the activity
            activityIDs.removeValue(forKey: torrentKey)
            if torrent.progress < 1.0 {
                await startActivity(for: torrent)
            }
        }
    }

    func endActivity(for torrent: Torrent) async {
        let torrentKey = torrent.infoHash.base64EncodedString()
        guard let activityID = activityIDs[torrentKey],
              let activity = Activity<TorrentsWidgetAttributes>
                .activities.first(where: { $0.id == activityID }) else {
            return
        }

        do {
            await activity.end(dismissalPolicy: .immediate)
            activityIDs.removeValue(forKey: torrentKey)
            
            if await activityID == self.activityID {
                await MainActor.run {
                    self.activityID = nil
                }
            }
            
            print("Ended activity for torrent: \(torrent.name)")
        } catch {
            print("Error ending activity: \(error.localizedDescription)")
        }
    }

    func endAllActivities() async {
        do {
            for activity in Activity<TorrentsWidgetAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            
            activityIDs.removeAll()
            await MainActor.run {
                activityID = nil
            }
            
            print("Ended all activities")
        } catch {
            print("Error ending all activities: \(error.localizedDescription)")
        }
    }

    func updateBackgroundMode(_ enabled: Bool) {
        enableBackgroundMode = enabled
        if enabled {
            (UIApplication.shared.delegate as? AppDelegate)?.setupBackgroundAudio()
        } else {
            do {
                try (UIApplication.shared.delegate as? AppDelegate)?.audioSession?.setActive(false)
            } catch {
                print("Error \(error)")
            }
            
        }
    }
}

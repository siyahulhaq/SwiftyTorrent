//
//  BindableTorrentManager.swift
//  SwiftyTorrent
//
//  Created by Danylo Kostyshyn on 7/12/19.
//  Copyright © 2019 Danylo Kostyshyn. All rights reserved.
//

import Combine
import SwiftUI
import TorrentKit
import Observation

@available(iOS 17.0, *)
@Observable
final class TorrentsViewModel {
    private(set) var torrents: [Torrent] = []
    var isPresentingRemoveAlert = false
    
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let torrentManager: TorrentManagerProtocol
    private let updateInterval: TimeInterval = 1.0
    
    init(torrentManager: TorrentManagerProtocol = TorrentManager.shared()) {
        self.torrentManager = torrentManager
        setupUpdateTimer()
        setupTorrentUpdates()
    }
    
    private func setupTorrentUpdates() {
        // Use Combine for torrent updates
        Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.reloadData()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.processPendingUpdates()
        }
    }
    
    private func processPendingUpdates() {
        Task {
            reloadData()
        }
    }
    
    private func areArraysEqual(_ current: [Torrent], _ new: [Torrent]) -> Bool {
        guard current.count == new.count else { return false }
        
        // Compare relevant properties that affect UI
        return zip(current, new).allSatisfy { currentTorrent, newTorrent in
            return currentTorrent.infoHash == newTorrent.infoHash &&
            currentTorrent.progress == newTorrent.progress &&
            currentTorrent.state == newTorrent.state &&
            currentTorrent.numberOfPeers == newTorrent.numberOfPeers &&
            currentTorrent.numberOfSeeds == newTorrent.numberOfSeeds &&
            currentTorrent.downloadRate == newTorrent.downloadRate &&
            currentTorrent.uploadRate == newTorrent.uploadRate
        }
    }
    
    func reloadData() {
        guard !isPresentingRemoveAlert else { return }
        
        Task {
            let sortedTorrents = torrentManager.torrents()
                .sorted { $0.name < $1.name }
            
            // Update activities for all incomplete torrents
            for torrent in sortedTorrents where torrent.progress < 1.0 {
                await ActivityManager.shared.updateActivity(with: torrent)
            }
            
            // Only update the torrents array if there are changes
            if !areArraysEqual(torrents, sortedTorrents) {
                torrents = sortedTorrents
            }
        }
    }
    
    // Add this new method to start activities for all downloading torrents
    func startAllActivities() async {
//        await ActivityManager.shared.startActivities()
    }
    
    // Add this method to end all activities
    func endAllActivities() async {
//        await ActivityManager.shared.endAllActivities()
    }
    
    func remove(_ torrent: Torrent, deleteFiles: Bool = false) {
        Task {
            // End the activity before removing the torrent
            await ActivityManager.shared.endActivity(for: torrent)
            
            torrentManager.removeTorrent(withInfoHash: torrent.infoHash,
                                       deleteFiles: deleteFiles)
            reloadData()
        }
    }
    
    func importTorrentFile(from url: URL) {
        Task {
            do {
                let data = try Data(contentsOf: url)
                let torrentFile = TorrentFile()
                torrentManager.add(torrentFile)
                await reloadData()
            } catch {
                print("Error importing torrent file: \(error)")
            }
        }
    }
    
    func importMagnet(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let magnetURI = MagnetURI(magnetURI: url)
        torrentManager.add(magnetURI)
        Task {
            await reloadData()
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
extension TorrentsViewModel {
    
    func addTestTorrentFiles() {
        torrentManager.add(TorrentFile.test_1())
        torrentManager.add(TorrentFile.test_2())
    }
    
    func addTestMagnetLinks() {
        torrentManager.add(MagnetURI.test_1())
    }
    
    func addTestTorrents() {
        addTestTorrentFiles()
        addTestMagnetLinks()
    }
    
}
#endif
